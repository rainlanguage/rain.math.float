//! The `LibDecimalFloat`, `LibFormatDecimalFloat` and `LibParseDecimalFloat`
//! functions `TestDecimalFloat` does not expose, called by their own names on
//! `TestDecimalFloatHarness`, against the exact reference and the Python
//! oracle as strictly as `exact.rs`: the same value, or the same single error.
//! Bytes are compared only where NatSpec documents the representation: a pack
//! of a non-zero coefficient that already fits, and `canonicalize`.

use crate::evm::{self, TestDecimalFloat as T, TestDecimalFloatHarness as H};
use crate::exact::{self as x, Fail, Sol, check_float, config, error_matches, py_float, show};
use crate::oracle::{self, ask};
use crate::reference::{self as r, Dec, I32_MAX, I32_MIN, RefError, pow10};
use alloy::primitives::{I256, U256};
use alloy::sol_types::SolCall;
use num_bigint::BigInt;
use num_traits::{Signed, Zero};
use proptest::prelude::*;
use proptest::test_runner::TestCaseError;
use serde_json::{Value, json};

fn harness<C: SolCall>(c: C) -> Sol<C::Return> {
    evm::harness(c).map_err(Fail::Harness)
}

fn i256(v: &BigInt) -> I256 {
    I256::from_dec_str(&v.to_string()).unwrap()
}

fn big(v: I256) -> BigInt {
    v.to_string().parse().unwrap()
}

/// Exponents the Python oracle's `decimal` context holds.
fn in_python_range(e: &BigInt) -> bool {
    e.abs() < BigInt::from(1_000_000_000_000_000i64)
}

fn py_pair(c: &BigInt, e: &BigInt) -> Value {
    json!([c.to_string(), r::pin(e)])
}

// ---------------------------------------------------------------- strategies

/// Every int256, weighted towards int224's and its own ends, digit-count
/// boundaries and trailing zeros.
fn int256_coefficient() -> BoxedStrategy<BigInt> {
    let sign = any::<bool>();
    prop_oneof![
        2 => any::<[u8; 32]>().prop_map(|b| BigInt::from_signed_bytes_be(&b)),
        3 => (1u64..=77, any::<[u8; 32]>(), sign).prop_map(|(n, b, neg)| {
            let lo = pow10(n - 1);
            let span = pow10(n) - &lo;
            let c = lo + BigInt::from_bytes_be(num_bigint::Sign::Plus, &b) % span;
            if neg { -c } else { c }
        }),
        3 => x::coefficient(),
        1 => prop_oneof![
            Just(r::int256_min()),
            Just(r::int256_max()),
            Just(r::int256_min() + 1),
            Just(r::int256_max() - 1),
        ],
        // Within a few of the int224 bound at some exponent, where the bound
        // one exponent down can be the nearest Float.
        1 => (-1i64..=3, 0u64..=10, any::<u64>(), sign).prop_map(|(d, j, low, neg)| {
            let c = (r::int224_max() + d) * pow10(j) + BigInt::from(low) % pow10(j);
            if neg { -c } else { c }
        }),
        // A few significant digits over many zeros, which shed losslessly.
        1 => (1u32..=99, 60u64..=75, sign).prop_map(|(d, k, neg)| {
            let c = BigInt::from(d) * pow10(k);
            if neg { -c } else { c }
        }),
    ]
    .prop_filter("int256", r::fits_int256)
    .boxed()
}

/// Every int256 exponent, weighted towards int32's ends, where packing
/// lifts, sheds or gives up, and towards int256's ends.
fn int256_exponent() -> BoxedStrategy<BigInt> {
    prop_oneof![
        3 => x::exponent().prop_map(BigInt::from),
        2 => (-90i64..=90).prop_map(|d| BigInt::from(I32_MIN + d)),
        2 => (-90i64..=90).prop_map(|d| BigInt::from(I32_MAX + d)),
        1 => any::<[u8; 32]>().prop_map(|b| BigInt::from_signed_bytes_be(&b)),
        1 => (0i64..=3).prop_map(|d| r::int256_max() - d),
        1 => (0i64..=3).prop_map(|d| r::int256_min() + d),
    ]
    .boxed()
}

fn tolerance() -> BoxedStrategy<Dec> {
    prop_oneof![
        4 => x::float().prop_map(|a| a.abs()).prop_filter("int224", |a| r::fits_int224(&a.c)),
        1 => Just(Dec::zero()),
        1 => x::float(),
    ]
    .boxed()
}

/// `agree`'s arguments: independent, related extremes, and extremes whose
/// spread is exactly a tolerance, or one unit either side of it.
fn agree_args() -> BoxedStrategy<(Dec, Dec, Dec, Dec)> {
    prop_oneof![
        2 => (tolerance(), tolerance(), x::float(), x::float()),
        2 => (tolerance(), tolerance(), x::pair()).prop_map(|(a, p, (l, h))| (a, p, l, h)),
        2 => (x::pair(), tolerance(), -1i64..=1).prop_map(|((l, h), p, d)| {
            let (l, h) = if l.cmp_value(&h).is_gt() { (h, l) } else { (l, h) };
            let absolute = match h.add_exact(&l.neg()).map(|s| r::pack(&s)) {
                Some(r::Packed::Value(s, true)) => {
                    let s = Dec::new(&s.c + d, s.e);
                    if r::fits_int224(&s.c) && s.c.sign() != num_bigint::Sign::Minus { s } else { p.clone() }
                }
                _ => p.clone(),
            };
            (absolute, Dec::zero(), l, h)
        }),
        // A 67-digit proportional within a unit of spread / anchor, so the
        // limit's coefficient product passes 256 bits and `mul` truncates it.
        2 => (x::pair(), -1i64..=1).prop_map(|((l, h), d)| {
            let (l, h) = if l.cmp_value(&h).is_gt() { (h, l) } else { (l, h) };
            let anchor = if l.abs().cmp_value(&h.abs()).is_gt() { l.abs() } else { h.abs() };
            let fallback = (Dec::zero(), Dec::new(1, 0), l.clone(), h.clone());
            let Some(s) = h.add_exact(&l.neg()) else { return fallback };
            if s.is_zero() || anchor.is_zero() {
                return fallback;
            }
            let digits = |v: &BigInt| v.abs().to_string().len() as i64;
            let k = 66 - (digits(&s.c) - digits(&anchor.c));
            let (num, den) = if k >= 0 {
                (&s.c * pow10(k as u64), anchor.c.clone())
            } else {
                (s.c.clone(), &anchor.c * pow10(k.unsigned_abs()))
            };
            let p = Dec::new(num / den + d, s.e - anchor.e - k);
            if r::fits_int224(&p.c) && p.c.is_positive() && (I32_MIN..=I32_MAX).contains(&p.e) {
                (Dec::zero(), p, l, h)
            } else {
                fallback
            }
        }),
        // spread = proportional × anchor: (0, h, 1) and (-h, h, 2).
        1 => (x::float(), any::<bool>(), -1i64..=1).prop_map(|(h, both, d)| {
            let h = h.abs();
            let h = if r::fits_int224(&h.c) { h } else { Dec::new(1, 0) };
            let (l, p) = if both {
                (h.neg(), Dec::new(20 + d, -1))
            } else {
                (Dec::zero(), Dec::new(10 + d, -1))
            };
            (Dec::zero(), p, l, h)
        }),
    ]
    .boxed()
}

