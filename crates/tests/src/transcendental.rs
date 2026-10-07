//! log10, pow10, pow and sqrt, over the full Float domain, against the true
//! value from two independent references: astro-float (`precise.rs`) and the
//! Python `decimal` oracle. Each result must be within the bound the library
//! proves (README "log10, pow10, pow and sqrt", and the NatSpec), with no
//! tolerance added; an exact result must be exact; an error must be the one
//! error the documented contract gives.
//! Neighbouring inputs may give results out of order only as the NatSpec
//! allows: by one unit in the last place, with both true values within the
//! raw error of the tie between them; sqrt never.
//!
//! The bounds, as documented:
//! - pow10: half a unit in the 41st digit plus 3.28e-8 of a unit.
//! - log10: half a unit in the 41st digit plus 2e-50 absolute.
//! - pow: 5.0000004e-41 + 3N 1e-75 relative, N the integer part of |b|.
//! - sqrt: correctly rounded, half a unit in the 41st digit.
//! - pow10 and pow: a result below 1e-2147483608 adds 1e-2147483648.

use crate::evm::{self, TestDecimalFloat as T};
use crate::exact::{config, float, show};
use crate::oracle::{self, ask};
use crate::precise::{self, Approx, RANGE, order};
use crate::reference::{self as r, Dec, I32_MAX, I32_MIN, Packed, RefError, pow10};
use alloy::primitives::B256;
use alloy::sol_types::SolCall;
use num_bigint::BigInt;
use num_integer::Integer;
use num_traits::{Signed, Zero};
use proptest::prelude::*;
use proptest::test_runner::TestCaseError;
use serde_json::{Value, json};

// ----------------------------------------------------------------- the EVM

/// A result, or the data it reverted with.
type Sol = Result<Dec, Vec<u8>>;

fn call<C: SolCall<Return = B256>>(c: C) -> Sol {
    evm::float(c).map_err(|output| output.to_vec())
}

/// `x` as an int256 word.
fn word(x: &BigInt) -> [u8; 32] {
    let mut w = [if x.is_negative() { 0xff } else { 0 }; 32];
    let b = x.to_signed_bytes_be();
    w[32 - b.len()..].copy_from_slice(&b);
    w
}

/// The revert data of `e` from a call whose first input is `a`. Every error
/// reports `a` as its coefficient and exponent, but `Log10Zero`, which reports
/// nothing, and `ZeroNegativePower`, which reports pow's `b` packed.
fn revert_data(e: RefError, a: &Dec, b: Option<&Dec>) -> Vec<u8> {
    let mut out = e.selector().to_vec();
    match e {
        RefError::Log10Zero => {}
        RefError::ZeroNegativePower => out.extend_from_slice(bytes(b.expect("pow's b")).as_slice()),
        _ => {
            out.extend_from_slice(&word(&a.c));
            out.extend_from_slice(&word(&BigInt::from(a.e)));
        }
    }
    out
}

fn bytes(a: &Dec) -> B256 {
    a.to_bytes()
}

fn sol_log10(a: &Dec) -> Sol {
    call(T::log10Call { a: bytes(a) })
}

fn sol_pow10(a: &Dec) -> Sol {
    call(T::pow10Call { a: bytes(a) })
}

fn sol_pow(a: &Dec, b: &Dec) -> Sol {
    call(T::powCall {
        a: bytes(a),
        b: bytes(b),
    })
}

fn sol_sqrt(a: &Dec) -> Sol {
    call(T::sqrtCall { a: bytes(a) })
}

// ------------------------------------------------------------ the contract

/// What the documented contract says of one call: the true value (within the
/// reference's own error) or the one error, and the exact result when the
/// contract promises one.
#[derive(Debug)]
pub struct Truth {
    value: Result<Approx, RefError>,
    exact: Option<Dec>,
}

impl Truth {
    fn exact(d: Dec) -> Self {
        Self {
            value: Ok(Approx::exact(d.clone())),
            exact: Some(d),
        }
    }

    fn err(e: RefError) -> Self {
        Self {
            value: Err(e),
            exact: None,
        }
    }

    fn near(t: Approx) -> Self {
        Self {
            exact: t.err.is_none().then(|| t.value.clone()),
            value: Ok(t),
        }
    }
}

fn past(rising: bool) -> RefError {
    if rising {
        RefError::ExponentOverflow
    } else {
        RefError::ExponentUnderflow
    }
}

pub fn truth_log10(a: &Dec) -> Truth {
    if a.is_zero() {
        Truth::err(RefError::Log10Zero)
    } else if a.is_negative() {
        Truth::err(RefError::Log10Negative)
    } else {
        Truth::near(precise::log10(a))
    }
}

/// 10^x, exact for an integer x.
pub fn truth_pow10(x: &Dec) -> Truth {
    if x.is_zero() {
        return Truth::exact(Dec::new(1, 0));
    }
    if x.abs().cmp_value(&Dec::new(RANGE, 0)).is_gt() {
        return Truth::err(past(x.c.is_positive()));
    }
    Truth::near(precise::pow10_true(x))
}

fn is_integer(b: &Dec) -> bool {
    b.normalized().e >= 0
}

fn is_odd(b: &Dec) -> bool {
    let n = b.normalized();
    n.e == 0 && n.c.is_odd()
}

/// `roundSignificant`: 41 significant digits, half away from zero.
pub fn round41(x: &Dec) -> Dec {
    let n = r::digits(&x.c);
    if n <= 41 {
        return x.clone();
    }
    let shed = n - 41;
    let guard = pow10(shed);
    let mut q = &x.c / &guard;
    let rem = &x.c % &guard;
    let half = &guard / 2;
    if rem >= half {
        q += 1;
    } else if rem <= -half {
        q -= 1;
    }
    Dec::new(q, x.e + shed as i64)
}

/// pow's final `packRoundedSignificant` of an exact unpacked value: the
/// rounding, unless it carries past what packs at the exponent ceiling, where
/// the unrounded value packs instead.
pub fn pack_rounded(x: &Dec) -> Result<Dec, RefError> {
    let rounded = round41(x);
    let excess = rounded.e - I32_MAX;
    if (1..=67).contains(&excess) && !r::fits_int224(&(&rounded.c * pow10(excess as u64))) {
        return r::arithmetic(x);
    }
    r::arithmetic(&rounded)
}

