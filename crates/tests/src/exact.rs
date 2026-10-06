//! Every non-transcendental operation, over the full Float domain, against
//! the exact reference (`reference.rs`) and the Python `decimal` oracle.
//! All three must agree exactly: the same value, or the same single error.
//! pow, pow10, log10 and sqrt are not here; #297 changes their contract.

use crate::oracle::{self, ask};
use crate::reference::{self as r, Dec, I32_MAX, I32_MIN, RefError, pow10};
use alloy::primitives::U256;
use alloy::sol_types::SolInterface;
use core::cmp::Ordering;
use num_bigint::BigInt;
use num_traits::Zero;
use proptest::prelude::*;
use proptest::test_runner::TestCaseError;
use rain_math_float::{Float, FloatError};
use serde_json::{Value, json};

/// Local runs set `PROPTEST_CASES` low; CI runs the default.
fn config() -> ProptestConfig {
    let cases = std::env::var("PROPTEST_CASES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(2000);
    ProptestConfig::with_cases(cases)
}

// ---------------------------------------------------------------- strategies

/// Every int224, weighted towards its ends, zero and one, powers of ten and
/// digit-count boundaries.
fn coefficient() -> BoxedStrategy<BigInt> {
    let sign = any::<bool>();
    prop_oneof![
        3 => any::<[u8; 28]>().prop_map(|b| BigInt::from_signed_bytes_be(&b)),
        // A uniformly random digit count, then uniform digits.
        3 => (1u64..=68, any::<[u8; 32]>(), sign).prop_map(|(n, b, neg)| {
            let lo = pow10(n - 1);
            let span = pow10(n) - &lo;
            let c = lo + BigInt::from_bytes_be(num_bigint::Sign::Plus, &b) % span;
            if neg { -c } else { c }
        }),
        2 => prop_oneof![
            Just(r::int224_min()),
            Just(r::int224_max()),
            Just(r::int224_min() + 1),
            Just(r::int224_max() - 1),
            Just(r::int224_max() / 10),
            Just(-r::int224_max() / 10),
            Just(BigInt::zero()),
            Just(BigInt::from(1)),
            Just(BigInt::from(-1)),
        ],
        // Near a power of ten.
        2 => (0u64..=67, -3i64..=3, sign).prop_map(|(k, d, neg)| {
            let c = pow10(k) + d;
            if neg { -c } else { c }
        }),
        // 9...9, the last value of each digit count.
        1 => (1u64..=67, sign).prop_map(|(k, neg)| {
            let c = pow10(k) - 1u32;
            if neg { -c } else { c }
        }),
    ]
    .prop_filter("int224", r::fits_int224)
    .boxed()
}

/// Every int32, weighted towards both ends and the middle.
fn exponent() -> BoxedStrategy<i64> {
    prop_oneof![
        2 => any::<i32>().prop_map(i64::from),
        2 => I32_MIN..=I32_MIN + 160,
        2 => I32_MAX - 160..=I32_MAX,
        3 => -160i64..=160,
    ]
    .boxed()
}

fn float() -> BoxedStrategy<Dec> {
    prop_oneof![
        6 => (coefficient(), exponent()).prop_map(|(c, e)| Dec::new(c, e)),
        // Near one: 10^k ± d at exponent -k.
        1 => (0u64..=66, -3i64..=3).prop_map(|(k, d)| Dec::new(pow10(k) + d, -(k as i64))),
    ]
    .boxed()
}

fn clamp_exponent(e: i64) -> i64 {
    e.clamp(I32_MIN, I32_MAX)
}

/// A second operand related to the first: the same value in another
/// representation, a neighbour, its negation, or one at an exponent offset
/// around the 76-digit alignment window.
fn related(a: Dec, c: BigInt, offset: i64, kind: u8) -> Dec {
    match kind {
        0 => {
            // Same value, other representation, where one exists.
            let k = offset.unsigned_abs() % 70;
            let up = &a.c * pow10(k);
            if r::fits_int224(&up) && a.e - (k as i64) >= I32_MIN {
                Dec::new(up, a.e - k as i64)
            } else {
                a
            }
        }
        1 => Dec::new(
            (&a.c + offset.signum()).clamp(r::int224_min(), r::int224_max()),
            a.e,
        ),
        2 => a.neg_clamped(),
        3 => Dec::new(a.c.clone(), clamp_exponent(a.e + offset)),
        _ => Dec::new(c, clamp_exponent(a.e + offset)),
    }
}

impl Dec {
    fn neg_clamped(&self) -> Dec {
        let n = self.neg();
        if r::fits_int224(&n.c) {
            n
        } else {
            self.clone()
        }
    }
}

fn pair() -> BoxedStrategy<(Dec, Dec)> {
    prop_oneof![
        1 => (float(), float()),
        1 => (float(), coefficient(), -90i64..=90, 0u8..6)
            .prop_map(|(a, c, off, kind)| {
                let b = related(a.clone(), c, off, kind);
                (a, b)
            }),
    ]
    .boxed()
}

// ------------------------------------------------------------------ checking

/// A Solidity error, as a selector or as the binding's name for it.
fn sol_error(e: &FloatError) -> Option<([u8; 4], String)> {
    match e {
        FloatError::DecimalFloat(x) => Some((x.selector(), String::new())),
        FloatError::DecimalFloatSelector(Ok(s)) => Some(([0; 4], format!("{s:?}"))),
        FloatError::DecimalFloatSelector(Err(b)) => Some((b.0, String::new())),
        _ => None,
    }
}

fn error_matches(e: &FloatError, want: RefError) -> bool {
    match sol_error(e) {
        Some((selector, name)) => selector == want.selector() || name == want.name(),
        None => false,
    }
}

/// The Python oracle's answer to a float-valued case.
fn py_float(v: &Value) -> Result<Dec, String> {
    match (&v["ok"], &v["err"]) {
        (Value::Array(_), _) => Ok(oracle::to_dec(&v["ok"])),
        (_, Value::String(e)) => Err(e.clone()),
        _ => panic!("oracle response {v}"),
    }
}

fn check_float(
    case: &str,
    sol: Result<Float, FloatError>,
    want: Result<Dec, RefError>,
    py: Value,
) -> Result<(), TestCaseError> {
    match (&want, py_float(&py)) {
        (Ok(w), Ok(p)) => prop_assert!(w.eq_value(&p), "{case}: reference {w:?}, python {p:?}"),
        (Err(w), Err(p)) => prop_assert_eq!(w.name(), p, "{}", case),
        (w, p) => prop_assert!(false, "{case}: reference {w:?}, python {p:?}"),
    }
    match (sol, want) {
        (Ok(s), Ok(w)) => {
            let s = Dec::from_float(s);
            prop_assert!(s.eq_value(&w), "{case}: solidity {s:?}, reference {w:?}");
        }
        (Err(s), Err(w)) => prop_assert!(
            error_matches(&s, w),
            "{case}: solidity {s:?}, reference {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

fn ask2(op: &str, a: &Dec, b: &Dec) -> Value {
    ask(json!({"op": op, "a": oracle::float(a), "b": oracle::float(b)}))
}

fn ask1(op: &str, a: &Dec) -> Value {
    ask(json!({"op": op, "a": oracle::float(a)}))
}

fn show(a: &Dec) -> String {
    format!("{}e{}", a.c, a.e)
}

fn check_add(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("add({}, {})", show(a), show(b));
    let want = r::add(a, b);
    // The documented alignment loses nothing an exact Float could hold.
    if let Some(exact) = a.add_exact(b).filter(Dec::representable) {
        prop_assert!(
            matches!(&want, Ok(w) if w.eq_value(&exact)),
            "{case}: representable sum {exact:?}, reference {want:?}"
        );
    }
    check_float(&case, a.to_float() + b.to_float(), want, ask2("add", a, b))
}

fn check_sub(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("sub({}, {})", show(a), show(b));
    let want = r::sub(a, b);
    if let Some(exact) = a.add_exact(&b.neg()).filter(Dec::representable) {
        prop_assert!(
            matches!(&want, Ok(w) if w.eq_value(&exact)),
            "{case}: representable difference {exact:?}, reference {want:?}"
        );
    }
    check_float(&case, a.to_float() - b.to_float(), want, ask2("sub", a, b))
}

fn check_mul(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("mul({}, {})", show(a), show(b));
    check_float(
        &case,
        a.to_float() * b.to_float(),
        r::mul(a, b),
        ask2("mul", a, b),
    )
}

fn check_div(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("div({}, {})", show(a), show(b));
    check_float(
        &case,
        a.to_float() / b.to_float(),
        r::div(a, b),
        ask2("div", a, b),
    )
}

fn check_compare(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("compare({}, {})", show(a), show(b));
    let want = a.cmp_value(b);
    let py = ask2("cmp", a, b)["ok"].as_i64().unwrap();
    prop_assert_eq!(py, want as i64, "{}: python", case);
    let (fa, fb) = (a.to_float(), b.to_float());
    prop_assert_eq!(fa.lt(fb).unwrap(), want == Ordering::Less, "{}: lt", case);
    prop_assert_eq!(
        fa.gt(fb).unwrap(),
        want == Ordering::Greater,
        "{}: gt",
        case
    );
    prop_assert_eq!(fa.eq(fb).unwrap(), want == Ordering::Equal, "{}: eq", case);
    prop_assert_eq!(
        fa.lte(fb).unwrap(),
        want != Ordering::Greater,
        "{}: lte",
        case
    );
    prop_assert_eq!(fa.gte(fb).unwrap(), want != Ordering::Less, "{}: gte", case);
    // min and max return an operand as is: `a < b ? a : b`, `a > b ? a : b`.
    let min = if want == Ordering::Less { fa } else { fb };
    let max = if want == Ordering::Greater { fa } else { fb };
    prop_assert_eq!(
        fa.min(fb).unwrap().get_inner(),
        min.get_inner(),
        "{}: min",
        case
    );
    prop_assert_eq!(
        fa.max(fb).unwrap().get_inner(),
        max.get_inner(),
        "{}: max",
        case
    );
    Ok(())
}

fn check_unary(a: &Dec) -> Result<(), TestCaseError> {
    let f = a.to_float();
    let s = show(a);
    check_float(&format!("minus({s})"), -f, r::minus(a), ask1("minus", a))?;
    check_float(&format!("abs({s})"), f.abs(), r::abs(a), ask1("abs", a))?;
    check_float(&format!("inv({s})"), f.inv(), r::inv(a), ask1("inv", a))?;
    check_float(
        &format!("integer({s})"),
        f.integer(),
        r::integer(a),
        ask1("integer", a),
    )?;
    check_float(&format!("frac({s})"), f.frac(), r::frac(a), ask1("frac", a))?;
    check_float(
        &format!("floor({s})"),
        f.floor(),
        r::floor(a),
        ask1("floor", a),
    )?;
    prop_assert_eq!(f.is_zero().unwrap(), a.is_zero(), "isZero({})", s);
    Ok(())
}

fn check_pack(a: &Dec) -> Result<(), TestCaseError> {
    let s = show(a);
    let c = alloy::primitives::aliases::I224::from_dec_str(&a.c.to_string()).unwrap();
    let packed = Float::pack_lossless(c, a.e as i32).unwrap();
    // packLossless keeps the fields, except that zero packs as FLOAT_ZERO.
    let want = if a.is_zero() { Dec::zero() } else { a.clone() };
    prop_assert_eq!(
        packed.get_inner(),
        want.to_float().get_inner(),
        "pack({})",
        s
    );
    let (uc, ue) = packed.unpack().unwrap();
    prop_assert_eq!(
        uc.to_string(),
        want.c.to_string(),
        "unpack({}) coefficient",
        s
    );
    prop_assert_eq!(ue.to_string(), want.e.to_string(), "unpack({}) exponent", s);
    Ok(())
}

fn u256() -> BoxedStrategy<U256> {
    let int256_max = U256::MAX >> 1usize;
    prop_oneof![
        2 => any::<[u8; 32]>().prop_map(U256::from_be_bytes),
        2 => (0u32..=256).prop_flat_map(|bits| any::<[u8; 32]>()
            .prop_map(move |b| if bits == 0 { U256::ZERO } else { U256::from_be_bytes(b) >> (256 - bits) })),
        1 => (0usize..=77, -3i64..=3).prop_map(|(k, d)| {
            let p = U256::from(10).pow(U256::from(k));
            if d < 0 { p.saturating_sub(U256::from(-d)) } else { p.saturating_add(U256::from(d)) }
        }),
        1 => (-20i64..=20).prop_map(move |d| if d < 0 {
            int256_max - U256::from(-d)
        } else {
            int256_max.saturating_add(U256::from(d))
        }),
        1 => (0u64..=20).prop_map(|d| U256::MAX - U256::from(d)),
        // Multiples of ten above int256.max shed their zero losslessly.
        1 => any::<[u8; 32]>().prop_map(move |b| {
            let x = U256::from_be_bytes(b) | (U256::from(1) << 255);
            x - x % U256::from(10)
        }),
    ]
    .boxed()
}

fn check_from_fixed(value: U256, decimals: u8) -> Result<(), TestCaseError> {
    let case = format!("fromFixedDecimal({value}, {decimals})");
    let (want, want_lossless) = r::from_fixed_decimal_lossy(value, decimals);
    let py =
        ask(json!({"op": "from_fixed_lossy", "value": value.to_string(), "decimals": decimals}));
    let p = oracle::to_dec(&py["ok"][0]);
    prop_assert!(
        p.eq_value(&want),
        "{case}: python {p:?}, reference {want:?}"
    );
    prop_assert_eq!(
        py["ok"][1].as_bool().unwrap(),
        want_lossless,
        "{}: python lossless",
        case
    );
    let (sol, sol_lossless) = Float::from_fixed_decimal_lossy(value, decimals).unwrap();
    let s = Dec::from_float(sol);
    prop_assert!(
        s.eq_value(&want),
        "{case}: solidity {s:?}, reference {want:?}"
    );
    prop_assert_eq!(sol_lossless, want_lossless, "{}: lossless", case);

    let py =
        ask(json!({"op": "from_fixed_lossless", "value": value.to_string(), "decimals": decimals}));
    check_float(
        &format!("{case} lossless"),
        Float::from_fixed_decimal(value, decimals),
        r::from_fixed_decimal_lossless(value, decimals),
        py,
    )
}

fn check_to_fixed(a: &Dec, decimals: u8) -> Result<(), TestCaseError> {
    let case = format!("toFixedDecimal({}, {decimals})", show(a));
    let f = a.to_float();
    let want = r::to_fixed_decimal_lossy(a, decimals);
    let py = ask(json!({"op": "to_fixed_lossy", "a": oracle::float(a), "decimals": decimals}));
    match (&want, &py["ok"], &py["err"]) {
        (Ok((v, l)), Value::Array(p), _) => {
            prop_assert_eq!(p[0].as_str().unwrap(), v.to_string(), "{}: python", case);
            prop_assert_eq!(p[1].as_bool().unwrap(), *l, "{}: python lossless", case);
        }
        (Err(w), _, Value::String(p)) => prop_assert_eq!(w.name(), p.as_str(), "{}: python", case),
        _ => prop_assert!(false, "{case}: reference {want:?}, python {py}"),
    }
    match (f.to_fixed_decimal_lossy(decimals), want) {
        (Ok(s), Ok(w)) => prop_assert_eq!(s, w, "{}", case),
        (Err(s), Err(w)) => prop_assert!(
            error_matches(&s, w),
            "{case}: solidity {s:?}, reference {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, reference {w:?}"),
    }
    let want = r::to_fixed_decimal_lossless(a, decimals);
    let py = ask(json!({"op": "to_fixed_lossless", "a": oracle::float(a), "decimals": decimals}));
    match (&want, &py["ok"], &py["err"]) {
        (Ok(v), Value::String(p), _) => {
            prop_assert_eq!(p.as_str(), v.to_string(), "{} lossless: python", case)
        }
        (Err(w), _, Value::String(p)) => {
            prop_assert_eq!(w.name(), p.as_str(), "{} lossless: python", case)
        }
        _ => prop_assert!(false, "{case} lossless: reference {want:?}, python {py}"),
    }
    match (f.to_fixed_decimal(decimals), want) {
        (Ok(s), Ok(w)) => prop_assert_eq!(s, w, "{} lossless", case),
        (Err(s), Err(w)) => prop_assert!(
            error_matches(&s, w),
            "{case} lossless: solidity {s:?}, reference {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case} lossless: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

/// A formatted string must be the documented string, denote the float's
/// value exactly (python reads it independently) and parse back to it.
fn check_format_one(
    case: &str,
    a: &Dec,
    sol: Result<String, FloatError>,
    want: Result<String, RefError>,
) -> Result<(), TestCaseError> {
    match (sol, want) {
        (Ok(s), Ok(w)) => {
            prop_assert_eq!(&s, &w, "{}", case);
            let p = oracle::to_dec(&ask(json!({"op": "literal", "s": s}))["ok"]);
            prop_assert!(p.eq_value(a), "{case}: {s} is {p:?} to python");
            let back = Float::parse(s.clone());
            prop_assert!(
                matches!(&back, Ok(b) if Dec::from_float(*b).eq_value(a)),
                "{case}: parse({s}) = {back:?}"
            );
        }
        (Err(s), Err(w)) => prop_assert!(
            error_matches(&s, w),
            "{case}: solidity {s:?}, reference {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

fn check_format(a: &Dec) -> Result<(), TestCaseError> {
    let f = a.to_float();
    let s = show(a);
    check_format_one(
        &format!("format({s}, true)"),
        a,
        f.format_with_scientific(true),
        r::format_scientific(a),
    )?;
    check_format_one(
        &format!("format({s}, false)"),
        a,
        f.format_with_scientific(false),
        r::format_plain(a),
    )
}

fn digit_string(max: usize) -> BoxedStrategy<String> {
    prop_oneof![
        3 => proptest::collection::vec(0u8..10, 1..=max)
            .prop_map(|d| d.iter().map(|d| char::from(b'0' + d)).collect()),
        1 => (1usize..=max, 0usize..=max).prop_map(move |(n, z)| format!("{}{}", "0".repeat(z.min(max)), "9".repeat(n))),
        1 => (0usize..=max).prop_map(|z| format!("1{}", "0".repeat(z))),
    ]
    .boxed()
}

/// Well formed literals: digit counts past every limit the parser has, and
/// exponents near int32 and int256 bounds.
fn literal() -> BoxedStrategy<String> {
    let exponent_digits = prop_oneof![
        2 => digit_string(80),
        2 => (-200i64..=200).prop_map(|d| (I32_MAX + d).unsigned_abs().to_string()),
        1 => (0u64..=80).prop_map(|d| d.to_string()),
        1 => (-3i64..=3).prop_map(|d| (BigInt::from(1) << 255usize).checked_add(&BigInt::from(d)).unwrap().to_string()),
    ];
    (
        prop_oneof![Just(""), Just("-")],
        digit_string(80),
        proptest::option::of(digit_string(80)),
        proptest::option::of((
            prop_oneof![Just("e"), Just("E")],
            prop_oneof![Just(""), Just("+"), Just("-")],
            exponent_digits,
        )),
    )
        .prop_map(|(sign, int, frac, exp)| {
            let mut s = format!("{sign}{int}");
            if let Some(frac) = frac {
                s.push('.');
                s.push_str(&frac);
            }
            if let Some((e, es, digits)) = exp {
                s.push_str(e);
                s.push_str(es);
                s.push_str(&digits);
            }
            s
        })
        .boxed()
}

fn check_parse(s: &str) -> Result<(), TestCaseError> {
    let case = format!("parse({s})");
    let want = r::parse(s);
    // The digit limits before packing are the parser's own; past them python
    // decides the literal's value and whether it packs, reading the string
    // itself wherever its exponent is in the decimal module's range.
    if let Ok(unpacked) = r::parse_unpacked(s) {
        let lit = r::literal_value(s);
        prop_assert!(
            unpacked.eq_value(&lit) || unpacked.e.abs() > 1 << 60,
            "{case}: unpacked {unpacked:?}, literal {lit:?}"
        );
        if unpacked.e.abs() < 1_000_000_000_000_000 {
            match (&want, py_float(&ask(json!({"op": "parse_value", "s": s})))) {
                (Ok(w), Ok(p)) => {
                    prop_assert!(w.eq_value(&p), "{case}: reference {w:?}, python {p:?}")
                }
                (Err(w), Err(p)) => prop_assert_eq!(w.name(), p, "{}", case),
                (w, p) => prop_assert!(false, "{case}: reference {w:?}, python {p:?}"),
            }
        }
    }
    match (Float::parse(s.to_string()), want) {
        (Ok(f), Ok(w)) => {
            let f = Dec::from_float(f);
            prop_assert!(f.eq_value(&w), "{case}: solidity {f:?}, reference {w:?}");
        }
        (Err(e), Err(w)) => prop_assert!(
            error_matches(&e, w),
            "{case}: solidity {e:?}, reference {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, reference {w:?}"),
    }
    Ok(())
}

proptest! {
    #![proptest_config(config())]

    #[test]
    fn exact_add((a, b) in pair()) { check_add(&a, &b)?; }

    #[test]
    fn exact_sub((a, b) in pair()) { check_sub(&a, &b)?; }

    #[test]
    fn exact_mul((a, b) in pair()) { check_mul(&a, &b)?; }

    #[test]
    fn exact_div((a, b) in pair()) { check_div(&a, &b)?; }

    #[test]
    fn exact_compare_min_max((a, b) in pair()) { check_compare(&a, &b)?; }

    #[test]
    fn exact_unary(a in float()) { check_unary(&a)?; }

    #[test]
    fn exact_pack_unpack(a in float()) { check_pack(&a)?; }

    #[test]
    fn exact_from_fixed_decimal(value in u256(), decimals in any::<u8>()) {
        check_from_fixed(value, decimals)?;
    }

    #[test]
    fn exact_to_fixed_decimal(a in float(), decimals in prop_oneof![any::<u8>(), 0u8..=80]) {
        check_to_fixed(&a, decimals)?;
    }

    #[test]
    fn exact_format(a in float()) { check_format(&a)?; }

    #[test]
    fn exact_parse(s in literal()) { check_parse(&s)?; }
}

/// Minimal repros of the fuzz findings, run every time rather than when the
/// fuzzer reaches them.
mod found {
    use super::*;

    fn run(r: Result<(), TestCaseError>) {
        if let Err(e) = r {
            panic!("{e}");
        }
    }

    /// The product is `1e2147483648`, exactly `10e2147483647`.
    #[test]
    fn mul_at_the_exponent_ceiling() {
        run(check_mul(&Dec::new(1, I32_MAX), &Dec::new(1, 1)));
    }

    #[test]
    fn parse_at_the_exponent_ceiling() {
        run(check_parse("1e2147483648"));
    }

    /// Fitting `1e68` into int224 sheds a zero, which takes the exponent
    /// past int256.max.
    #[test]
    fn parse_sheds_past_the_int256_exponent() {
        let int256_max = (BigInt::from(1) << 255usize) - 1u32;
        run(check_parse(&format!("1{}e{int256_max}", "0".repeat(68))));
    }
}
