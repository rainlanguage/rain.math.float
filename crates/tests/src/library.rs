//! The `LibDecimalFloat`, `LibFormatDecimalFloat` and `LibParseDecimalFloat`
//! functions `TestDecimalFloat` does not expose, called by their own names on
//! `TestDecimalFloatHarness`, against the exact reference and the Python
//! oracle as strictly as `exact.rs`: the same bytes, or the same single error.

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

fn py_pack(c: &BigInt, e: &BigInt, op: &str) -> Option<Value> {
    in_python_range(e).then(|| ask(json!({"op": op, "a": py_pair(c, e)})))
}

/// `packLossy`: the bytes `pack` fits, the flag, or `ExponentOverflow`.
fn check_pack_lossy(c: &BigInt, e: &BigInt) -> Result<(), TestCaseError> {
    let case = format!("packLossy({c}, {e})");
    let want = r::pack_lossy(c, e);
    if let Some(py) = py_pack(c, e, "pack") {
        match (&want, &py["ok"], py["err"].as_str()) {
            (Ok((w, l)), Value::Array(p), _) => {
                let v = oracle::to_dec(&p[0]);
                prop_assert!(w.eq_value(&v), "{case}: reference {w:?}, python {v:?}");
                prop_assert_eq!(p[1].as_bool().unwrap(), *l, "{}: python lossless", case);
            }
            (Ok((w, false)), _, Some("ExponentUnderflow")) if w.is_zero() => {}
            (Err(w), _, Some(p)) => prop_assert_eq!(w.name(), p, "{}: python", case),
            _ => prop_assert!(false, "{case}: reference {want:?}, python {py}"),
        }
    }
    let sol = harness(H::packLossyCall {
        signedCoefficient: i256(c),
        exponent: i256(e),
    });
    match (sol, want) {
        (Ok(s), Ok((w, l))) => {
            prop_assert_eq!(s._0, w.to_bytes(), "{}: reference {:?}", case, w);
            prop_assert_eq!(s._1, l, "{}: lossless", case);
        }
        (Err(s), Err(w)) => prop_assert!(error_matches(&s, w), "{case}: solidity {s:?}, reference {w:?}"),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

/// A packed result must be the reference's bytes, not only its value.
fn check_packed(case: &str, sol: Sol<alloy::primitives::B256>, want: Result<Dec, RefError>, py: Option<Value>) -> Result<(), TestCaseError> {
    if let (Ok(s), Ok(w)) = (&sol, &want) {
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
    )
}

/// `canonicalize`: the reference's bytes, the same value, idempotent.
fn check_canonicalize(a: &Dec) -> Result<(), TestCaseError> {
    let case = format!("canonicalize({})", show(a));
    let want = r::canonicalize(a);
    let p = oracle::to_dec(&ask(json!({"op": "canonical", "a": oracle::float(a)}))["ok"]);
    prop_assert!(
        p.c == want.c && p.e == want.e,
        "{case}: reference {want:?}, python {p:?}"
    );
    prop_assert!(want.eq_value(a), "{case}: reference {want:?} changed the value");
    let sol = harness(H::canonicalizeCall { float: a.to_bytes() }).unwrap();
    prop_assert_eq!(sol, want.to_bytes(), "{}: reference {:?}", case, want);
    let again = harness(H::canonicalizeCall { float: sol }).unwrap();
    prop_assert_eq!(again, sol, "{}: not idempotent", case);
    Ok(())
}

/// Two floats canonicalize to the same bytes iff they are equal.
fn check_canonical_pair(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let ca = harness(H::canonicalizeCall { float: a.to_bytes() }).unwrap();
    let cb = harness(H::canonicalizeCall { float: b.to_bytes() }).unwrap();
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

fn check_agree(absolute: &Dec, proportional: &Dec, lowest: &Dec, highest: &Dec) -> Result<(), TestCaseError> {
    let case = format!(
        "agree({}, {}, {}, {})",
        show(absolute),
        show(proportional),
        show(lowest),
        show(highest)
    );
    let want = r::agree(absolute, proportional, lowest, highest);
    let py = ask(json!({
        "op": "agree",
        "absolute": oracle::float(absolute),
        "proportional": oracle::float(proportional),
        "a": oracle::float(lowest),
        "b": oracle::float(highest),
    }));
    match (&want, &py["ok"], py["err"].as_str()) {
        (Ok(w), Value::Bool(p), _) => prop_assert_eq!(w, p, "{}: python", case),
        (Err(w), _, Some(p)) => prop_assert_eq!(w.name(), p, "{}: python", case),
        _ => prop_assert!(false, "{case}: reference {want:?}, python {py}"),
    }
    let sol = harness(H::agreeCall {
        absolute: absolute.to_bytes(),
        proportional: proportional.to_bytes(),
        lowest: lowest.to_bytes(),
        highest: highest.to_bytes(),
    });
    match (sol, want) {
        (Ok(s), Ok(w)) => prop_assert_eq!(s, w, "{}", case),
        (Err(s), Err(w)) => prop_assert!(error_matches(&s, w), "{case}: solidity {s:?}, reference {w:?}"),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

fn check_is_odd(a: &Dec) -> Result<(), TestCaseError> {
    let case = format!("isOdd({})", show(a));
    let want = r::is_odd(a);
    let py = ask(json!({"op": "is_odd", "a": oracle::float(a)}))["ok"].as_bool().unwrap();
    prop_assert_eq!(py, want, "{}: python", case);
    let sol = harness(H::isOddCall { float: a.to_bytes() }).unwrap();
    prop_assert_eq!(sol, want, "{}", case);
    Ok(())
}

/// The unpacked conversions: the exact coefficient and exponent.
fn check_from_fixed_unpacked(value: U256, decimals: u8) -> Result<(), TestCaseError> {
    let case = format!("fromFixedDecimalLossy({value}, {decimals}) unpacked");
    let (want, lossless) = r::from_fixed_decimal_lossy_unpacked(value, decimals);
    let py = ask(json!({"op": "from_fixed_unpacked", "value": value.to_string(), "decimals": decimals}));
    let p = oracle::to_dec(&py["ok"][0]);
    prop_assert!(p.c == want.c && p.e == want.e, "{case}: reference {want:?}, python {p:?}");
    prop_assert_eq!(py["ok"][1].as_bool().unwrap(), lossless, "{}: python lossless", case);
    let sol = harness(H::fromFixedDecimalLossyCall { value, decimals }).unwrap();
    prop_assert_eq!(
        (big(sol._0), big(sol._1), sol._2),
        (want.c.clone(), BigInt::from(want.e), lossless),
        "{}",
        case
    );
    let want = r::from_fixed_decimal_lossless_unpacked(value, decimals);
    let sol = harness(H::fromFixedDecimalLosslessCall { value, decimals });
    match (sol, want) {
        (Ok(s), Ok(w)) => prop_assert_eq!(
            (big(s._0), big(s._1)),
            (w.c, BigInt::from(w.e)),
            "{} lossless",
            case
        ),
        (Err(s), Err(w)) => prop_assert!(error_matches(&s, w), "{case} lossless: solidity {s:?}, reference {w:?}"),
        (s, w) => prop_assert!(false, "{case} lossless: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

fn check_to_fixed_unpacked(c: &BigInt, e: &BigInt, decimals: u8) -> Result<(), TestCaseError> {
    let case = format!("toFixedDecimalLossy({c}, {e}, {decimals})");
    let want = r::to_fixed_decimal_lossy_unpacked(c, e, decimals);
    if in_python_range(e) {
        let py = ask(json!({"op": "to_fixed_lossy", "a": py_pair(c, e), "decimals": decimals}));
        match (&want, &py["ok"], py["err"].as_str()) {
            (Ok((v, l)), Value::Array(p), _) => {
                prop_assert_eq!(p[0].as_str().unwrap(), v.to_string(), "{}: python", case);
                prop_assert_eq!(p[1].as_bool().unwrap(), *l, "{}: python lossless", case);
            }
            (Err(w), _, Some(p)) => prop_assert_eq!(w.name(), p, "{}: python", case),
            _ => prop_assert!(false, "{case}: reference {want:?}, python {py}"),
        }
    }
    let sol = harness(H::toFixedDecimalLossyCall {
        signedCoefficient: i256(c),
        exponent: i256(e),
        decimals,
    });
    match (sol.map(|s| (s._0, s._1)), want) {
        (Ok(s), Ok(w)) => prop_assert_eq!(s, w, "{}", case),
        (Err(s), Err(w)) => prop_assert!(error_matches(&s, w), "{case}: solidity {s:?}, reference {w:?}"),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, reference {w:?}"),
    }
    let want = r::to_fixed_decimal_lossless_unpacked(c, e, decimals);
    let sol = harness(H::toFixedDecimalLosslessCall {
        signedCoefficient: i256(c),
        exponent: i256(e),
        decimals,
    });
    match (sol, want) {
        (Ok(s), Ok(w)) => prop_assert_eq!(s, w, "{} lossless", case),
        (Err(s), Err(w)) => prop_assert!(error_matches(&s, w), "{case} lossless: solidity {s:?}, reference {w:?}"),
        (s, w) => prop_assert!(false, "{case} lossless: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

/// `toDecimalString` by its own name: the documented string, which the
/// concrete's `format` must return too.
fn check_to_decimal_string(a: &Dec) -> Result<(), TestCaseError> {
    for (scientific, want) in [(true, r::format_scientific(a)), (false, r::format_plain(a))] {
        let case = format!("toDecimalString({}, {scientific})", show(a));
        let sol = harness(H::toDecimalStringCall { float: a.to_bytes(), scientific });
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
    let case = format!("parseDecimalFloatInline({s:?})");
    let want = r::parse_inline(lit);
    if let Ok((c, e)) = &want
        && in_python_range(e)
    {
        let p = py_float(&ask(json!({"op": "literal", "s": lit}))).unwrap();
        prop_assert!(
            p.eq_value(&Dec::new(c.clone(), r::pin(e))),
            "{case}: reference {c}e{e}, python {p:?}"
        );
    }
    let sol = harness(H::parseDecimalFloatInlineCall { str: s.clone() }).unwrap();
    match want {
        Ok((c, e)) => {
            prop_assert_eq!(sol._0.0, [0u8; 4], "{}: error", case);
            prop_assert_eq!(sol._1, U256::from(lit.len()), "{}: cursor", case);
            prop_assert_eq!((big(sol._2), big(sol._3)), (c, e), "{}", case);
        }
        Err(w) => prop_assert!(
            error_matches(&Fail::Selector(sol._0.0), w),
            "{case}: solidity {:?}, reference {w:?}",
            sol._0
        ),
    }

    let case = format!("parseDecimalFloat({s:?})");
    let want = match r::parse_inline(lit) {
        Err(w) => Err(w),
        Ok(_) if !suffix.is_empty() => Err(RefError::ParseDecimalFloatExcessCharacters),
        Ok(_) => r::parse(lit),
    };
    let sol = harness(H::parseDecimalFloatCall { str: s.clone() }).unwrap();
    let concrete = evm::concrete(T::parseCall { str: s }).unwrap();
    prop_assert_eq!((sol._0, sol._1), (concrete._0, concrete._1), "{}: harness and concrete", case);
    match want {
        Ok(w) => {
            prop_assert_eq!(sol._0.0, [0u8; 4], "{}: error", case);
            prop_assert_eq!(sol._1, w.to_bytes(), "{}: reference {:?}", case, w);
        }
        Err(w) => {
            prop_assert!(
                error_matches(&Fail::Selector(sol._0.0), w),
                "{case}: solidity {:?}, reference {w:?}",
                sol._0
            );
            prop_assert!(sol._1.is_zero(), "{}: an error returns zero", case);
        }
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
        for c in [r::int224_max(), r::int224_min(), pow10(67), pow10(67) * 2 + 1] {
            let e = &floor - shortfall;
            run(check_pack_lossy(&c, &e));
            run(check_pack_lossless(&c, &e));
            run(check_pack_arithmetic(&c, &e));
        }
    }
    for excess in 0i64..=70 {
        for c in [BigInt::from(1), BigInt::from(-1), BigInt::from(26), pow10(66), r::int224_max() / 10] {
            let e = BigInt::from(I32_MAX + excess);
            run(check_pack_lossy(&c, &e));
            run(check_pack_lossless(&c, &e));
        }
    }
    for k in 70u64..=76 {
        for d in [0i64, 1, 12345, -1] {
            let c = pow10(k) + d;
            if r::fits_int256(&c) {
                for e in [BigInt::from(0), BigInt::from(I32_MAX - 3), BigInt::from(I32_MIN)] {
                    run(check_pack_lossy(&c, &e));
                    run(check_pack_lossy(&-c.clone(), &e));
                }
            }
        }
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
    let want = r::agree(&Dec::zero(), &Dec::new(1, 0), &Dec::new(-1, -100), &Dec::new(1, 0));
    assert_eq!(want, Ok(true));
    run(check_agree(&Dec::zero(), &Dec::new(1, 0), &Dec::new(-1, -100), &Dec::new(1, 0)));
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
            run(check_to_fixed_unpacked(&BigInt::from(1), &(r::int256_max() - d), decimals));
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