/// `b` as p/q in lowest terms, when both are small enough to raise to.
fn small_ratio(b: &Dec) -> Option<(BigInt, u32)> {
    let n = b.normalized();
    if n.e >= 0 {
        if n.e > 3 {
            return None;
        }
        let p = &n.c * pow10(n.e as u64);
        return (p.abs() <= BigInt::from(256)).then_some((p, 1));
    }
    if n.e < -6 {
        return None;
    }
    let den = pow10((-n.e) as u64);
    let g = n.c.gcd(&den);
    let (p, q) = (&n.c / &g, den / &g);
    (p.abs() <= BigInt::from(256) && q <= BigInt::from(64)).then(|| (p, u32::try_from(&q).unwrap()))
}

fn power(d: &Dec, k: u32) -> Dec {
    Dec::new(num_traits::pow(d.c.clone(), k as usize), d.e * k as i64)
}

/// The exact a^b for a > 0 when it has at most 41 significant digits and b
/// is a small ratio p/q: g = round41(approx) is exact iff g^q = a^p.
fn exact_power(a: &Dec, b: &Dec, t: &Approx) -> Option<Dec> {
    let (p, q) = small_ratio(b)?;
    let g = round41(&t.value).normalized();
    let pa = u32::try_from(p.magnitude()).unwrap();
    let lhs = power(&g, q);
    let rhs = power(a, pa);
    let equal = if p.is_positive() {
        lhs.eq_value(&rhs)
    } else {
        lhs.mul_exact(&rhs).eq_value(&Dec::new(1, 0))
    };
    equal.then_some(g)
}

/// a^b as `LibDecimalFloat.pow` documents it.
pub fn truth_pow(a: &Dec, b: &Dec) -> Truth {
    if b.is_zero() {
        return Truth::exact(Dec::new(1, 0));
    }
    if a.is_zero() {
        return if b.is_negative() {
            Truth::err(RefError::ZeroNegativePower)
        } else {
            Truth::exact(Dec::zero())
        };
    }
    let mut negate = false;
    let mut base = a.clone();
    if a.is_negative() {
        if !is_integer(b) {
            return Truth::err(RefError::PowNegativeBase);
        }
        negate = is_odd(b);
        base = a.neg();
    }
    let sign = |d: Dec| if negate { d.neg() } else { d };
    if base.eq_value(&Dec::new(1, 0)) {
        return Truth::exact(sign(Dec::new(1, 0)));
    }
    if b.eq_value(&Dec::new(1, 0)) {
        // a^1 is a, rounded to 41 digits and packed.
        return Truth {
            value: Ok(Approx::exact(a.clone())),
            exact: Some(pack_rounded(a).expect("a Float packs")),
        };
    }
    // (10^j)^b is 10^(jb) exactly, a power with one significant digit when jb
    // is an integer.
    let n = base.normalized();
    if n.c == BigInt::from(1) {
        let y = Dec::new(&b.c * n.e, b.e);
        if y.abs().cmp_value(&Dec::new(RANGE, 0)).is_gt() {
            return Truth::err(past(y.c.is_positive()));
        }
        if is_integer(&y) {
            let k = y.normalized();
            let k = i64::try_from(&(&k.c * pow10(k.e as u64))).expect("|y| <= RANGE");
            return Truth::exact(sign(Dec::new(1, k)));
        }
        let t = precise::pow10_true(&y);
        return Truth::near(Approx {
            value: sign(t.value),
            err: t.err,
        });
    }
    match precise::pow_true(&base, b) {
        Err(rising) => Truth::err(past(rising)),
        Ok(t) => match exact_power(&base, b, &t) {
            Some(g) => Truth::exact(sign(g)),
            None => Truth::near(Approx {
                value: sign(t.value),
                err: t.err,
            }),
        },
    }
}

// ---------------------------------------------------------------- checking

/// Python's answer must be the reference's: the same error, or a value
/// within both references' errors (Python's is under 1e-250 relative).
fn check_python(case: &str, truth: &Truth, py: &Value) -> Result<(), TestCaseError> {
    match (&truth.value, &py["ok"], &py["err"]) {
        (Err(e), _, Value::String(p)) => prop_assert_eq!(e.name(), p.as_str(), "{}: python", case),
        (Ok(t), Value::Array(_), _) => {
            let p = oracle::to_dec(&py["ok"]);
            if t.value.is_zero() {
                prop_assert!(p.is_zero(), "{case}: reference 0, python {p:?}");
                return Ok(());
            }
            let gap = p.add_exact(&t.value.neg()).map(|d| d.abs());
            let allowed = Dec::new(1, order(&t.value) - 250)
                .add_exact(&t.err_dec())
                .unwrap();
            prop_assert!(
                gap.as_ref().is_some_and(|g| !g.cmp_value(&allowed).is_gt()),
                "{case}: reference {t:?}, python {p:?}"
            );
        }
        _ => prop_assert!(false, "{case}: reference {truth:?}, python {py}"),
    }
    Ok(())
}

/// Which bound applies.
#[derive(Debug, Clone)]
pub enum Bound {
    Log10,
    /// pow10 of x with integer part `k`.
    Pow10(i64),
    /// pow with N the integer part of |b|.
    Pow(BigInt),
    Sqrt,
}

fn sum(a: &Dec, b: &Dec) -> Dec {
    a.add_exact(b)
        .expect("terms within 400 digits of each other")
}

fn largest(negative: bool) -> Dec {
    let c = if negative {
        -r::int224_min()
    } else {
        r::int224_max()
    };
    Dec::new(c, I32_MAX)
}

/// The exponent floor's carve-out applies below 1e-2147483608.
fn floor_carve(lowest: &Dec) -> Dec {
    if lowest.cmp_value(&Dec::new(1, I32_MIN + 40)).is_lt() {
        Dec::new(1, I32_MIN)
    } else {
        Dec::zero()
    }
}