/// A character no literal continues with, then anything.
fn suffix() -> BoxedStrategy<String> {
    prop_oneof![
        2 => Just(String::new()),
        1 => (prop_oneof![Just(" "), Just("x"), Just(","), Just(")"), Just("_")], "[0-9a-z.]{0,3}")
            .prop_map(|(c, rest)| format!("{c}{rest}")),
    ]
    .boxed()
}

// ------------------------------------------------------------------ checking
//
// Each check takes what Solidity and python answered, so `checker` can show
// it rejects wrong answers.

/// The same value, or the same single error.
fn judge<V: PartialEq + std::fmt::Debug>(
    case: &str,
    sol: Sol<V>,
    want: Result<V, RefError>,
) -> Result<(), TestCaseError> {
    match (sol, want) {
        (Ok(s), Ok(w)) => prop_assert_eq!(s, w, "{}", case),
        (Err(s), Err(w)) => prop_assert!(
            error_matches(&s, w),
            "{case}: solidity {s:?}, reference {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

/// Python's answer: the same value, or an error of the same name.
fn judge_py<V: PartialEq + std::fmt::Debug>(
    case: &str,
    py: Result<V, String>,
    want: &Result<V, RefError>,
) -> Result<(), TestCaseError> {
    match (py, want) {
        (Ok(p), Ok(w)) => prop_assert_eq!(&p, w, "{}: python", case),
        (Err(p), Err(w)) => prop_assert_eq!(p.as_str(), w.name(), "{}: python", case),
        (p, w) => prop_assert!(false, "{case}: python {p:?}, reference {w:?}"),
    }
    Ok(())
}

fn py_result<V>(py: &Value, ok: impl Fn(&Value) -> V) -> Result<V, String> {
    match (&py["ok"], py["err"].as_str()) {
        (_, Some(e)) => Err(e.to_string()),
        (Value::Null, None) => panic!("oracle response {py}"),
        (v, None) => Ok(ok(v)),
    }
}

/// A value's fields with every trailing zero shed, which equal iff the
/// values do.
fn norm(d: &Dec) -> (BigInt, i64) {
    let n = d.normalized();
    (n.c, n.e)
}

fn py_pack(c: &BigInt, e: &BigInt, op: &str) -> Option<Value> {
    in_python_range(e).then(|| ask(json!({"op": op, "a": py_pair(c, e)})))
}

/// Packing's NatSpec sheds digits "as many times as it takes" to fit, so a
/// non-zero coefficient that already fits int224 at an int32 exponent packs
/// to its own bytes. Any other representation is undocumented (#345).
fn representation_documented(c: &BigInt, e: &BigInt) -> bool {
    !c.is_zero() && r::fits_int224(c) && *e >= BigInt::from(I32_MIN) && *e <= BigInt::from(I32_MAX)
}

/// A packed result and its flag: the reference's value, and its bytes where
/// `documented`, or the same single error.
fn judge_pack<F: PartialEq + std::fmt::Debug>(
    case: &str,
    sol: Sol<(alloy::primitives::B256, F)>,
    want: Result<(Dec, F), RefError>,
    documented: bool,
) -> Result<(), TestCaseError> {
    match (sol, want) {
        (Ok((s, sf)), Ok((w, wf))) => {
            prop_assert_eq!(sf, wf, "{}: flag", case);
            if documented {
                prop_assert_eq!(s, w.to_bytes(), "{}: reference {:?}", case, w);
            } else {
                let s = Dec::from_bytes(s);
                prop_assert!(s.eq_value(&w), "{case}: solidity {s:?}, reference {w:?}");
            }
            Ok(())
        }
        (s, w) => judge(case, s.map(|(s, _)| s), w.map(|(w, _)| w.to_bytes())),
    }
}

/// `packLossy`: the value `pack` fits, the flag, or `ExponentOverflow`.
fn check_pack_lossy(c: &BigInt, e: &BigInt) -> Result<(), TestCaseError> {
    let sol = harness(H::packLossyCall {
        signedCoefficient: i256(c),
        exponent: i256(e),
    });
    check_pack_lossy_with(c, e, py_pack(c, e, "pack"), sol)
}

fn check_pack_lossy_with(
    c: &BigInt,
    e: &BigInt,
    py: Option<Value>,
    sol: Sol<H::packLossyReturn>,
) -> Result<(), TestCaseError> {
    let case = format!("packLossy({c}, {e})");
    let want = r::pack_lossy(c, e);
    if let Some(py) = py {
        // Python reports a value every digit is shed from as the
        // underflow, where `packLossy` returns zero, lossy.
        let py = match py_result(&py, |p| {
            (norm(&oracle::to_dec(&p[0])), p[1].as_bool().unwrap())
        }) {
            Err(u) if u == "ExponentUnderflow" => Ok((norm(&Dec::zero()), false)),
            p => p,
        };
        judge_py(&case, py, &want.clone().map(|(w, l)| (norm(&w), l)))?;
    }
    judge_pack(
        &case,
        sol.map(|s| (s._0, s._1)),
        want,
        representation_documented(c, e),
    )
}

/// A packed result: the reference's value, and its bytes where `documented`.
fn check_packed(
    case: &str,
    sol: Sol<alloy::primitives::B256>,
    want: Result<Dec, RefError>,
    py: Option<Value>,
    documented: bool,
) -> Result<(), TestCaseError> {
    if let (Ok(s), Ok(w), true) = (&sol, &want, documented) {
        prop_assert_eq!(*s, w.to_bytes(), "{}: reference {:?}", case, w);
    }
    let sol = sol.map(Dec::from_bytes);
    match py {
        Some(py) => check_float(case, sol, want, py),
        None => {
            // Past the oracle's range the reference stands alone.
            let want_py = match &want {
                Ok(w) => json!({"ok": oracle::float(w)}),
                Err(e) => json!({"err": e.name()}),
            };
            check_float(case, sol, want, want_py)
        }
    }
}

fn check_pack_lossless(c: &BigInt, e: &BigInt) -> Result<(), TestCaseError> {
    check_packed(
        &format!("packLossless({c}, {e})"),
        harness(H::packLosslessCall {
            signedCoefficient: i256(c),
            exponent: i256(e),
        }),
        r::pack_lossless(c, e),
        py_pack(c, e, "pack_lossless"),
        representation_documented(c, e),
    )
}

fn check_pack_arithmetic(c: &BigInt, e: &BigInt) -> Result<(), TestCaseError> {
    check_packed(
        &format!("packArithmeticResult({c}, {e})"),
        harness(H::packArithmeticResultCall {
            signedCoefficient: i256(c),
            exponent: i256(e),
        }),
        r::pack_arithmetic(c, e),
        py_pack(c, e, "pack_arithmetic"),
        representation_documented(c, e),
    )
}

fn canonical(a: alloy::primitives::B256) -> Sol<alloy::primitives::B256> {
    harness(H::canonicalizeCall { float: a })
}

/// `canonicalize`: the reference's bytes, the same value, idempotent.
fn check_canonicalize(a: &Dec) -> Result<(), TestCaseError> {
    let py = ask(json!({"op": "canonical", "a": oracle::float(a)}));
    check_canonicalize_with(a, py, canonical(a.to_bytes()), canonical)
}

fn check_canonicalize_with(
    a: &Dec,
    py: Value,
    sol: Sol<alloy::primitives::B256>,
    again: impl Fn(alloy::primitives::B256) -> Sol<alloy::primitives::B256>,
) -> Result<(), TestCaseError> {
    let case = format!("canonicalize({})", show(a));
    let want = r::canonicalize(a);
    prop_assert!(
        want.eq_value(a),
        "{case}: reference {want:?} changed the value"
    );
    let p = oracle::to_dec(&py["ok"]);
    judge_py(&case, Ok((p.c, p.e)), &Ok((want.c.clone(), want.e)))?;
    let bytes = sol.as_ref().ok().copied();
    judge(&case, sol, Ok(want.to_bytes()))?;
    if let Some(b) = bytes {
        judge(&format!("{case}: again"), again(b), Ok(b))?;
    }
    Ok(())
}

/// Two floats canonicalize to the same bytes iff they are equal.
fn check_canonical_pair(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let ca = canonical(a.to_bytes()).unwrap();
    let cb = canonical(b.to_bytes()).unwrap();
    prop_assert_eq!(
        ca == cb,
        a.eq_value(b),
        "canonicalize({}) {}, canonicalize({}) {}",
        show(a),
        ca,
        show(b),
        cb
    );
    Ok(())
}

fn check_agree(
    absolute: &Dec,
    proportional: &Dec,
    lowest: &Dec,
    highest: &Dec,
) -> Result<(), TestCaseError> {
    let py = ask(json!({
        "op": "agree",
        "absolute": oracle::float(absolute),
        "proportional": oracle::float(proportional),
        "a": oracle::float(lowest),
        "b": oracle::float(highest),
    }));
    let sol = harness(H::agreeCall {
        absolute: absolute.to_bytes(),
        proportional: proportional.to_bytes(),
        lowest: lowest.to_bytes(),
        highest: highest.to_bytes(),
    });
    check_agree_with([absolute, proportional, lowest, highest], py, sol)
}

fn check_agree_with(args: [&Dec; 4], py: Value, sol: Sol<bool>) -> Result<(), TestCaseError> {
    let [absolute, proportional, lowest, highest] = args;
    let case = format!(
        "agree({}, {}, {}, {})",
        show(absolute),
        show(proportional),
        show(lowest),
        show(highest)
    );
    let want = r::agree(absolute, proportional, lowest, highest);
    judge_py(&case, py_result(&py, |p| p.as_bool().unwrap()), &want)?;
    judge(&case, sol, want)
}

fn check_is_odd(a: &Dec) -> Result<(), TestCaseError> {
    let py = ask(json!({"op": "is_odd", "a": oracle::float(a)}));
    check_is_odd_with(
        a,
        py,
        harness(H::isOddCall {
            float: a.to_bytes(),
        }),
    )
}

fn check_is_odd_with(a: &Dec, py: Value, sol: Sol<bool>) -> Result<(), TestCaseError> {
    let case = format!("isOdd({})", show(a));
    let want = Ok(r::is_odd(a));
    judge_py(&case, py_result(&py, |p| p.as_bool().unwrap()), &want)?;
    judge(&case, sol, want)
}

/// The unpacked conversions: the exact coefficient and exponent.
fn check_from_fixed_unpacked(value: U256, decimals: u8) -> Result<(), TestCaseError> {
    let py =
        ask(json!({"op": "from_fixed_unpacked", "value": value.to_string(), "decimals": decimals}));
    let lossy = harness(H::fromFixedDecimalLossyCall { value, decimals });
    let lossless = harness(H::fromFixedDecimalLosslessCall { value, decimals });
    check_from_fixed_unpacked_with(value, decimals, py, lossy, lossless)
}

fn check_from_fixed_unpacked_with(
    value: U256,
    decimals: u8,
    py: Value,
    lossy: Sol<H::fromFixedDecimalLossyReturn>,
    lossless: Sol<H::fromFixedDecimalLosslessReturn>,
) -> Result<(), TestCaseError> {
    let case = format!("fromFixedDecimalLossy({value}, {decimals}) unpacked");
    let (w, l) = r::from_fixed_decimal_lossy_unpacked(value, decimals);
    let want = Ok((w.c, BigInt::from(w.e), l));
    let py = py_result(&py, |p| {
        let d = oracle::to_dec(&p[0]);
        (d.c, BigInt::from(d.e), p[1].as_bool().unwrap())
    });
    judge_py(&case, py, &want)?;
    judge(&case, lossy.map(|s| (big(s._0), big(s._1), s._2)), want)?;
    let want =
        r::from_fixed_decimal_lossless_unpacked(value, decimals).map(|w| (w.c, BigInt::from(w.e)));
    judge(
        &format!("{case} lossless"),
        lossless.map(|s| (big(s._0), big(s._1))),
        want,
    )
}

fn check_to_fixed_unpacked(c: &BigInt, e: &BigInt, decimals: u8) -> Result<(), TestCaseError> {
    let py = in_python_range(e)
        .then(|| ask(json!({"op": "to_fixed_lossy", "a": py_pair(c, e), "decimals": decimals})));
    let lossy = harness(H::toFixedDecimalLossyCall {
        signedCoefficient: i256(c),
        exponent: i256(e),
        decimals,
    });
    let lossless = harness(H::toFixedDecimalLosslessCall {
        signedCoefficient: i256(c),
        exponent: i256(e),
        decimals,
    });
    check_to_fixed_unpacked_with(c, e, decimals, py, lossy, lossless)
}

fn check_to_fixed_unpacked_with(
    c: &BigInt,
    e: &BigInt,
    decimals: u8,
    py: Option<Value>,
    lossy: Sol<H::toFixedDecimalLossyReturn>,
    lossless: Sol<U256>,
) -> Result<(), TestCaseError> {
    let case = format!("toFixedDecimalLossy({c}, {e}, {decimals})");
    let want = r::to_fixed_decimal_lossy_unpacked(c, e, decimals);
    if let Some(py) = py {
        let py = py_result(&py, |p| {
            (
                U256::from_str_radix(p[0].as_str().unwrap(), 10).unwrap(),
                p[1].as_bool().unwrap(),
            )
        });
        judge_py(&case, py, &want)?;
    }
    judge(&case, lossy.map(|s| (s._0, s._1)), want)?;
    judge(
        &format!("{case} lossless"),
        lossless,
        r::to_fixed_decimal_lossless_unpacked(c, e, decimals),
    )
}

/// `toDecimalString` by its own name: the documented string, which the
/// concrete's `format` must return too.
fn check_to_decimal_string(a: &Dec) -> Result<(), TestCaseError> {
    for (scientific, want) in [(true, r::format_scientific(a)), (false, r::format_plain(a))] {
        let case = format!("toDecimalString({}, {scientific})", show(a));
        let sol = harness(H::toDecimalStringCall {
            float: a.to_bytes(),
            scientific,
        });
        if let (Ok(h), Ok(c)) = (&sol, &x::sol_format(a, scientific)) {
            prop_assert_eq!(h, c, "{}: harness and concrete", case);
        }
        x::check_format_one(&case, a, sol, want)?;
    }
    Ok(())
}

/// `parseDecimalFloatInline` over a literal and a suffix it stops at, and
/// `parseDecimalFloat`, which takes the whole string or reports the excess.
fn check_parse_entry_points(lit: &str, suffix: &str) -> Result<(), TestCaseError> {
    let s = format!("{lit}{suffix}");
    let py = match r::parse_inline(lit) {
        Ok((_, e)) if in_python_range(&e) => Some(ask(json!({"op": "literal", "s": lit}))),
        _ => None,
    };
    let inline = harness(H::parseDecimalFloatInlineCall { str: s.clone() });
    let whole = harness(H::parseDecimalFloatCall { str: s.clone() });
    let concrete = evm::concrete(T::parseCall { str: s });
    check_parse_entry_points_with(lit, suffix, py, inline, whole, concrete)
}

fn check_parse_entry_points_with(
    lit: &str,
    suffix: &str,
    py: Option<Value>,
    inline: Sol<H::parseDecimalFloatInlineReturn>,
    whole: Sol<H::parseDecimalFloatReturn>,
    concrete: Result<T::parseReturn, alloy::primitives::Bytes>,
) -> Result<(), TestCaseError> {
    let s = format!("{lit}{suffix}");
    let case = format!("parseDecimalFloatInline({s:?})");
    let want = r::parse_inline(lit);
    if let (Ok((c, e)), Some(py)) = (&want, py) {
        let p = py_float(&py);
        let w = Dec::new(c.clone(), r::pin(e));
        prop_assert!(
            p.as_ref().is_ok_and(|p| p.eq_value(&w)),
            "{case}: reference {c}e{e}, python {p:?}"
        );
    }
    // The cursor stops at the end of the literal, or reports the error.
    let inline = inline.map(|s| (s._0.0, s._1, big(s._2), big(s._3)));
    let want_inline = match want {
        Ok((c, e)) => Ok(([0u8; 4], U256::from(lit.len()), c, e)),
        Err(w) => Err(w),
    };
    match (inline, want_inline) {
        (Ok((sel, ..)), Err(w)) => {
            prop_assert!(
                error_matches(&Fail::Selector(sel), w),
                "{case}: solidity {sel:?}, reference {w:?}"
            );
        }
        (inline, want) => judge(&case, inline, want)?,
    }

    // Only packing's ExponentOverflow reverts; every other error is a
    // selector.
    let case = format!("parseDecimalFloat({s:?})");
    let (want, reverts) = match r::parse_inline(lit) {
        Err(w) => (Err(w), false),
        Ok(_) if !suffix.is_empty() => (Err(RefError::ParseDecimalFloatExcessCharacters), false),
        Ok(_) => {
            let w = r::parse(lit);
            let reverts = matches!(w, Err(RefError::ExponentOverflow));
            (w, reverts)
        }
    };
    match (&whole, &concrete) {
        (Ok(h), Ok(c)) => {
            prop_assert_eq!((h._0, h._1), (c._0, c._1), "{}: harness and concrete", case)
        }
        (Err(Fail::Harness(h)), Err(c)) => prop_assert_eq!(h, c, "{}: harness and concrete", case),
        (h, c) => prop_assert!(false, "{case}: harness {h:?}, concrete {c:?}"),
    }
    match (whole, want) {
        (Ok(s), Ok(w)) => {
            prop_assert_eq!(s._0.0, [0u8; 4], "{}: error", case);
            // NatSpec documents the value, not its representation (#345).
            let s = Dec::from_bytes(s._1);
            prop_assert!(s.eq_value(&w), "{case}: solidity {s:?}, reference {w:?}");
        }
        (Ok(s), Err(w)) if !reverts => {
            prop_assert!(
                error_matches(&Fail::Selector(s._0.0), w),
                "{case}: solidity {:?}, reference {w:?}",
                s._0
            );
            prop_assert!(s._1.is_zero(), "{}: an error returns zero", case);
        }
        (Err(s), Err(w)) if reverts => prop_assert!(
            error_matches(&s, w),
            "{case}: solidity {s:?}, reference {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

proptest! {
    #![proptest_config(config())]

    #[test]
    fn library_pack(c in int256_coefficient(), e in int256_exponent()) {
        check_pack_lossy(&c, &e)?;
        check_pack_lossless(&c, &e)?;
        check_pack_arithmetic(&c, &e)?;
    }

    #[test]
    fn library_canonicalize(a in x::float()) { check_canonicalize(&a)?; }

    #[test]
    fn library_canonical_pair((a, b) in x::pair()) { check_canonical_pair(&a, &b)?; }

    #[test]
    fn library_agree((absolute, proportional, lowest, highest) in agree_args()) {
        check_agree(&absolute, &proportional, &lowest, &highest)?;
    }

    #[test]
    fn library_is_odd(a in x::float()) { check_is_odd(&a)?; }

    #[test]
    fn library_from_fixed_unpacked(value in x::u256(), decimals in any::<u8>()) {
        check_from_fixed_unpacked(value, decimals)?;
    }

    #[test]
    fn library_to_fixed_unpacked(
        c in int256_coefficient(),
        e in prop_oneof![int256_exponent(), (-90i64..=90).prop_map(BigInt::from)],
        decimals in any::<u8>(),
    ) {
        check_to_fixed_unpacked(&c, &e, decimals)?;
    }

    #[test]
    fn library_to_decimal_string(a in x::float()) { check_to_decimal_string(&a)?; }

    #[test]
    fn library_parse(lit in x::literal(), suffix in suffix()) {
        check_parse_entry_points(&lit, &suffix)?;
    }
}

fn run(r: Result<(), TestCaseError>) {
    if let Err(e) = r {
        panic!("{e}");
    }
}

/// Packing at each edge the fuzzer may miss: the int32 floor with every
/// shortfall up to and past a whole int224, the ceiling lift, and the
/// coefficients past 1e72 the packing sheds five digits from at once.
#[test]
fn library_pack_edges() {
    let floor = BigInt::from(I32_MIN);
    for shortfall in 60i64..=70 {
        for c in [
            r::int224_max(),
            r::int224_min(),
            pow10(67),
            pow10(67) * 2 + 1,
        ] {
            let e = &floor - shortfall;
            run(check_pack_lossy(&c, &e));
            run(check_pack_lossless(&c, &e));
            run(check_pack_arithmetic(&c, &e));
        }
    }
    for excess in 0i64..=70 {
        for c in [
            BigInt::from(1),
            BigInt::from(-1),
            BigInt::from(26),
            pow10(66),
            r::int224_max() / 10,
        ] {
            let e = BigInt::from(I32_MAX + excess);
            run(check_pack_lossy(&c, &e));
            run(check_pack_lossless(&c, &e));
        }
    }
    for k in 70u64..=76 {
        for d in [0i64, 1, 12345, -1] {
            let c = pow10(k) + d;
            if r::fits_int256(&c) {
                for e in [
                    BigInt::from(0),
                    BigInt::from(I32_MAX - 3),
                    BigInt::from(I32_MIN),
                ] {
                    run(check_pack_lossy(&c, &e));
                    run(check_pack_lossy(&-c.clone(), &e));
                }
            }
        }
    }
}

/// #326 and #332: a value just past int224 packs as the bound one exponent
/// down when that is nearer than shedding a digit, at the exponent ceiling
/// too, and not when the bound's exponent is below the floor.
#[test]
fn library_pack_nearest_bound() {
    let two223 = -r::int224_min();
    let cases = [
        (two223.clone(), 0i64, Some((r::int224_max(), 0i64, false))),
        (two223.clone() + 1, 0, Some((r::int224_max(), 0, false))),
        (
            two223.clone() + 2,
            0,
            Some(((two223.clone() + 2) / 10, 1, true)),
        ),
        (
            two223.clone() * 10 + 9,
            0,
            Some((r::int224_max(), 1, false)),
        ),
        (-two223.clone() - 1, 0, Some((r::int224_min(), 0, false))),
        (
            -two223.clone() - 2,
            0,
            Some(((-two223.clone() - 2) / 10, 1, true)),
        ),
        (
            two223.clone(),
            I32_MAX,
            Some((r::int224_max(), I32_MAX, false)),
        ),
        (two223.clone() + 2, I32_MAX, None),
        (
            two223.clone(),
            I32_MIN - 1,
            Some((two223.clone() / 10, I32_MIN, false)),
        ),
        (
            two223.clone(),
            I32_MIN,
            Some((r::int224_max(), I32_MIN, false)),
        ),
    ];
    for (c, e, want) in cases {
        let e = BigInt::from(e);
        let got = r::pack_lossy(&c, &e);
        match want {
            Some((wc, we, wl)) => {
                let (v, lossless) = got.unwrap();
                let w = Dec::new(wc, we);
                assert!(v.eq_value(&w), "packLossy({c}, {e}): {v:?}, want {w:?}");
                assert_eq!(lossless, wl, "packLossy({c}, {e}) lossless");
            }
            None => assert_eq!(got.unwrap_err(), r::RefError::ExponentOverflow),
        }
        run(check_pack_lossy(&c, &e));
        run(check_pack_lossless(&c, &e));
        run(check_pack_arithmetic(&c, &e));
    }
}

/// Every whole number in each representation down to 68 digits, and its
/// neighbours, which are not whole.
#[test]
fn library_is_odd_every_representation() {
    for k in 0u64..=67 {
        for m in [1i64, 2, 3, 7, 10, 25] {
            for off in [0i64, 1, -1] {
                let c = BigInt::from(m) * pow10(k) + off;
                for c in [c.clone(), -c] {
                    if r::fits_int224(&c) {
                        run(check_is_odd(&Dec::new(c, -(k as i64))));
                    }
                }
            }
        }
    }
    for e in 1i64..=3 {
        for c in -3i64..=3 {
            run(check_is_odd(&Dec::new(c, e)));
        }
    }
}

/// The documented boundary case: a spread of `1 + 1e-100` aligned to
/// exactly `1`, which `1 <= 1` accepts.
#[test]
fn library_agree_documented_boundary() {
    let want = r::agree(
        &Dec::zero(),
        &Dec::new(1, 0),
        &Dec::new(-1, -100),
        &Dec::new(1, 0),
    );
    assert_eq!(want, Ok(true));
    run(check_agree(
        &Dec::zero(),
        &Dec::new(1, 0),
        &Dec::new(-1, -100),
        &Dec::new(1, 0),
    ));
}

/// The two tolerance errors, for each sign of each tolerance and every
/// representation of zero.
#[test]
fn library_agree_tolerance_errors() {
    let values = [
        Dec::zero(),
        Dec::new(0, 5),
        Dec::new(0, -5),
        Dec::new(1, -3),
        Dec::new(-1, -3),
    ];
    for a in &values {
        for p in &values {
            run(check_agree(a, p, &Dec::new(1, 0), &Dec::new(2, 0)));
        }
    }
}

/// The unpacked `toFixedDecimalLossy` where `exponent + decimals` passes
/// int256.max, which no packed Float reaches.
#[test]
fn library_to_fixed_exponent_wrap() {
    for d in 0i64..=3 {
        for decimals in [0u8, 1, 4, 255] {
            run(check_to_fixed_unpacked(
                &BigInt::from(1),
                &(r::int256_max() - d),
                decimals,
            ));
        }
    }
}

/// `exponent + decimals` either side of 77, the last power of ten in a
/// uint256, for coefficients a scale past it would and would not overflow.
#[test]
fn library_to_fixed_overflow_boundary() {
    for c in [1i64, 2, 9, 11, 115, 116] {
        for (e, decimals) in [
            (76i64, 0u8),
            (77, 0),
            (78, 0),
            (79, 0),
            (0, 77),
            (0, 78),
            (60, 18),
        ] {
            run(check_to_fixed_unpacked(
                &BigInt::from(c),
                &BigInt::from(e),
                decimals,
            ));
        }
    }
}

/// A spread one to nine units past the absolute tolerance in the last digit
/// of the alignment, and one the alignment sheds whole.
#[test]
fn library_agree_last_aligned_digit() {
    for r in 1i64..=9 {
        for e in [-74i64, -75, -76] {
            run(check_agree(
                &Dec::new(1, 0),
                &Dec::zero(),
                &Dec::new(-r, e),
                &Dec::new(1, 0),
            ));
        }
    }
}

/// A zero literal parses to exponent zero however it is written.
#[test]
fn library_parse_zero() {
    for lit in ["0", "0.000", "0e5", "0e-5", "-0.0e3", "00.00e-1"] {
        run(check_parse_entry_points(lit, ""));
        run(check_parse_entry_points(lit, " x"));
    }
}

/// Each check against Solidity and python answers that are wrong.
mod checker {
    use super::*;
    use alloy::primitives::B256;

    fn one() -> Dec {
        Dec::new(1, 0)
    }

    fn two() -> Dec {
        Dec::new(2, 0)
    }

    /// A real `AgreeToleranceNegative` revert, and a real
    /// `AgreeNoPositiveTolerance` one.
    fn negative() -> Fail {
        harness(H::agreeCall {
            absolute: one().neg().to_bytes(),
            proportional: Dec::zero().to_bytes(),
            lowest: one().to_bytes(),
            highest: one().to_bytes(),
        })
        .unwrap_err()
    }

    fn no_positive() -> Fail {
        harness(H::agreeCall {
            absolute: Dec::zero().to_bytes(),
            proportional: Dec::zero().to_bytes(),
            lowest: one().to_bytes(),
            highest: one().to_bytes(),
        })
        .unwrap_err()
    }

    #[test]
    fn judge_rejects_wrong_solidity() {
        let neg = RefError::AgreeToleranceNegative;
        assert!(judge("checker", Ok(1), Ok(1)).is_ok());
        assert!(judge("checker", Ok(2), Ok(1)).is_err());
        assert!(judge("checker", Err(negative()), Ok(1)).is_err());
        assert!(judge("checker", Ok(1), Err(neg)).is_err());
        assert!(judge::<u8>("checker", Err(negative()), Err(neg)).is_ok());
        assert!(judge::<u8>("checker", Err(no_positive()), Err(neg)).is_err());
    }

    #[test]
    fn judge_py_rejects_wrong_python() {
        let neg = RefError::AgreeToleranceNegative;
        assert!(judge_py("checker", Ok(1), &Ok(1)).is_ok());
        assert!(judge_py("checker", Ok(2), &Ok(1)).is_err());
        assert!(judge_py("checker", Err("AgreeToleranceNegative".into()), &Ok(1)).is_err());
        assert!(judge_py("checker", Ok(1), &Err(neg)).is_err());
        assert!(judge_py::<u8>("checker", Err("AgreeToleranceNegative".into()), &Err(neg)).is_ok());
        assert!(
            judge_py::<u8>("checker", Err("AgreeNoPositiveTolerance".into()), &Err(neg)).is_err()
        );
    }

    #[test]
    fn py_result_reads_ok_and_err() {
        assert_eq!(
            py_result(&json!({"ok": true}), |p| p.as_bool().unwrap()),
            Ok(true)
        );
        assert_eq!(
            py_result(&json!({"ok": false}), |p| p.as_bool().unwrap()),
            Ok(false)
        );
        assert_eq!(
            py_result(&json!({"err": "Log10Zero"}), |p| p.as_bool().unwrap()),
            Err("Log10Zero".to_string())
        );
    }

    fn pack_lossy_accepts(py: Value, value: Dec, lossless: bool) -> bool {
        let sol = Ok(H::packLossyReturn {
            _0: value.to_bytes(),
            _1: lossless,
        });
        check_pack_lossy_with(&BigInt::from(1), &BigInt::from(0), Some(py), sol).is_ok()
    }

    #[test]
    fn pack_lossy_rejects_wrong_answers() {
        let py = || json!({"ok": [["1", 0], true]});
        assert!(pack_lossy_accepts(py(), one(), true));
        assert!(pack_lossy_accepts(
            json!({"ok": [["10", -1], true]}),
            one(),
            true
        ));
        assert!(!pack_lossy_accepts(py(), two(), true));
        assert!(!pack_lossy_accepts(py(), one(), false));
        // The same value in other bytes.
        assert!(!pack_lossy_accepts(py(), Dec::new(10, -1), true));
        assert!(!pack_lossy_accepts(
            json!({"ok": [["2", 0], true]}),
            one(),
            true
        ));
        assert!(!pack_lossy_accepts(
            json!({"ok": [["1", 0], false]}),
            one(),
            true
        ));
        assert!(!pack_lossy_accepts(
            json!({"err": "ExponentUnderflow"}),
            one(),
            true
        ));
        // A value every digit is shed from is zero, lossy, where python
        // reports the underflow.
        let (c, e) = (BigInt::from(1), BigInt::from(I32_MIN - 80));
        let zero = || {
            Ok(H::packLossyReturn {
                _0: Dec::zero().to_bytes(),
                _1: false,
            })
        };
        let underflow = || Some(json!({"err": "ExponentUnderflow"}));
        assert!(check_pack_lossy_with(&c, &e, underflow(), zero()).is_ok());
        assert!(
            check_pack_lossy_with(&c, &e, Some(json!({"err": "ExponentOverflow"})), zero())
                .is_err()
        );
        let lossless = Ok(H::packLossyReturn {
            _0: Dec::zero().to_bytes(),
            _1: true,
        });
        assert!(check_pack_lossy_with(&c, &e, underflow(), lossless).is_err());
        // 10^70 does not fit int224, so its representation is undocumented:
        // any bytes of its value are accepted, and no other value.
        let (c, e) = (pow10(70), BigInt::from(0));
        let py = || Some(json!({"ok": [["1", 70], true]}));
        let packed = |v: Dec, l: bool| {
            Ok(H::packLossyReturn {
                _0: v.to_bytes(),
                _1: l,
            })
        };
        for v in [
            Dec::new(pow10(66), 4),
            Dec::new(pow10(67), 3),
            Dec::new(1, 70),
        ] {
            assert!(check_pack_lossy_with(&c, &e, py(), packed(v, true)).is_ok());
        }
        assert!(check_pack_lossy_with(&c, &e, py(), packed(Dec::new(1, 70), false)).is_err());
        assert!(check_pack_lossy_with(&c, &e, py(), packed(Dec::new(2, 70), true)).is_err());
    }

    #[test]
    fn packed_rejects_other_bytes() {
        let py = || Some(json!({"ok": ["1", 0]}));
        assert!(check_packed("checker", Ok(one().to_bytes()), Ok(one()), py(), true).is_ok());
        assert!(
            check_packed(
                "checker",
                Ok(Dec::new(10, -1).to_bytes()),
                Ok(one()),
                py(),
                true
            )
            .is_err()
        );
        assert!(check_packed("checker", Ok(two().to_bytes()), Ok(one()), None, true).is_err());
        // Undocumented: another representation of the value is accepted,
        // another value is not.
        assert!(
            check_packed(
                "checker",
                Ok(Dec::new(10, -1).to_bytes()),
                Ok(one()),
                py(),
                false
            )
            .is_ok()
        );
        assert!(check_packed("checker", Ok(two().to_bytes()), Ok(one()), py(), false).is_err());
    }

    fn canonicalize_accepts(py: Value, sol: Dec, again: Dec) -> bool {
        check_canonicalize_with(&one(), py, Ok(sol.to_bytes()), |_| Ok(again.to_bytes())).is_ok()
    }

    #[test]
    fn canonicalize_rejects_wrong_answers() {
        let want = r::canonicalize(&one());
        let py = || json!({"ok": [want.c.to_string(), want.e]});
        assert!(canonicalize_accepts(py(), want.clone(), want.clone()));
        // The same value in other bytes, from Solidity or python.
        assert!(!canonicalize_accepts(py(), one(), want.clone()));
        assert!(!canonicalize_accepts(py(), one(), one()));
        assert!(!canonicalize_accepts(
            json!({"ok": ["1", 0]}),
            want.clone(),
            want.clone()
        ));
        // Not idempotent.
        assert!(!canonicalize_accepts(py(), want.clone(), one()));
    }

    fn agree_args() -> [Dec; 4] {
        [Dec::zero(), one(), one(), two()]
    }

    fn agree_accepts(args: [Dec; 4], py: Value, sol: Sol<bool>) -> bool {
        let [a, p, l, h] = &args;
        check_agree_with([a, p, l, h], py, sol).is_ok()
    }

    #[test]
    fn agree_rejects_wrong_answers() {
        // A spread of 1 against a limit of 2.
        assert!(agree_accepts(agree_args(), json!({"ok": true}), Ok(true)));
        assert!(!agree_accepts(agree_args(), json!({"ok": true}), Ok(false)));
        assert!(!agree_accepts(agree_args(), json!({"ok": false}), Ok(true)));
        assert!(!agree_accepts(
            agree_args(),
            json!({"ok": true}),
            Err(negative())
        ));
        let bad = [one().neg(), Dec::zero(), one(), two()];
        let py = || json!({"err": "AgreeToleranceNegative"});
        assert!(agree_accepts(bad.clone(), py(), Err(negative())));
        assert!(!agree_accepts(bad.clone(), py(), Err(no_positive())));
        assert!(!agree_accepts(
            bad.clone(),
            json!({"err": "AgreeNoPositiveTolerance"}),
            Err(negative())
        ));
        assert!(!agree_accepts(bad, py(), Ok(false)));
    }

    #[test]
    fn is_odd_rejects_wrong_answers() {
        assert!(check_is_odd_with(&one(), json!({"ok": true}), Ok(true)).is_ok());
        assert!(check_is_odd_with(&one(), json!({"ok": true}), Ok(false)).is_err());
        assert!(check_is_odd_with(&one(), json!({"ok": false}), Ok(true)).is_err());
        assert!(check_is_odd_with(&two(), json!({"ok": false}), Ok(false)).is_ok());
    }

    /// `2^256 - 1` sheds its last digit, a 5.
    fn from_fixed_accepts(
        py: Value,
        lossy: (BigInt, i64, bool),
        lossless: Sol<H::fromFixedDecimalLosslessReturn>,
    ) -> bool {
        let (c, e, l) = lossy;
        let lossy = Ok(H::fromFixedDecimalLossyReturn {
            _0: i256(&c),
            _1: i256(&BigInt::from(e)),
            _2: l,
        });
        check_from_fixed_unpacked_with(U256::MAX, 3, py, lossy, lossless).is_ok()
    }

    #[test]
    fn from_fixed_rejects_wrong_answers() {
        let shed = r::u256_to_big(U256::MAX) / 10;
        let lossless = || {
            harness(H::fromFixedDecimalLosslessCall {
                value: U256::MAX,
                decimals: 3,
            })
        };
        let py = |c: &BigInt, e: i64, l: bool| json!({"ok": [[c.to_string(), e], l]});
        assert!(from_fixed_accepts(
            py(&shed, -2, false),
            (shed.clone(), -2, false),
            lossless()
        ));
        assert!(!from_fixed_accepts(
            py(&shed, -2, false),
            (shed.clone(), -3, false),
            lossless()
        ));
        assert!(!from_fixed_accepts(
            py(&shed, -2, false),
            (shed.clone() - 1, -2, false),
            lossless()
        ));
        assert!(!from_fixed_accepts(
            py(&shed, -2, false),
            (shed.clone(), -2, true),
            lossless()
        ));
        assert!(!from_fixed_accepts(
            py(&shed, -3, false),
            (shed.clone(), -2, false),
            lossless()
        ));
        assert!(!from_fixed_accepts(
            py(&shed, -2, true),
            (shed.clone(), -2, false),
            lossless()
        ));
        let value = Ok(H::fromFixedDecimalLosslessReturn {
            _0: i256(&shed),
            _1: i256(&BigInt::from(-2)),
        });
        assert!(!from_fixed_accepts(
            py(&shed, -2, false),
            (shed.clone(), -2, false),
            value
        ));
    }

    fn to_fixed_accepts(py: Option<Value>, lossy: (u64, bool), lossless: Sol<U256>) -> bool {
        let lossy = Ok(H::toFixedDecimalLossyReturn {
            _0: U256::from(lossy.0),
            _1: lossy.1,
        });
        // 15e-1 at 0 decimals: 1, lossy.
        check_to_fixed_unpacked_with(&BigInt::from(15), &BigInt::from(-1), 0, py, lossy, lossless)
            .is_ok()
    }

    #[test]
    fn to_fixed_rejects_wrong_answers() {
        let lossless = || {
            harness(H::toFixedDecimalLosslessCall {
                signedCoefficient: i256(&BigInt::from(15)),
                exponent: i256(&BigInt::from(-1)),
                decimals: 0,
            })
        };
        let py = || Some(json!({"ok": ["1", false]}));
        assert!(to_fixed_accepts(py(), (1, false), lossless()));
        assert!(to_fixed_accepts(None, (1, false), lossless()));
        assert!(!to_fixed_accepts(py(), (2, false), lossless()));
        assert!(!to_fixed_accepts(py(), (1, true), lossless()));
        assert!(!to_fixed_accepts(
            Some(json!({"ok": ["2", false]})),
            (1, false),
            lossless()
        ));
        assert!(!to_fixed_accepts(
            Some(json!({"ok": ["1", true]})),
            (1, false),
            lossless()
        ));
        assert!(!to_fixed_accepts(py(), (1, false), Ok(U256::from(1))));
    }

    fn inline(
        selector: [u8; 4],
        cursor: u64,
        c: i64,
        e: i64,
    ) -> Sol<H::parseDecimalFloatInlineReturn> {
        Ok(H::parseDecimalFloatInlineReturn {
            _0: selector.into(),
            _1: U256::from(cursor),
            _2: i256(&BigInt::from(c)),
            _3: i256(&BigInt::from(e)),
        })
    }

    fn whole(selector: [u8; 4], value: B256) -> Sol<H::parseDecimalFloatReturn> {
        Ok(H::parseDecimalFloatReturn {
            _0: selector.into(),
            _1: value,
        })
    }

    fn concrete(
        selector: [u8; 4],
        value: B256,
    ) -> Result<T::parseReturn, alloy::primitives::Bytes> {
        Ok(T::parseReturn {
            _0: selector.into(),
            _1: value,
        })
    }

    fn parse_accepts(
        suffix: &str,
        py: Option<Value>,
        i: Sol<H::parseDecimalFloatInlineReturn>,
        w: Sol<H::parseDecimalFloatReturn>,
        c: Result<T::parseReturn, alloy::primitives::Bytes>,
    ) -> bool {
        check_parse_entry_points_with("15e-1", suffix, py, i, w, c).is_ok()
    }

    #[test]
    fn parse_rejects_wrong_answers() {
        let none = [0u8; 4];
        let v = Dec::new(15, -1).to_bytes();
        let py = || Some(json!({"ok": ["15", -1]}));
        assert!(parse_accepts(
            "",
            py(),
            inline(none, 5, 15, -1),
            whole(none, v),
            concrete(none, v)
        ));
        // The inline parse.
        assert!(!parse_accepts(
            "",
            Some(json!({"ok": ["16", -1]})),
            inline(none, 5, 15, -1),
            whole(none, v),
            concrete(none, v)
        ));
        assert!(!parse_accepts(
            "",
            py(),
            inline(none, 4, 15, -1),
            whole(none, v),
            concrete(none, v)
        ));
        assert!(!parse_accepts(
            "",
            py(),
            inline(none, 5, 16, -1),
            whole(none, v),
            concrete(none, v)
        ));
        assert!(!parse_accepts(
            "",
            py(),
            inline(none, 5, 15, -2),
            whole(none, v),
            concrete(none, v)
        ));
        let loss = RefError::ParseDecimalPrecisionLoss.selector();
        assert!(!parse_accepts(
            "",
            py(),
            inline(loss, 5, 15, -1),
            whole(none, v),
            concrete(none, v)
        ));
        // The whole parse: another representation of the value is accepted,
        // as NatSpec documents no representation.
        let same = Dec::new(150, -2).to_bytes();
        assert!(parse_accepts(
            "",
            py(),
            inline(none, 5, 15, -1),
            whole(none, same),
            concrete(none, same)
        ));
        let other = Dec::new(16, -1).to_bytes();
        assert!(!parse_accepts(
            "",
            py(),
            inline(none, 5, 15, -1),
            whole(none, other),
            concrete(none, other)
        ));
        assert!(!parse_accepts(
            "",
            py(),
            inline(none, 5, 15, -1),
            whole(none, v),
            concrete(none, other)
        ));
        assert!(!parse_accepts(
            "",
            py(),
            inline(none, 5, 15, -1),
            whole(loss, B256::ZERO),
            concrete(loss, B256::ZERO)
        ));
        // The right value under an error selector.
        assert!(!parse_accepts(
            "",
            py(),
            inline(none, 5, 15, -1),
            whole(loss, v),
            concrete(loss, v)
        ));
        // Excess characters: a selector and zero.
        let excess = RefError::ParseDecimalFloatExcessCharacters.selector();
        assert!(parse_accepts(
            " x",
            py(),
            inline(none, 5, 15, -1),
            whole(excess, B256::ZERO),
            concrete(excess, B256::ZERO)
        ));
        assert!(!parse_accepts(
            " x",
            py(),
            inline(none, 5, 15, -1),
            whole(excess, v),
            concrete(excess, v)
        ));
        assert!(!parse_accepts(
            " x",
            py(),
            inline(none, 5, 15, -1),
            whole(loss, B256::ZERO),
            concrete(loss, B256::ZERO)
        ));
        assert!(!parse_accepts(
            " x",
            py(),
            inline(none, 5, 15, -1),
            whole(none, v),
            concrete(none, v)
        ));
    }

    /// Past every Float the whole parse reverts, from both contracts alike.
    #[test]
    fn parse_overflow_must_revert() {
        let lit = "1e3000000000";
        let s = || lit.to_string();
        let inline = || harness(H::parseDecimalFloatInlineCall { str: s() });
        let sol = harness(H::parseDecimalFloatCall { str: s() });
        let c = evm::concrete(T::parseCall { str: s() });
        let revert = c.clone().unwrap_err();
        assert!(check_parse_entry_points_with(lit, "", None, inline(), sol, c).is_ok());
        let none = [0u8; 4];
        let loss = RefError::ParseDecimalPrecisionLoss.selector();
        assert!(
            check_parse_entry_points_with(
                lit,
                "",
                None,
                inline(),
                whole(loss, B256::ZERO),
                concrete(loss, B256::ZERO)
            )
            .is_err()
        );
        assert!(
            check_parse_entry_points_with(
                lit,
                "",
                None,
                inline(),
                Err(Fail::Harness(revert.clone())),
                concrete(none, B256::ZERO)
            )
            .is_err()
        );
        let other = no_positive();
        let Fail::Harness(other) = other else {
            unreachable!()
        };
        assert!(
            check_parse_entry_points_with(
                lit,
                "",
                None,
                inline(),
                Err(Fail::Harness(other.clone())),
                Err(other)
            )
            .is_err()
        );
    }

    /// An inline exponent below int256 is the precision loss selector, never
    /// a revert and never ExponentOverflow.
    #[test]
    fn parse_inline_exponent_wrap_is_a_selector() {
        let lit = format!("9.1e{}", r::int256_min());
        let inline = || harness(H::parseDecimalFloatInlineCall { str: lit.clone() });
        let loss = RefError::ParseDecimalPrecisionLoss.selector();
        assert!(
            check_parse_entry_points_with(
                &lit,
                "",
                None,
                inline(),
                whole(loss, B256::ZERO),
                concrete(loss, B256::ZERO)
            )
            .is_ok()
        );
        let revert = evm::concrete(T::parseCall {
            str: "1e3000000000".into(),
        })
        .unwrap_err();
        assert!(
            check_parse_entry_points_with(
                &lit,
                "",
                None,
                inline(),
                Err(Fail::Harness(revert.clone())),
                Err(revert)
            )
            .is_err()
        );
        let eo = RefError::ExponentOverflow.selector();
        let wrong = Ok(H::parseDecimalFloatInlineReturn {
            _0: eo.into(),
            _1: U256::ZERO,
            _2: I256::ZERO,
            _3: I256::ZERO,
        });
        assert!(
            check_parse_entry_points_with(
                &lit,
                "",
                None,
                wrong,
                whole(loss, B256::ZERO),
                concrete(loss, B256::ZERO)
            )
            .is_err()
        );
    }
}

/// A fraction's exponent below an int256.min exponent: the inline parse's
/// `ParseDecimalPrecisionLoss` selector, before any packing.
#[test]
fn library_parse_exponent_wrap() {
    let min = r::int256_min();
    for lit in [
        format!("9.1e{min}"),
        format!("-9.1e{min}"),
        format!("9.12e{}", &min + 1),
        format!("9.1e{}", &min + 1),
        format!("0.5e{min}"),
    ] {
        run(check_parse_entry_points(&lit, ""));
        run(check_parse_entry_points(&lit, " x"));
    }
}
