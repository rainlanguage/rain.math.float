//! Every non-transcendental operation, over the full Float domain, against
//! the exact reference (`reference.rs`) and the Python `decimal` oracle.
//! All three must agree exactly: the same value, or the same single error.
//! pow, pow10, log10 and sqrt are not here; #297 changes their contract.

use crate::evm::{self, TestDecimalFloat as T, TestDecimalFloatHarness as H};
use crate::oracle::{self, ask};
use crate::reference::{self as r, Dec, I32_MAX, I32_MIN, RefError, pow10};
use alloy::primitives::{B256, Bytes, U256};
use alloy::sol_types::SolInterface;
use core::cmp::Ordering;
use num_bigint::BigInt;
use num_traits::Zero;
use proptest::prelude::*;
use proptest::test_runner::TestCaseError;
use serde_json::{Value, json};

/// Local runs set `PROPTEST_CASES` low; CI runs the default.
pub(crate) fn config() -> ProptestConfig {
    let cases = std::env::var("PROPTEST_CASES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(2000);
    ProptestConfig::with_cases(cases)
}

// ---------------------------------------------------------------- strategies

/// Every int224, weighted towards its ends, zero and one, powers of ten and
/// digit-count boundaries.
pub(crate) fn coefficient() -> BoxedStrategy<BigInt> {
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
pub(crate) fn exponent() -> BoxedStrategy<i64> {
    prop_oneof![
        2 => any::<i32>().prop_map(i64::from),
        2 => I32_MIN..=I32_MIN + 160,
        2 => I32_MAX - 160..=I32_MAX,
        3 => -160i64..=160,
    ]
    .boxed()
}

pub(crate) fn float() -> BoxedStrategy<Dec> {
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

pub(crate) fn pair() -> BoxedStrategy<(Dec, Dec)> {
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

/// How a call failed: a revert of the concrete or of the harness, or the
/// error selector `parse` returns.
#[derive(Debug)]
pub(crate) enum Fail {
    Revert(Bytes),
    Harness(Bytes),
    Selector([u8; 4]),
}

/// A revert must decode as one of the errors of the contract that reverted.
pub(crate) fn error_matches(e: &Fail, want: RefError) -> bool {
    match e {
        Fail::Revert(out) => T::TestDecimalFloatErrors::abi_decode(out)
            .is_ok_and(|x| x.selector() == want.selector()),
        Fail::Harness(out) => H::TestDecimalFloatHarnessErrors::abi_decode(out)
            .is_ok_and(|x| x.selector() == want.selector()),
        Fail::Selector(s) => *s == want.selector(),
    }
}

pub(crate) type Sol<V> = Result<V, Fail>;

fn sol<V>(r: Result<V, Bytes>) -> Sol<V> {
    r.map_err(Fail::Revert)
}

pub(crate) fn sol_float<C: alloy::sol_types::SolCall<Return = B256>>(c: C) -> Sol<Dec> {
    sol(evm::float(c))
}

fn sol_bool<C: alloy::sol_types::SolCall<Return = bool>>(c: C) -> bool {
    evm::concrete(c).unwrap()
}

pub(crate) fn sol_parse(s: &str) -> Sol<Dec> {
    let r = sol(evm::concrete(T::parseCall { str: s.to_string() }))?;
    if r._0 != [0u8; 4] {
        return Err(Fail::Selector(r._0.0));
    }
    Ok(Dec::from_bytes(r._1))
}

pub(crate) fn sol_format(a: &Dec, scientific: bool) -> Sol<String> {
    sol(evm::concrete(T::formatCall {
        a: a.to_bytes(),
        scientific,
    }))
}

/// The Python oracle's answer to a float-valued case.
pub(crate) fn py_float(v: &Value) -> Result<Dec, String> {
    match (&v["ok"], &v["err"]) {
        (Value::Array(_), _) => Ok(oracle::to_dec(&v["ok"])),
        (_, Value::String(e)) => Err(e.clone()),
        _ => panic!("oracle response {v}"),
    }
}

pub(crate) fn check_float(
    case: &str,
    sol: Sol<Dec>,
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

pub(crate) fn show(a: &Dec) -> String {
    format!("{}e{}", a.c, a.e)
}

fn sol_add(a: &Dec, b: &Dec) -> Sol<Dec> {
    sol_float(T::addCall {
        a: a.to_bytes(),
        b: b.to_bytes(),
    })
}

fn sol_sub(a: &Dec, b: &Dec) -> Sol<Dec> {
    sol_float(T::subCall {
        a: a.to_bytes(),
        b: b.to_bytes(),
    })
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
    check_float(&case, sol_add(a, b), want, ask2("add", a, b))
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
    check_float(&case, sol_sub(a, b), want, ask2("sub", a, b))
}

fn check_mul(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("mul({}, {})", show(a), show(b));
    let sol = sol_float(T::mulCall {
        a: a.to_bytes(),
        b: b.to_bytes(),
    });
    check_float(&case, sol, r::mul(a, b), ask2("mul", a, b))
}

fn check_div(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("div({}, {})", show(a), show(b));
    let sol = sol_float(T::divCall {
        a: a.to_bytes(),
        b: b.to_bytes(),
    });
    check_float(&case, sol, r::div(a, b), ask2("div", a, b))
}

fn check_compare(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("compare({}, {})", show(a), show(b));
    let want = a.cmp_value(b);
    let py = ask2("cmp", a, b)["ok"].as_i64().unwrap();
    prop_assert_eq!(py, want as i64, "{}: python", case);
    let (fa, fb) = (a.to_bytes(), b.to_bytes());
    prop_assert_eq!(
        sol_bool(T::ltCall { a: fa, b: fb }),
        want == Ordering::Less,
        "{}: lt",
        case
    );
    prop_assert_eq!(
        sol_bool(T::gtCall { a: fa, b: fb }),
        want == Ordering::Greater,
        "{}: gt",
        case
    );
    prop_assert_eq!(
        sol_bool(T::eqCall { a: fa, b: fb }),
        want == Ordering::Equal,
        "{}: eq",
        case
    );
    prop_assert_eq!(
        sol_bool(T::lteCall { a: fa, b: fb }),
        want != Ordering::Greater,
        "{}: lte",
        case
    );
    prop_assert_eq!(
        sol_bool(T::gteCall { a: fa, b: fb }),
        want != Ordering::Less,
        "{}: gte",
        case
    );
    // min and max return an operand as is: `a < b ? a : b`, `a > b ? a : b`.
    let min = if want == Ordering::Less { fa } else { fb };
    let max = if want == Ordering::Greater { fa } else { fb };
    prop_assert_eq!(
        evm::concrete(T::minCall { a: fa, b: fb }).unwrap(),
        min,
        "{}: min",
        case
    );
    prop_assert_eq!(
        evm::concrete(T::maxCall { a: fa, b: fb }).unwrap(),
        max,
        "{}: max",
        case
    );
    Ok(())
}

fn check_unary(a: &Dec) -> Result<(), TestCaseError> {
    let f = a.to_bytes();
    let s = show(a);
    check_float(
        &format!("minus({s})"),
        sol_float(T::minusCall { a: f }),
        r::minus(a),
        ask1("minus", a),
    )?;
    check_float(
        &format!("abs({s})"),
        sol_float(T::absCall { a: f }),
        r::abs(a),
        ask1("abs", a),
    )?;
    check_float(
        &format!("inv({s})"),
        sol_float(T::invCall { a: f }),
        r::inv(a),
        ask1("inv", a),
    )?;
    check_float(
        &format!("integer({s})"),
        sol_float(T::integerCall { a: f }),
        r::integer(a),
        ask1("integer", a),
    )?;
    check_float(
        &format!("frac({s})"),
        sol_float(T::fracCall { a: f }),
        r::frac(a),
        ask1("frac", a),
    )?;
    check_float(
        &format!("floor({s})"),
        sol_float(T::floorCall { a: f }),
        r::floor(a),
        ask1("floor", a),
    )?;
    check_float(
        &format!("ceil({s})"),
        sol_float(T::ceilCall { a: f }),
        r::ceil(a),
        ask1("ceil", a),
    )?;
    prop_assert_eq!(
        sol_bool(T::isZeroCall { a: f }),
        a.is_zero(),
        "isZero({})",
        s
    );
    Ok(())
}

/// The four getters, in the order `check_extremes_with` takes them.
fn sol_extremes() -> [Result<B256, Bytes>; 4] {
    [
        evm::concrete(T::maxPositiveValueCall {}),
        evm::concrete(T::minPositiveValueCall {}),
        evm::concrete(T::maxNegativeValueCall {}),
        evm::concrete(T::minNegativeValueCall {}),
    ]
}

fn check_extremes(a: &Dec) -> Result<(), TestCaseError> {
    let py = ask(json!({"op": "extremes"}))["ok"].clone();
    check_extremes_with(a, sol_extremes(), py)
}

/// The getters return the documented extremes exactly, and no Float lies
/// past them.
fn check_extremes_with(
    a: &Dec,
    sol: [Result<B256, Bytes>; 4],
    py: Value,
) -> Result<(), TestCaseError> {
    let extremes = [
        ("maxPositiveValue", r::max_positive()),
        ("minPositiveValue", r::min_positive()),
        ("maxNegativeValue", r::max_negative()),
        ("minNegativeValue", r::min_negative()),
    ];
    for (i, ((name, want), sol)) in extremes.iter().zip(&sol).enumerate() {
        let p = oracle::to_dec(&py[i]);
        prop_assert!(p.eq_value(want), "{name}: python {p:?}, reference {want:?}");
        prop_assert_eq!(
            sol.as_ref().unwrap(),
            &want.to_bytes(),
            "{}: solidity, reference {:?}",
            name,
            want
        );
    }
    let s = show(a);
    prop_assert!(
        r::min_negative().cmp_value(a) != Ordering::Greater
            && a.cmp_value(&r::max_positive()) != Ordering::Greater,
        "{s} is past an extreme"
    );
    if a.c.sign() == num_bigint::Sign::Plus {
        prop_assert!(
            a.cmp_value(&r::min_positive()) != Ordering::Less,
            "{s} is below minPositiveValue"
        );
    }
    if a.is_negative() {
        prop_assert!(
            a.cmp_value(&r::max_negative()) != Ordering::Greater,
            "{s} is above maxNegativeValue"
        );
    }
    Ok(())
}

fn check_pack(a: &Dec) -> Result<(), TestCaseError> {
    let s = show(a);
    let packed = evm::harness(H::packLosslessCall {
        signedCoefficient: alloy::primitives::I256::from_dec_str(&a.c.to_string()).unwrap(),
        exponent: alloy::primitives::I256::try_from(a.e).unwrap(),
    })
    .unwrap();
    // packLossless keeps the fields, except that zero packs as FLOAT_ZERO.
    let want = if a.is_zero() { Dec::zero() } else { a.clone() };
    prop_assert_eq!(packed, want.to_bytes(), "pack({})", s);
    let unpacked = evm::harness(H::unpackCall { float: packed }).unwrap();
    prop_assert_eq!(
        unpacked._0.to_string(),
        want.c.to_string(),
        "unpack({}) coefficient",
        s
    );
    prop_assert_eq!(
        unpacked._1.to_string(),
        want.e.to_string(),
        "unpack({}) exponent",
        s
    );
    Ok(())
}

pub(crate) fn u256() -> BoxedStrategy<U256> {
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
    let lossy = evm::concrete(T::fromFixedDecimalLossyCall { value, decimals }).unwrap();
    check_from_fixed_lossy(&case, lossy, &want, want_lossless)?;

    let py =
        ask(json!({"op": "from_fixed_lossless", "value": value.to_string(), "decimals": decimals}));
    check_float(
        &format!("{case} lossless"),
        sol_float(T::fromFixedDecimalLosslessCall { value, decimals }),
        r::from_fixed_decimal_lossless(value, decimals),
        py,
    )
}

fn check_from_fixed_lossy(
    case: &str,
    lossy: T::fromFixedDecimalLossyReturn,
    want: &Dec,
    want_lossless: bool,
) -> Result<(), TestCaseError> {
    let (s, sol_lossless) = (Dec::from_bytes(lossy._0), lossy._1);
    prop_assert!(
        s.eq_value(want),
        "{case}: solidity {s:?}, reference {want:?}"
    );
    prop_assert_eq!(sol_lossless, want_lossless, "{}: lossless", case);
    Ok(())
}

fn check_to_fixed(a: &Dec, decimals: u8) -> Result<(), TestCaseError> {
    let case = format!("toFixedDecimal({}, {decimals})", show(a));
    let float = a.to_bytes();
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
    let lossy = sol(evm::concrete(T::toFixedDecimalLossyCall {
        float,
        decimals,
    }));
    match (lossy.map(|r| (r._0, r._1)), want) {
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
    let lossless = sol(evm::concrete(T::toFixedDecimalLosslessCall {
        float,
        decimals,
    }));
    match (lossless, want) {
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
pub(crate) fn check_format_one(
    case: &str,
    a: &Dec,
    sol: Sol<String>,
    want: Result<String, RefError>,
) -> Result<(), TestCaseError> {
    match (sol, want) {
        (Ok(s), Ok(w)) => {
            prop_assert_eq!(&s, &w, "{}", case);
            let p = oracle::to_dec(&ask(json!({"op": "literal", "s": s}))["ok"]);
            prop_assert!(p.eq_value(a), "{case}: {s} is {p:?} to python");
            let back = sol_parse(&s);
            prop_assert!(
                matches!(&back, Ok(b) if b.eq_value(a)),
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
    let s = show(a);
    check_format_one(
        &format!("format({s}, true)"),
        a,
        sol_format(a, true),
        r::format_scientific(a),
    )?;
    check_format_one(
        &format!("format({s}, false)"),
        a,
        sol_format(a, false),
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
pub(crate) fn literal() -> BoxedStrategy<String> {
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

/// #327: a nonzero integer part outside int224 with an all-zero
/// fraction, which Solidity rejects as ParseDecimalPrecisionLoss before it
/// reads the exponent.
pub(crate) fn zero_fraction_defect(s: &str) -> bool {
    let mantissa = s.split(['e', 'E']).next().unwrap();
    let Some((int_str, frac)) = mantissa.split_once('.') else {
        return false;
    };
    let int: BigInt = int_str.parse().unwrap();
    frac.bytes().all(|b| b == b'0')
        && !int.is_zero()
        && !r::fits_int224(&int)
        && int >= r::int256_min()
        && int <= r::int256_max()
}

pub(crate) fn check_parse(s: &str) -> Result<(), TestCaseError> {
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
    if zero_fraction_defect(s) {
        let sol = sol_parse(s);
        prop_assert!(
            sol.as_ref()
                .is_err_and(|e| error_matches(e, RefError::ParseDecimalPrecisionLoss)),
            "{case}: solidity {sol:?}"
        );
        return Ok(());
    }
    match (sol_parse(s), want) {
        (Ok(f), Ok(w)) => {
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
    fn exact_extremes(a in float()) { check_extremes(&a)?; }

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

/// Every unary operation at each exponent near zero, where `ceil`, `floor`,
/// `integer` and `frac` keep or shed a fraction, not only when the fuzzer
/// reaches them.
#[test]
fn exact_unary_near_zero_exponents() {
    for e in -3..=1 {
        for c in -25..=25 {
            if let Err(err) = check_unary(&Dec::new(c, e)) {
                panic!("{err}");
            }
        }
    }
}

/// `check_float` and `error_matches` reject wrong Solidity and Python results.
mod checker {
    use super::*;

    fn one() -> Dec {
        Dec::new(1, 0)
    }

    fn two() -> Dec {
        Dec::new(2, 0)
    }

    fn div_by_zero() -> Sol<Dec> {
        let r = sol_float(T::divCall {
            a: one().to_bytes(),
            b: Dec::zero().to_bytes(),
        });
        assert!(matches!(r, Err(Fail::Revert(_))), "{r:?}");
        r
    }

    fn overflow() -> Sol<Dec> {
        let max = Dec::new(1, I32_MAX);
        let r = sol_float(T::mulCall {
            a: max.to_bytes(),
            b: max.to_bytes(),
        });
        assert!(matches!(r, Err(Fail::Revert(_))), "{r:?}");
        r
    }

    fn py_ok(d: &Dec) -> Value {
        json!({ "ok": oracle::float(d) })
    }

    fn py_err(e: RefError) -> Value {
        json!({ "err": e.name() })
    }

    fn accepts(sol: Sol<Dec>, want: Result<Dec, RefError>, py: Value) -> bool {
        check_float("checker", sol, want, py).is_ok()
    }

    #[test]
    fn accepts_agreement() {
        assert!(accepts(Ok(one()), Ok(one()), py_ok(&one())));
        // The same value in another representation.
        assert!(accepts(Ok(Dec::new(10, -1)), Ok(one()), py_ok(&one())));
        let dz = RefError::DivisionByZero;
        assert!(accepts(div_by_zero(), Err(dz), py_err(dz)));
    }

    #[test]
    fn rejects_wrong_solidity() {
        let dz = RefError::DivisionByZero;
        assert!(!accepts(Ok(two()), Ok(one()), py_ok(&one())));
        assert!(!accepts(overflow(), Err(dz), py_err(dz)));
        assert!(!accepts(Ok(one()), Err(dz), py_err(dz)));
        assert!(!accepts(div_by_zero(), Ok(one()), py_ok(&one())));
    }

    #[test]
    fn rejects_wrong_python() {
        let dz = RefError::DivisionByZero;
        let eo = RefError::ExponentOverflow;
        assert!(!accepts(Ok(one()), Ok(one()), py_ok(&two())));
        assert!(!accepts(div_by_zero(), Err(dz), py_err(eo)));
        assert!(!accepts(Ok(one()), Ok(one()), py_err(dz)));
        assert!(!accepts(div_by_zero(), Err(dz), py_ok(&one())));
    }

    #[test]
    fn error_matches_decodes_the_revert() {
        let dz = RefError::DivisionByZero;
        let Err(revert) = div_by_zero() else {
            unreachable!()
        };
        assert!(error_matches(&revert, dz));
        assert!(!error_matches(&revert, RefError::ExponentOverflow));
        // The selector alone does not decode.
        let bare = Fail::Revert(Bytes::from(dz.selector().to_vec()));
        assert!(!error_matches(&bare, dz));
    }

    fn py_extremes() -> Value {
        json!([
            oracle::float(&r::max_positive()),
            oracle::float(&r::min_positive()),
            oracle::float(&r::max_negative()),
            oracle::float(&r::min_negative()),
        ])
    }

    fn extremes_accept(a: &Dec, sol: [Result<B256, Bytes>; 4], py: Value) -> bool {
        check_extremes_with(a, sol, py).is_ok()
    }

    #[test]
    fn extremes_accept_agreement() {
        assert!(extremes_accept(&one(), sol_extremes(), py_extremes()));
    }

    #[test]
    fn extremes_reject_wrong_solidity() {
        for i in 0..4 {
            let mut sol = sol_extremes();
            sol[i] = Ok(one().to_bytes());
            assert!(!extremes_accept(&one(), sol, py_extremes()), "{i}");
        }
    }

    #[test]
    fn extremes_reject_wrong_python() {
        for i in 0..4 {
            let mut py = py_extremes();
            py[i] = oracle::float(&one());
            assert!(!extremes_accept(&one(), sol_extremes(), py), "{i}");
        }
    }

    /// Values past each extreme, which no Float holds.
    #[test]
    fn extremes_reject_values_past_them() {
        for past in [
            Dec::new(1, I32_MAX + 68),
            Dec::new(-1, I32_MAX + 68),
            Dec::new(1, I32_MIN - 1),
            Dec::new(-1, I32_MIN - 1),
        ] {
            assert!(
                !extremes_accept(&past, sol_extremes(), py_extremes()),
                "{past:?}"
            );
        }
    }

    fn from_fixed_accepts(value: Dec, lossless: bool) -> bool {
        let lossy = T::fromFixedDecimalLossyReturn {
            _0: value.to_bytes(),
            _1: lossless,
        };
        check_from_fixed_lossy("checker", lossy, &one(), true).is_ok()
    }

    #[test]
    fn from_fixed_lossy_rejects_wrong_solidity() {
        assert!(from_fixed_accepts(one(), true));
        assert!(from_fixed_accepts(Dec::new(10, -1), true));
        assert!(!from_fixed_accepts(two(), true));
        assert!(!from_fixed_accepts(one(), false));
    }

    #[test]
    fn error_matches_parse_selectors() {
        let loss = RefError::ParseDecimalPrecisionLoss;
        assert!(error_matches(&Fail::Selector(loss.selector()), loss));
        assert!(!error_matches(
            &Fail::Selector(loss.selector()),
            RefError::ParseDecimalOverflow
        ));
        assert!(matches!(sol_parse("abc"), Err(Fail::Selector(_))));
    }
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

    /// #327: the literal without its all-zero fraction parses or fails with
    /// the reference; with it, Solidity says ParseDecimalPrecisionLoss.
    #[test]
    fn parse_zero_fraction_checks_the_integer_part() {
        let nines = "9".repeat(68);
        for (int, exp) in [
            (nines.as_str(), "e2200000000"),
            (&format!("2{}", "0".repeat(67)), ""),
            (&format!("-2{}", "0".repeat(67)), "e-5"),
        ] {
            let bare = format!("{int}{exp}");
            run(check_parse(&bare));
            for frac in [".0", ".000"] {
                let s = format!("{int}{frac}{exp}");
                match (r::parse(&s), r::parse(&bare)) {
                    (Ok(a), Ok(b)) => assert!(a.eq_value(&b), "{s}"),
                    (Err(a), Err(b)) => assert_eq!(a, b, "{s}"),
                    (a, b) => panic!("{s}: {a:?}, {bare}: {b:?}"),
                }
                assert!(
                    !matches!(r::parse(&s), Err(RefError::ParseDecimalPrecisionLoss)),
                    "{s}"
                );
                assert!(zero_fraction_defect(&s), "{s}");
                assert!(
                    error_matches(
                        &sol_parse(&s).unwrap_err(),
                        RefError::ParseDecimalPrecisionLoss
                    ),
                    "{s}"
                );
            }
        }
    }
}