fn check_sol(case: &str, sol: Sol, truth: &Truth, bound: &Bound) -> Result<(), TestCaseError> {
    let reverted = |e: RefError| matches!(&sol, Err(s) if *s == e.selector());
    let t = match &truth.value {
        Err(e) => {
            prop_assert!(reverted(*e), "{case}: solidity {sol:?}, want {e:?}");
            return Ok(());
        }
        Ok(t) => t,
    };
    if let Some(d) = &truth.exact {
        match r::pack(d) {
            Packed::Value(v, true) => {
                prop_assert!(
                    matches!(&sol, Ok(s) if s.eq_value(&v)),
                    "{case}: solidity {sol:?}, exactly {v:?}"
                );
                return Ok(());
            }
            Packed::Overflow => {
                prop_assert!(
                    reverted(RefError::ExponentOverflow),
                    "{case}: solidity {sol:?}, want overflow"
                );
                return Ok(());
            }
            Packed::Underflow => {
                prop_assert!(
                    reverted(RefError::ExponentUnderflow),
                    "{case}: solidity {sol:?}, want underflow"
                );
                return Ok(());
            }
            // Shed at the exponent floor: the bound, with its carve-out.
            Packed::Value(_, false) => {}
        }
    }
    let err = t.err_dec();
    let magnitude = t.value.abs();
    // The unit of the true value's 41st digit, the smaller one if the
    // reference's error straddles a power of ten.
    let half_unit = Dec::new(5, order(&sum(&magnitude, &err.neg())) - 41);
    let (within, carve) = match bound {
        Bound::Log10 => (sum(&half_unit, &Dec::new(2, -50)), Dec::zero()),
        Bound::Sqrt => (half_unit, Dec::zero()),
        Bound::Pow10(k) => (Dec::new(5_000_000_328i64, k - 50), Dec::new(1, I32_MIN)),
        Bound::Pow(n) => {
            let relative = Dec::new(BigInt::from(50_000_004) * pow10(27) + n * 3, -75);
            (
                relative.mul_exact(&sum(&magnitude, &err.neg())),
                Dec::new(1, I32_MIN),
            )
        }
    };
    let lowest = sum(&sum(&magnitude, &err.neg()), &within.neg());
    let highest = sum(&sum(&magnitude, &err), &within);
    let carve = if carve.is_zero() {
        carve
    } else {
        floor_carve(&lowest)
    };
    // Only pow10 and pow reach past every Float.
    let ranged = matches!(bound, Bound::Pow10(_) | Bound::Pow(_));
    let below = ranged && lowest.cmp_value(&Dec::new(1, I32_MIN)).is_lt();
    let above = ranged && highest.cmp_value(&largest(t.value.is_negative())).is_gt();
    let under = ranged && highest.cmp_value(&Dec::new(1, I32_MIN)).is_lt();
    let over = ranged && lowest.cmp_value(&largest(t.value.is_negative())).is_gt();
    match &sol {
        Ok(s) => {
            prop_assert!(
                !under && !over,
                "{case}: solidity {s:?}, true {t:?} is past every Float"
            );
            let gap = s.add_exact(&t.value.neg()).map(|d| sum(&d.abs(), &err));
            let allowed = sum(&within, &carve);
            prop_assert!(
                gap.as_ref().is_some_and(|g| !g.cmp_value(&allowed).is_gt()),
                "{case}: solidity {s:?}, true {t:?}, error {gap:?} past {allowed:?}"
            );
        }
        Err(_) if below && reverted(RefError::ExponentUnderflow) => {}
        Err(_) if above && reverted(RefError::ExponentOverflow) => {}
        Err(_) => prop_assert!(false, "{case}: solidity {sol:?}, true {t:?}"),
    }
    Ok(())
}

fn float_json(a: &Dec) -> Value {
    oracle::float(a)
}

pub fn check_log10(a: &Dec) -> Result<(), TestCaseError> {
    let case = format!("log10({})", show(a));
    let truth = truth_log10(a);
    check_python(
        &case,
        &truth,
        &ask(json!({"op": "log10", "a": float_json(a)})),
    )?;
    check_sol(&case, sol_log10(a), &truth, &Bound::Log10)
}

/// floor(x) for |x| at most RANGE. Past it the truth is an error and the
/// bound is unused.
fn floor_in_range(x: &Dec) -> i64 {
    if x.abs().cmp_value(&Dec::new(RANGE, 0)).is_gt() {
        return 0;
    }
    let f = r::floor(x).expect("|x| <= RANGE packs");
    i64::try_from(&(&f.c * pow10(f.e as u64))).expect("|x| <= RANGE")
}

pub fn check_pow10(x: &Dec) -> Result<(), TestCaseError> {
    let case = format!("pow10({})", show(x));
    let truth = truth_pow10(x);
    check_python(
        &case,
        &truth,
        &ask(json!({"op": "pow10", "a": float_json(x)})),
    )?;
    check_sol(
        &case,
        sol_pow10(x),
        &truth,
        &Bound::Pow10(floor_in_range(x)),
    )
}

/// The integer part of |b|, for |b| below 1e90: past that every power of a
/// base other than one is past every Float, and the bound is unused.
fn integer_part(b: &Dec) -> BigInt {
    if order(b) >= 90 {
        return BigInt::zero();
    }
    let t = b.abs().trunc();
    &t.c * pow10(t.e.max(0) as u64)
}

pub fn check_pow(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("pow({}, {})", show(a), show(b));
    let truth = truth_pow(a, b);
    let py = ask(json!({"op": "pow", "a": float_json(a), "b": float_json(b)}));
    check_python(&case, &truth, &py)?;
    let n = if truth.value.is_ok() {
        integer_part(b)
    } else {
        BigInt::zero()
    };
    check_sol(&case, sol_pow(a, b), &truth, &Bound::Pow(n))
}

pub fn check_sqrt(a: &Dec) -> Result<(), TestCaseError> {
    let case = format!("sqrt({})", show(a));
    let half = Dec::new(5, -1);
    let truth = truth_pow(a, &half);
    let py = ask(json!({"op": "pow", "a": float_json(a), "b": float_json(&half)}));
    check_python(&case, &truth, &py)?;
    check_sol(&case, sol_sqrt(a), &truth, &Bound::Sqrt)
}

// ------------------------------------------------------------ monotonicity

/// The raw error before rounding, as documented: the distance from a rounding
/// tie within which two results can come out in the wrong order.
fn raw(bound: &Bound, t: &Approx) -> Dec {
    match bound {
        Bound::Log10 => Dec::new(2, -50),
        Bound::Pow10(k) => Dec::new(328, k - 50),
        Bound::Pow(n) => {
            Dec::new(BigInt::from(333) * pow10(25) + n * 3, -75).mul_exact(&t.value.abs())
        }
        // Correctly rounded: never out of order, which check_monotone asserts.
        Bound::Sqrt => Dec::zero(),
    }
}

/// One call of a pair whose true values are in order.
struct Point {
    sol: Sol,
    truth: Truth,
    bound: Bound,
}

/// `lower`'s true value is below `upper`'s. Their results may be out of order
/// only by exactly one unit in the last place, and only when both true values
/// lie within the larger raw error of the tie between the two results.
fn check_monotone(case: &str, lower: Point, upper: Point) -> Result<(), TestCaseError> {
    let (Ok(a), Ok(b), Ok(ta), Ok(tb)) = (
        &lower.sol,
        &upper.sol,
        &lower.truth.value,
        &upper.truth.value,
    ) else {
        return Ok(());
    };
    if !a.cmp_value(b).is_gt() {
        return Ok(());
    }
    prop_assert!(
        !matches!(lower.bound, Bound::Sqrt),
        "{case}: {a:?} > {b:?}, and sqrt is monotone"
    );
    let larger = if a.abs().cmp_value(&b.abs()).is_gt() {
        a.abs()
    } else {
        b.abs()
    };
    let ulp = Dec::new(1, order(&larger) - 40);
    let gap = sum(a, &b.neg());
    prop_assert!(
        !gap.cmp_value(&ulp).is_gt(),
        "{case}: {a:?} > {b:?} by more than {ulp:?}"
    );
    let tie = sum(a, b).mul_exact(&Dec::new(5, -1));
    let (ra, rb) = (raw(&lower.bound, ta), raw(&upper.bound, tb));
    let most = if ra.cmp_value(&rb).is_gt() { ra } else { rb };
    for t in [ta, tb] {
        let off = sum(&sum(&t.value, &tie.neg()).abs(), &t.err_dec().neg());
        prop_assert!(
            !off.cmp_value(&most).is_gt(),
            "{case}: {a:?} > {b:?}, true {t:?} is {off:?} from the tie {tie:?}"
        );
    }
    Ok(())
}

/// The next Float up at the same exponent.
fn next(a: &Dec) -> Option<Dec> {
    let c = &a.c + 1;
    r::fits_int224(&c).then(|| Dec::new(c, a.e))
}

fn point_log10(a: &Dec) -> Point {
    Point {
        sol: sol_log10(a),
        truth: truth_log10(a),
        bound: Bound::Log10,
    }
}

fn point_pow10(x: &Dec) -> Point {
    Point {
        sol: sol_pow10(x),
        truth: truth_pow10(x),
        bound: Bound::Pow10(floor_in_range(x)),
    }
}

fn point_pow(a: &Dec, b: &Dec) -> Point {
    let truth = truth_pow(a, b);
    let n = if truth.value.is_ok() {
        integer_part(b)
    } else {
        BigInt::zero()
    };
    Point {
        sol: sol_pow(a, b),
        truth,
        bound: Bound::Pow(n),
    }
}

fn point_sqrt(a: &Dec) -> Point {
    Point {
        sol: sol_sqrt(a),
        truth: truth_pow(a, &Dec::new(5, -1)),
        bound: Bound::Sqrt,
    }
}

pub fn monotone_log10(a: &Dec) -> Result<(), TestCaseError> {
    let a = a.abs();
    let Some(b) = next(&a).filter(|_| !a.is_zero()) else {
        return Ok(());
    };
    check_monotone(
        &format!("log10({}) and log10({})", show(&a), show(&b)),
        point_log10(&a),
        point_log10(&b),
    )
}

pub fn monotone_pow10(x: &Dec) -> Result<(), TestCaseError> {
    let Some(y) = next(x) else { return Ok(()) };
    check_monotone(
        &format!("pow10({}) and pow10({})", show(x), show(&y)),
        point_pow10(x),
        point_pow10(&y),
    )
}

/// a^b against a^b' for the next b' up: rising in b for a above one, falling
/// below.
pub fn monotone_pow(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let Some(c) = next(b) else { return Ok(()) };
    let case = format!(
        "pow({0}, {1}) and pow({0}, {2})",
        show(a),
        show(b),
        show(&c)
    );
    if a.cmp_value(&Dec::new(1, 0)).is_gt() {
        check_monotone(&case, point_pow(a, b), point_pow(a, &c))
    } else {
        check_monotone(&case, point_pow(a, &c), point_pow(a, b))
    }
}

pub fn monotone_sqrt(a: &Dec) -> Result<(), TestCaseError> {
    let a = a.abs();
    let Some(b) = next(&a) else { return Ok(()) };
    check_monotone(
        &format!("sqrt({}) and sqrt({})", show(&a), show(&b)),
        point_sqrt(&a),
        point_sqrt(&b),
    )
}

// -------------------------------------------------------------- strategies

fn digits_below(n: u32) -> BoxedStrategy<BigInt> {
    any::<[u8; 32]>()
        .prop_map(move |b| BigInt::from_bytes_be(num_bigint::Sign::Plus, &b) % pow10(n as u64))
        .boxed()
}

/// k + f for an integer k and up to `max_frac` fraction digits, either sign.
fn with_fraction(k: BoxedStrategy<i64>, max_frac: u32) -> BoxedStrategy<Dec> {
    (k, 0..=max_frac)
        .prop_flat_map(|(k, n)| {
            digits_below(n)
                .prop_map(move |f| Dec::new(BigInt::from(k) * pow10(n as u64) + f, -(n as i64)))
        })
        .prop_filter("int224", |d| r::fits_int224(&d.c))
        .boxed()
}

/// An integer in another representation: k 10^j at exponent -j.
fn spread(k: BoxedStrategy<i64>) -> BoxedStrategy<Dec> {
    (k, 0u64..=40)
        .prop_map(|(k, j)| Dec::new(BigInt::from(k) * pow10(j), -(j as i64)))
        .prop_filter("int224", |d| r::fits_int224(&d.c))
        .boxed()
}

/// Integer parts at the edges of the range of 10^x: the exponent floor and
/// the carve-out above it, and the ceiling with the coefficient's 67 digits.
fn edge_integer() -> BoxedStrategy<i64> {
    prop_oneof![
        I32_MIN - 3..=I32_MIN + 45,
        I32_MAX - 3..=I32_MAX + 70,
        -3i64..=3,
    ]
    .boxed()
}

fn x_pow10() -> BoxedStrategy<Dec> {
    prop_oneof![
        2 => float(),
        3 => with_fraction((-2_200_000_000i64..=2_200_000_000).boxed(), 55),
        3 => with_fraction((-120i64..=120).boxed(), 66),
        2 => with_fraction(edge_integer(), 56),
        1 => spread(edge_integer()),
        1 => spread((-2_200_000_000i64..=2_200_000_000).boxed()),
        // Within 1e-50 of an integer, where the fraction truncates to zero.
        1 => (edge_integer(), 51u64..=66, any::<bool>()).prop_map(|(k, n, up)| {
            let c = BigInt::from(k) * pow10(n) + if up { 1 } else { -1 };
            Dec::new(c, -(n as i64))
        }).prop_filter("int224", |d| r::fits_int224(&d.c)),
    ]
    .boxed()
}

fn a_log10() -> BoxedStrategy<Dec> {
    prop_oneof![
        4 => float(),
        // Powers of ten, the exact anchors, in every representation.
        1 => (0u64..=66, crate::exact::exponent()).prop_map(|(j, e)| Dec::new(pow10(j), e)),
        // Next to a power of ten, and within a table step of one.
        2 => (0u64..=66, -1000i64..=1000, crate::exact::exponent()).prop_map(|(j, d, e)| Dec::new(pow10(j) + d, e)),
    ]
    .boxed()
}

/// A positive a with a coefficient of any digit count near 1e-70 to 1e77.
fn moderate() -> BoxedStrategy<Dec> {
    (crate::exact::coefficient(), -70i64..=10)
        .prop_filter("nonzero", |(c, _)| !c.is_zero())
        .prop_map(|(c, e)| Dec::new(c.abs().min(r::int224_max()), e))
        .boxed()
}

fn small_b() -> BoxedStrategy<Dec> {
    prop_oneof![
        3 => (-400i64..=400).prop_map(|n| Dec::new(n, 0)),
        3 => (-1_000_000_000i64..=1_000_000_000, -9i64..=0).prop_map(|(c, e)| Dec::new(c, e)),
        1 => Just(Dec::new(5, -1)),
        1 => (crate::exact::coefficient(), -80i64..=20).prop_map(|(c, e)| Dec::new(c, e)),
    ]
    .boxed()
}

/// b = t / log10(a) for a = 10^j, with t at the edges of the range.
fn edge_pow() -> BoxedStrategy<(Dec, Dec)> {
    (
        prop_oneof![Just(1i64), Just(2), Just(4), Just(5)],
        any::<bool>(),
        with_fraction(edge_integer(), 30),
    )
        .prop_map(|(j, below, t)| {
            // t / j, exactly: j divides 10^2.
            let scale = 100 / j;
            let b = Dec::new(&t.c * scale, t.e - 2);
            if below {
                (Dec::new(1, -j), b.neg())
            } else {
                (Dec::new(1, j), b)
            }
        })
        .prop_filter("int224", |(_, b)| r::fits_int224(&b.c))
        .boxed()
}

/// g^k and 1/k, whose power is exactly g, for every g whose g^k fits.
fn root_anchor() -> BoxedStrategy<(Dec, Dec)> {
    prop_oneof![
        Just(2u32),
        Just(4),
        Just(5),
        Just(8),
        Just(10),
        Just(16),
        Just(20),
        Just(25)
    ]
    .prop_flat_map(|k| {
        // g below 10^(66 / k) keeps g^k under 1e66, inside int224.
        let most = 10u64.pow((66 / k).min(19));
        (1..most, -5i64..=5).prop_map(move |(g, e)| {
            let a = power(&Dec::new(g, e), k);
            (a, Dec::new(BigInt::from(10_000 / k), -4))
        })
    })
    .boxed()
}

fn pow_pair() -> BoxedStrategy<(Dec, Dec)> {
    prop_oneof![
        2 => (float(), float()),
        4 => (moderate(), small_b()),
        2 => edge_pow(),
        // a within 1e-66 of one, and a large b.
        1 => (-1000i64..=1000, crate::exact::coefficient(), 40i64..=80).prop_map(|(d, c, e)| {
            (Dec::new(pow10(66) + d, -66), Dec::new(c, e))
        }),
        // Negative bases, whole and fractional b.
        2 => (moderate(), small_b()).prop_map(|(a, b)| (a.neg(), b)),
        // Zero bases.
        1 => (Just(Dec::zero()), float()),
        // b one in any representation: a^1 rounds a to 41 digits.
        2 => (float(), 0u64..=60).prop_map(|(a, j)| (a, Dec::new(pow10(j), -(j as i64)))),
        // Small integer powers, often exact.
        2 => (1i64..=1_000_000, -3i64..=3, -30i64..=30).prop_map(|(g, e, n)| (Dec::new(g, e), Dec::new(n, 0))),
        2 => root_anchor(),
    ]
    .boxed()
}

fn a_sqrt() -> BoxedStrategy<Dec> {
    prop_oneof![
        3 => float(),
        // Perfect squares of up to 33 digits, whose root is exact.
        2 => (1u32..=33, -1_000_000_000i64..=1_000_000_000).prop_flat_map(|(n, e)| {
            digits_below(n).prop_map(move |c| {
                let c = if c.is_zero() { BigInt::from(1) } else { c };
                Dec::new(&c * &c, 2 * e)
            })
        }),
    ]
    .boxed()
}

proptest! {
    #![proptest_config(config())]

    #[test]
    fn exact_log10(a in a_log10()) { check_log10(&a)?; }

    #[test]
    fn exact_pow10(x in x_pow10()) { check_pow10(&x)?; }

    #[test]
    fn exact_pow((a, b) in pow_pair()) { check_pow(&a, &b)?; }

    #[test]
    fn exact_sqrt(a in a_sqrt()) { check_sqrt(&a)?; }

    #[test]
    fn monotone_log10_neighbours(a in a_log10()) { monotone_log10(&a)?; }

    #[test]
    fn monotone_pow10_neighbours(x in x_pow10()) { monotone_pow10(&x)?; }

    #[test]
    fn monotone_pow_neighbours((a, b) in (moderate(), small_b())) { monotone_pow(&a, &b)?; }

    #[test]
    fn monotone_sqrt_neighbours(a in a_sqrt()) { monotone_sqrt(&a)?; }
}

/// The checks themselves, on made-up results: each accepts a result at
/// exactly the documented bound and rejects one a step past it, so the bounds
/// are the NatSpec's with no margin, with the reference's own error taken off.
mod checker {
    use super::*;

    /// A reference value within 300 digits below its leading one.
    fn near(value: Dec) -> Truth {
        let err = Some(order(&value) - 300);
        Truth::near(Approx { value, err })
    }

    fn accepts(truth: &Truth, bound: &Bound, sol: Sol) -> bool {
        check_sol("checker", sol, truth, bound).is_ok()
    }

    /// `v + within - err` is the furthest result the bound admits, and a
    /// step of `step` further is past it.
    fn edge(v: &Dec, bound: &Bound, within: &Dec, step: &Dec) {
        let truth = near(v.clone());
        let err = Dec::new(1, order(v) - 300);
        let at = sum(&sum(v, within), &err.neg());
        assert!(accepts(&truth, bound, Ok(at.clone())), "{at:?} for {v:?}");
        let past = sum(&at, step);
        assert!(
            !accepts(&truth, bound, Ok(past.clone())),
            "{past:?} for {v:?}"
        );
        let low = sum(&sum(v, &within.neg()), &err);
        assert!(accepts(&truth, bound, Ok(low.clone())), "{low:?} for {v:?}");
        let below = sum(&low, &step.neg());
        assert!(
            !accepts(&truth, bound, Ok(below.clone())),
            "{below:?} for {v:?}"
        );
    }

    #[test]
    fn log10_bound() {
        // Half a unit in the 41st digit of 2, plus 2e-50.
        let within = sum(&Dec::new(5, -41), &Dec::new(2, -50));
        edge(&Dec::new(2, 0), &Bound::Log10, &within, &Dec::new(1, -310));
        // A true value that may be just below one takes the 41st digit there.
        let within = sum(&Dec::new(5, -42), &Dec::new(2, -50));
        edge(&Dec::new(1, 0), &Bound::Log10, &within, &Dec::new(1, -310));
    }

    #[test]
    fn sqrt_bound() {
        // Half a unit in the 41st digit, nothing more.
        edge(
            &Dec::new(2, 0),
            &Bound::Sqrt,
            &Dec::new(5, -41),
            &Dec::new(1, -310),
        );
        edge(
            &Dec::new(1, 0),
            &Bound::Sqrt,
            &Dec::new(5, -42),
            &Dec::new(1, -310),
        );
        // Never past every Float.
        let under = || -> Sol { Err(RefError::ExponentUnderflow.selector()) };
        assert!(!accepts(&near(Dec::new(1, I32_MIN)), &Bound::Sqrt, under()));
    }

    #[test]
    fn pow10_bound() {
        // 3.5 has integer part 0: half a unit plus 3.28e-8 of one, 1e-40.
        let within = Dec::new(5_000_000_328i64, -50);
        edge(
            &Dec::new(35, -1),
            &Bound::Pow10(0),
            &within,
            &Dec::new(1, -310),
        );
    }

    #[test]
    fn pow_bound() {
        // N = 7: 5.0000004e-41 + 21e-75 relative to the true value.
        let v = Dec::new(2, 0);
        let relative = sum(&Dec::new(50_000_004, -48), &Dec::new(21, -75));
        let within = relative.mul_exact(&sum(&v, &Dec::new(-1, -300)));
        edge(
            &v,
            &Bound::Pow(BigInt::from(7)),
            &within,
            &Dec::new(1, -310),
        );
    }

    /// At or above 1e-2147483608 the bound has no carve-out; below it, it adds
    /// 1e-2147483648.
    #[test]
    fn floor_carve_out() {
        let k = -2147483608;
        let within = Dec::new(5_000_000_328i64, k - 50);
        let step = Dec::new(1, I32_MIN - 12);
        edge(&Dec::new(5, k), &Bound::Pow10(k), &within, &step);
        let k = -2147483620;
        let within = sum(&Dec::new(5_000_000_328i64, k - 50), &Dec::new(1, I32_MIN));
        edge(&Dec::new(5, k), &Bound::Pow10(k), &within, &step);
    }

    /// A revert is accepted only where the bound reaches past every Float.
    #[test]
    fn reverts() {
        let under = || -> Sol { Err(RefError::ExponentUnderflow.selector()) };
        let over = || -> Sol { Err(RefError::ExponentOverflow.selector()) };
        let ordinary = near(Dec::new(5, -100));
        assert!(!accepts(&ordinary, &Bound::Pow(BigInt::zero()), under()));
        assert!(!accepts(&ordinary, &Bound::Pow(BigInt::zero()), over()));
        // 5e-2147483648 is a Float: no underflow for it.
        let lowest = near(Dec::new(5, I32_MIN));
        assert!(!accepts(&lowest, &Bound::Pow10(I32_MIN), under()));
        // Straddling the floor, either.
        let straddle = near(Dec::new(1, I32_MIN));
        assert!(accepts(&straddle, &Bound::Pow10(I32_MIN), under()));
        assert!(accepts(
            &straddle,
            &Bound::Pow10(I32_MIN),
            Ok(Dec::new(1, I32_MIN))
        ));
        // Past every Float: only the error.
        let tiny = near(Dec::new(1, I32_MIN - 100));
        assert!(accepts(&tiny, &Bound::Pow10(I32_MIN - 100), under()));
        assert!(!accepts(
            &tiny,
            &Bound::Pow10(I32_MIN - 100),
            Ok(Dec::new(1, I32_MIN))
        ));
        let huge = near(Dec::new(1, I32_MAX + 100));
        assert!(accepts(&huge, &Bound::Pow10(I32_MAX + 100), over()));
        assert!(!accepts(
            &huge,
            &Bound::Pow10(I32_MAX + 100),
            Ok(largest(false))
        ));
        // Straddling the top, either.
        let top = near(largest(false));
        let k = I32_MAX + 67;
        assert!(accepts(&top, &Bound::Pow10(k), over()));
        assert!(accepts(&top, &Bound::Pow10(k), Ok(largest(false))));
        // log10 never over- or underflows.
        assert!(!accepts(&ordinary, &Bound::Log10, under()));
        // The most negative Float is one further from zero than the largest.
        assert!(largest(true).eq_value(&Dec::new(-r::int224_min(), I32_MAX)));
        assert!(largest(false).eq_value(&Dec::new(r::int224_max(), I32_MAX)));
    }

    #[test]
    fn exact_and_errors() {
        let two = Truth::exact(Dec::new(2, 0));
        assert!(accepts(&two, &Bound::Log10, Ok(Dec::new(20, -1))));
        assert!(!accepts(
            &two,
            &Bound::Log10,
            Ok(sum(&Dec::new(2, 0), &Dec::new(1, -50)))
        ));
        let past = Truth::exact(Dec::new(1, I32_MAX + 68));
        assert!(accepts(
            &past,
            &Bound::Pow10(0),
            Err(RefError::ExponentOverflow.selector())
        ));
        assert!(!accepts(
            &past,
            &Bound::Pow10(0),
            Err(RefError::ExponentUnderflow.selector())
        ));
        let gone = Truth::exact(Dec::new(1, I32_MIN - 1));
        assert!(accepts(
            &gone,
            &Bound::Pow10(0),
            Err(RefError::ExponentUnderflow.selector())
        ));
        assert!(!accepts(
            &gone,
            &Bound::Pow10(0),
            Err(RefError::ExponentOverflow.selector())
        ));
        let e = Truth::err(RefError::Log10Zero);
        assert!(accepts(
            &e,
            &Bound::Log10,
            Err(RefError::Log10Zero.selector())
        ));
        assert!(!accepts(
            &e,
            &Bound::Log10,
            Err(RefError::Log10Negative.selector())
        ));
        assert!(!accepts(&e, &Bound::Log10, Ok(Dec::zero())));
    }

    #[test]
    fn python_check() {
        let t = near(Dec::new(2, 0));
        let py = |s: &str| json!({"ok": [s, -60]});
        // Within 1e-250 + 1e-300 of 2 at 60 digits is only 2 itself.
        let two = format!("2{}", "0".repeat(60));
        assert!(check_python("p", &t, &py(&two)).is_ok());
        let off = format!("2{}1", "0".repeat(59));
        assert!(check_python("p", &t, &py(&off)).is_err());
        // At 300 digits: 2 + 1e-250 + 1e-300 is the furthest Python may be.
        let py300 = |s: String| json!({"ok": [s, -300]});
        let at: BigInt = BigInt::from(2) * pow10(300) + pow10(50) + 1;
        assert!(check_python("p", &t, &py300(at.to_string())).is_ok());
        assert!(check_python("p", &t, &py300((at + 1u32).to_string())).is_err());
        let zero = Truth::exact(Dec::zero());
        assert!(check_python("p", &zero, &json!({"ok": ["0", 0]})).is_ok());
        assert!(check_python("p", &zero, &json!({"ok": ["1", -400]})).is_err());
        let e = Truth::err(RefError::Log10Zero);
        assert!(check_python("p", &e, &json!({"err": "Log10Zero"})).is_ok());
        assert!(check_python("p", &e, &json!({"err": "Log10Negative"})).is_err());
        assert!(check_python("p", &e, &json!({"ok": ["0", 0]})).is_err());
    }

    fn point(sol: Dec, value: Dec, bound: Bound) -> Point {
        Point {
            sol: Ok(sol),
            truth: near(value),
            bound,
        }
    }

    /// Results one unit out of order, with the true values at `d` either side
    /// of the tie between them.
    fn reorder(bound: Bound, d: &Dec) -> Result<(), TestCaseError> {
        let (a, b) = (
            Dec::new(BigInt::from(1) * pow10(40) + 1, -40),
            Dec::new(1, 0),
        );
        let tie = Dec::new(BigInt::from(2) * pow10(40) + 1, -40).mul_exact(&Dec::new(5, -1));
        check_monotone(
            "m",
            point(a, sum(&tie, &d.neg()), bound.clone()),
            point(b, sum(&tie, d), bound),
        )
    }

    /// Out of order by one unit only within the raw error of the tie.
    #[test]
    fn monotone() {
        let fuzz = Dec::new(1, -300);
        let step = Dec::new(1, -310);
        for (bound, raw) in [
            (Bound::Log10, Dec::new(2, -50)),
            (Bound::Pow10(0), Dec::new(328, -50)),
            (Bound::Pow10(3), Dec::new(328, -47)),
        ] {
            let at = sum(&raw, &fuzz);
            assert!(reorder(bound.clone(), &at).is_ok(), "{bound:?}");
            assert!(
                reorder(bound.clone(), &sum(&at, &step)).is_err(),
                "{bound:?}"
            );
        }
        // sqrt: never, even with both true values at the tie.
        assert!(reorder(Bound::Sqrt, &Dec::zero()).is_err());
        // pow: 3.33e-48 relative to the larger true value, the lower point's.
        let tie = Dec::new(BigInt::from(2) * pow10(40) + 1, -40).mul_exact(&Dec::new(5, -1));
        let raw = Dec::new(333, -50);
        let pow = |d: &Dec| {
            let hi = Dec::new(BigInt::from(1) * pow10(40) + 1, -40);
            check_monotone(
                "m",
                point(hi, tie.clone(), Bound::Pow(BigInt::zero())),
                point(
                    Dec::new(1, 0),
                    sum(&tie, &d.neg()),
                    Bound::Pow(BigInt::zero()),
                ),
            )
        };
        let at = sum(&raw.mul_exact(&tie), &fuzz);
        assert!(pow(&at).is_ok());
        assert!(pow(&sum(&at, &step)).is_err());
        // Two units out of order, even with both true values at the tie.
        let mid = Dec::new(BigInt::from(1) * pow10(40) + 1, -40);
        let two = check_monotone(
            "m",
            point(
                Dec::new(BigInt::from(1) * pow10(40) + 2, -40),
                mid.clone(),
                Bound::Log10,
            ),
            point(Dec::new(1, 0), mid, Bound::Log10),
        );
        assert!(two.is_err());
        // The unit is the larger result's: 1 against 1 - 1e-40.
        let below = Dec::new(pow10(40) - 1, -40);
        let tie = sum(&Dec::new(1, 0), &Dec::new(-5, -41));
        let across = check_monotone(
            "m",
            point(Dec::new(1, 0), tie.clone(), Bound::Log10),
            point(below, tie, Bound::Log10),
        );
        assert!(across.is_ok());
        // In order is always fine.
        assert!(
            check_monotone(
                "m",
                point(Dec::new(1, 0), Dec::new(1, 0), Bound::Log10),
                point(Dec::new(5, 0), Dec::new(5, 0), Bound::Log10),
            )
            .is_ok()
        );
    }

    #[test]
    fn integer_parts() {
        assert_eq!(floor_in_range(&Dec::new(-25, -1)), -3);
        assert_eq!(floor_in_range(&Dec::new(25, -1)), 2);
        assert_eq!(floor_in_range(&Dec::new(3, 1)), 30);
        assert_eq!(floor_in_range(&Dec::new(1, 100)), 0);
        assert_eq!(integer_part(&Dec::new(-75, -1)), BigInt::from(7));
        assert_eq!(integer_part(&Dec::new(12, 1)), BigInt::from(120));
        assert_eq!(integer_part(&Dec::new(1, 95)), BigInt::zero());
    }
}

/// The documented anchors, each checked against the reference's own answer
/// and then through the same checks as the fuzz.
mod anchors {
    use super::*;

    fn run(r: Result<(), TestCaseError>) {
        if let Err(e) = r {
            panic!("{e}");
        }
    }

    fn d(s: &str) -> Dec {
        r::literal_value(s)
    }

    fn exactly(t: Truth, want: &str) {
        let w = d(want);
        assert!(
            matches!(&t.exact, Some(e) if e.eq_value(&w)),
            "{t:?} is not exactly {want}"
        );
    }

    #[test]
    fn pow10_of_an_integer_is_exact() {
        for k in [
            "0",
            "1",
            "-1",
            "41",
            "-2147483648",
            "2147483647",
            "2147483713",
            "2147483714",
        ] {
            exactly(truth_pow10(&d(k)), &format!("1e{k}"));
            run(check_pow10(&d(k)));
        }
        run(check_pow10(&Dec::new(20, -1)));
        // 1e2147483714 is 1e67 at the ceiling; one more is 68 digits, past
        // every Float. Below the floor.
        run(check_pow10(&d("2147483715")));
        run(check_pow10(&d("-2147483649")));
        assert!(truth_pow10(&d("-2147483649")).exact.is_some());
    }

    #[test]
    fn log10_of_a_power_of_ten_is_exact() {
        for (a, k) in [
            ("1", "0"),
            ("1000", "3"),
            ("0.001", "-3"),
            ("1e-2147483648", "-2147483648"),
            ("1e2147483647", "2147483647"),
        ] {
            exactly(truth_log10(&d(a)), k);
            run(check_log10(&d(a)));
        }
        run(check_log10(&Dec::new(pow10(66), -66)));
        run(check_log10(&Dec::new(pow10(66), I32_MAX)));
    }

    #[test]
    fn exact_powers_and_roots() {
        for (a, b, want) in [
            ("4", "0.5", "2"),
            ("2", "10", "1024"),
            ("2", "-3", "0.125"),
            ("-2", "3", "-8"),
            ("-2", "2", "4"),
            ("0.0625", "0.25", "0.5"),
            ("1e10", "0.5", "1e5"),
            ("10", "-2147483648", "1e-2147483648"),
            ("0", "0", "1"),
            ("0", "2", "0"),
            ("-1", "1e10", "1"),
            ("-1", "3", "-1"),
            ("-10", "3", "-1000"),
            ("-0.1", "-3", "-1000"),
            ("7", "0", "1"),
            ("1", "1e100", "1"),
        ] {
            exactly(truth_pow(&d(a), &d(b)), want);
            run(check_pow(&d(a), &d(b)));
        }
        exactly(
            truth_pow(&d("152415787532388367501905199875019052100"), &d("0.5")),
            "12345678901234567890",
        );
        run(check_sqrt(&d("152415787532388367501905199875019052100")));
        run(check_sqrt(&d("4")));
        run(check_sqrt(&d("0")));
    }

    /// a^1 is a rounded half away from zero at 41 digits.
    #[test]
    fn pow_one_rounds_a() {
        let a = Dec::new(BigInt::from(123456789) * pow10(40) + 5 * pow10(7), -3);
        let t = truth_pow(&a, &d("1"));
        let want = Dec::new(BigInt::from(123456789) * pow10(32) + 1, 5);
        assert!(t.exact.as_ref().unwrap().eq_value(&want), "{t:?}");
        run(check_pow(&a, &d("1")));
        run(check_pow(&a.neg(), &d("1")));
    }

    /// At the exponent ceiling, a rounding that carries past int224 packs the
    /// unrounded a instead.
    #[test]
    fn pow_one_at_the_ceiling() {
        let a = Dec::new(r::int224_max(), I32_MAX);
        let t = truth_pow(&a, &d("1"));
        assert!(t.exact.as_ref().unwrap().eq_value(&a), "{t:?}");
        run(check_pow(&a, &d("1")));
    }

    /// The one error the contract gives: the truth's, or the exact result's
    /// when it is past every Float.
    fn contract_error(t: &Truth) -> Option<RefError> {
        match (&t.value, &t.exact) {
            (Err(e), _) => Some(*e),
            (Ok(_), Some(x)) => match r::pack(x) {
                Packed::Overflow => Some(RefError::ExponentOverflow),
                Packed::Underflow => Some(RefError::ExponentUnderflow),
                Packed::Value(..) => None,
            },
            (Ok(_), None) => None,
        }
    }

    #[test]
    fn errors() {
        for (a, b, e) in [
            ("0", "-1", RefError::ZeroNegativePower),
            ("-2", "0.5", RefError::PowNegativeBase),
            ("2", "1e100", RefError::ExponentOverflow),
            ("2", "-1e100", RefError::ExponentUnderflow),
            ("0.5", "1e100", RefError::ExponentUnderflow),
            ("10", "2147483715", RefError::ExponentOverflow),
            ("10", "1e10", RefError::ExponentOverflow),
            ("0.1", "1e10", RefError::ExponentUnderflow),
        ] {
            assert_eq!(contract_error(&truth_pow(&d(a), &d(b))), Some(e), "{a}^{b}");
            run(check_pow(&d(a), &d(b)));
        }
        assert!(matches!(
            truth_log10(&d("0")).value,
            Err(RefError::Log10Zero)
        ));
        assert!(matches!(
            truth_log10(&d("-1")).value,
            Err(RefError::Log10Negative)
        ));
        run(check_log10(&d("0")));
        run(check_log10(&d("-1")));
        run(check_sqrt(&d("-4")));
        run(check_pow10(&d("1e100")));
        run(check_pow10(&d("-1e100")));
    }

    /// Below 1e-2147483608 a result sheds digits to lift its exponent to the
    /// floor, and the bound adds 1e-2147483648.
    #[test]
    fn floor_carve_out() {
        run(check_pow10(&d("-2147483640.5")));
        run(check_pow(&d("10"), &d("-2147483640.5")));
        run(check_pow10(&d("-2147483647.99")));
    }
}
