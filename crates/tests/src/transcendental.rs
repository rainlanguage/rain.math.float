//! log10, pow10, pow and sqrt, over the full Float domain, against the true
//! value from two independent references: astro-float (`precise.rs`) and the
//! Python `decimal` oracle. Each result must be within the bound the library
//! proves (`test/lib/LibTestErrorBound.sol`), with no
//! tolerance added; an exact result must be exact; an error must be the one
//! error the documented contract gives.
//! Neighbouring inputs may give results out of order only as the NatSpec
//! allows: by one unit in the last place, with both true values within the
//! raw error of the tie between them; sqrt never.
//!
//! The bounds, as proven in `test/lib/LibTestErrorBound.sol`:
//! - pow10: half a unit in the 41st digit plus 1.1111e-8 of a unit.
//! - log10: half a unit in the 41st digit plus 1.0037e-50 absolute.
//! - pow: 5.00000011343e-41 + N min(K1, K2 d) relative, N the integer part
//!   of |b| and d = max(|a|, 1/|a|) - 1: `PowTerm`.
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
pub(crate) fn revert_data(e: RefError, a: &Dec, b: Option<&Dec>) -> Vec<u8> {
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

/// log10Unrounded's error, absolute, in units of 1e-54: `LOG10_RAW_ERROR_E54`.
const LOG10_RAW_E54: i64 = 10_037;

/// pow10Unrounded's error in units of 1e-52 of 10^k, k the integer part of
/// x: `POW10_RAW_ERROR_E52`.
const POW10_RAW_E52: i64 = 11_111;

/// Half a unit in the 41st digit of a power below 10, in units of 1e-52.
const POW10_HALF_UNIT_E52: i64 = 500_000_000_000;

/// pow's error before its integer part, relative, in units of 1e-52:
/// `POW_RELATIVE_ERROR_E52`.
const POW_RELATIVE_E52: i64 = 500_000_011_343;

fn log10_raw() -> Dec {
    Dec::new(LOG10_RAW_E54, -54)
}

fn pow10_within(k: i64) -> Dec {
    Dec::new(POW10_HALF_UNIT_E52 + POW10_RAW_E52, k - 52)
}

/// pow's K1 for b > 0, in units of 1e-80: `POW_K1_E80`.
const POW_K1_E80: i64 = 17_273;

/// pow's K1 for b < 0, in units of 1e-80: `POW_INVERSE_K1_E80`.
const POW_INVERSE_K1_E80: i64 = 117_280;

/// pow's K2 for b > 0, in units of 1e-42: `POW_K2_E42`.
const POW_K2_E42: i64 = 15_000;

/// pow's K2 for b < 0, in units of 1e-42: `POW_INVERSE_K2_E42`.
const POW_INVERSE_K2_E42: i64 = 34_786;

fn pow_base() -> Dec {
    Dec::new(POW_RELATIVE_E52, -52)
}

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

/// a > 0 as c 2^i 5^j, c coprime to ten.
fn split_ten(a: &Dec) -> (BigInt, i64, i64) {
    let n = a.normalized();
    let (mut c, mut i, mut j) = (n.c, n.e, n.e);
    while c.is_even() {
        c /= 2;
        i += 1;
    }
    while (&c % 5u32).is_zero() {
        c /= 5;
        j += 1;
    }
    (c, i, j)
}

fn power(d: &Dec, k: u32) -> Dec {
    Dec::new(num_traits::pow(d.c.clone(), k as usize), d.e * k as i64)
}

/// The exact a^b for a > 0 when it has at most 41 significant digits, from
/// exact maths alone. For b = p/q in lowest terms a^b is rational only when
/// a = r^q for a rational r, and is then r^p. With a = c 2^i 5^j, c coprime
/// to ten, r = s 2^(i/q) 5^(j/q): q divides i and j, and c = s^q. r^p is a
/// terminating decimal only when s^p is an integer, so s = 1 for p < 0, and
/// its significant digits are those of s^p 2^(X - t) 5^(Y - t), X = pi/q,
/// Y = pj/q, t = min(X, Y), with no trailing zero as one of the two powers is
/// one.
///
/// None past b = c 10^12 or c 10^-40: there q has 2^41 or 5^41 in it, which
/// divides neither i nor j under 2^33 unless both are zero, nor c under 2^224
/// unless c is one and a is one, so a^b is not exact; or |p| is over 10^12,
/// which an exact power under 1e41 has only for r a power of ten, past every
/// Float, as is any t past 2^40.
fn exact_power(a: &Dec, b: &Dec) -> Option<Dec> {
    let b = b.normalized();
    if b.e > 12 || b.e < -40 {
        return None;
    }
    let (p, q) = if b.e >= 0 {
        (&b.c * pow10(b.e as u64), BigInt::from(1))
    } else {
        let den = pow10((-b.e) as u64);
        let g = b.c.gcd(&den);
        (&b.c / &g, den / g)
    };
    let (c, i, j) = split_ten(a);
    let (i, j) = (BigInt::from(i), BigInt::from(j));
    if !i.is_multiple_of(&q) || !j.is_multiple_of(&q) {
        return None;
    }
    let s = if c == BigInt::from(1) {
        c
    } else {
        // c >= 3, so s >= 3 and a 41 digit s^p has 0 < p <= 84.
        let k = u32::try_from(&q).ok()?;
        let s = c.nth_root(k);
        if num_traits::pow(s.clone(), k as usize) != c || p.is_negative() || p > BigInt::from(84) {
            return None;
        }
        s
    };
    let x = &i / &q * &p;
    let y = &j / &q * &p;
    let t = x.clone().min(y.clone());
    let (d2, d5) = (&x - &t, &y - &t);
    // 2^137 and 5^59 are past 1e41.
    if d2 > BigInt::from(137) || d5 > BigInt::from(59) {
        return None;
    }
    let p = usize::try_from(&p).unwrap_or(0);
    let m = num_traits::pow(s, p)
        * num_traits::pow(BigInt::from(2), usize::try_from(&d2).unwrap())
        * num_traits::pow(BigInt::from(5), usize::try_from(&d5).unwrap());
    let t = i64::try_from(&t).ok().filter(|t| t.abs() < 1 << 40)?;
    (r::digits(&m) <= 41).then(|| Dec::new(m, t))
}

/// The error of a positive exact g with |log10 g| past RANGE, as every other
/// branch and the Python oracle decide it. With g = m 10^t, m free of
/// trailing zeros, floor(log10 g) is t + digits(m) - 1, and log10 g equals
/// it only for m = 1.
fn past_range(g: &Dec) -> Option<RefError> {
    let n = g.normalized();
    let top = n.e + r::digits(&n.c) as i64 - 1;
    if top > RANGE || (top == RANGE && n.c != BigInt::from(1)) {
        Some(past(true))
    } else if top < -RANGE {
        Some(past(false))
    } else {
        None
    }
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
    if let Some(g) = exact_power(&base, b) {
        return match past_range(&g) {
            Some(e) => Truth::err(e),
            None => Truth::exact(sign(g)),
        };
    }
    match precise::pow_true(&base, b) {
        Err(rising) => Truth::err(past(rising)),
        Ok(t) => Truth::near(Approx {
            value: sign(t.value),
            err: t.err,
        }),
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
    Pow(PowTerm),
    Sqrt,
}

/// pow's N term, N min(K1, K2 d) relative for N the integer part of |b| and
/// d = max(|a|, 1/|a|) - 1, exactly as `num / den`: below one, where K2 d is
/// the lesser, d is (1 - |a|) / |a| and `den` is |a|; otherwise `den` is 1.
#[derive(Debug, Clone)]
pub struct PowTerm {
    num: Dec,
    den: Dec,
}

impl PowTerm {
    pub fn new(a: &Dec, b: &Dec, n: BigInt) -> Self {
        let one = Dec::new(1, 0);
        let none = Self {
            num: Dec::zero(),
            den: one.clone(),
        };
        if n.is_zero() || a.is_zero() {
            return none;
        }
        let n = Dec::new(n, 0);
        let (k1, k2) = if b.is_negative() {
            (POW_INVERSE_K1_E80, POW_INVERSE_K2_E42)
        } else {
            (POW_K1_E80, POW_K2_E42)
        };
        let (k1, k2) = (Dec::new(k1, -80), Dec::new(k2, -42));
        let m = a.abs();
        // Past 1e-100 of one either way K2 d is past K1.
        if order(&m) >= 100 || order(&m) <= -100 {
            return Self {
                num: k1.mul_exact(&n),
                den: one,
            };
        }
        if !m.cmp_value(&one).is_lt() {
            let k2d = k2.mul_exact(&sum(&m, &one.neg()));
            let per = if k2d.cmp_value(&k1).is_lt() { k2d } else { k1 };
            return Self {
                num: per.mul_exact(&n),
                den: one,
            };
        }
        // K2 (1 - |a|) / |a| < K1 iff K2 (1 - |a|) < K1 |a|.
        let k2d = k2.mul_exact(&sum(&one, &m.neg()));
        if k2d.cmp_value(&k1.mul_exact(&m)).is_lt() {
            Self {
                num: k2d.mul_exact(&n),
                den: m,
            }
        } else {
            Self {
                num: k1.mul_exact(&n),
                den: one,
            }
        }
    }

    /// `base` plus the N term, relative, times `den`.
    fn relative(&self, base: Dec) -> Dec {
        sum(&base.mul_exact(&self.den), &self.num)
    }
}

fn sum(a: &Dec, b: &Dec) -> Dec {
    a.add_exact(b)
        .expect("terms within 400 digits of each other")
}

/// x / y for positive x and y, rounded down and up at 10^e.
fn bracket(x: &Dec, y: &Dec, e: i64) -> (Dec, Dec) {
    let shift = x.e - y.e - e;
    let (num, den) = if shift >= 0 {
        (&x.c * pow10(shift as u64), y.c.clone())
    } else {
        (x.c.clone(), &y.c * pow10((-shift) as u64))
    };
    let (q, rem) = num.div_rem(&den);
    let up = if rem.is_zero() { q.clone() } else { &q + 1 };
    (Dec::new(q, e), Dec::new(up, e))
}

fn largest(negative: bool) -> Dec {
    let c = if negative {
        -r::int224_min()
    } else {
        r::int224_max()
    };
    Dec::new(c, I32_MAX)
}

/// The exponent floor's carve-out applies below 1e-2147483608, for `lowest`
/// times `scale`.
fn floor_carve(lowest: &Dec, scale: &Dec) -> Dec {
    if lowest
        .cmp_value(&Dec::new(1, I32_MIN + 40).mul_exact(scale))
        .is_lt()
    {
        Dec::new(1, I32_MIN)
    } else {
        Dec::zero()
    }
}

/// `want` is the revert data of each error from this call.
fn check_sol(
    case: &str,
    sol: Sol,
    truth: &Truth,
    bound: &Bound,
    want: impl Fn(RefError) -> Vec<u8>,
) -> Result<(), TestCaseError> {
    let reverted = |e: RefError| matches!(&sol, Err(s) if *s == want(e));
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
    // `within` is the bound times `scale`, so every side below is scaled.
    let (within, carve, scale) = match bound {
        Bound::Log10 => (sum(&half_unit, &log10_raw()), Dec::zero(), Dec::new(1, 0)),
        Bound::Sqrt => (half_unit, Dec::zero(), Dec::new(1, 0)),
        Bound::Pow10(k) => (pow10_within(*k), Dec::new(1, I32_MIN), Dec::new(1, 0)),
        Bound::Pow(term) => (
            term.relative(pow_base())
                .mul_exact(&sum(&magnitude, &err.neg())),
            Dec::new(1, I32_MIN),
            term.den.clone(),
        ),
    };
    let scaled = |x: &Dec| x.mul_exact(&scale);
    let lowest = sum(&scaled(&sum(&magnitude, &err.neg())), &within.neg());
    let highest = sum(&scaled(&sum(&magnitude, &err)), &within);
    let carve = if carve.is_zero() {
        carve
    } else {
        floor_carve(&lowest, &scale)
    };
    // Only pow10 and pow reach past every Float.
    let ranged = matches!(bound, Bound::Pow10(_) | Bound::Pow(_));
    let least = scaled(&Dec::new(1, I32_MIN));
    let most = scaled(&largest(t.value.is_negative()));
    let below = ranged && lowest.cmp_value(&least).is_lt();
    let above = ranged && highest.cmp_value(&most).is_gt();
    let under = ranged && highest.cmp_value(&least).is_lt();
    let over = ranged && lowest.cmp_value(&most).is_gt();
    match &sol {
        Ok(s) => {
            prop_assert!(
                !under && !over,
                "{case}: solidity {s:?}, true {t:?} is past every Float"
            );
            // (|s - v| + err) scale <= within + carve scale, exactly: within's
            // exponent and the carve-out's are billions apart.
            let side = match Dec::sign_of_sum(&[s.clone(), t.value.neg()]) {
                std::cmp::Ordering::Less => Dec::new(-1, 0),
                _ => Dec::new(1, 0),
            };
            let excess = Dec::sign_of_sum(&[
                scaled(&s.mul_exact(&side)),
                scaled(&t.value.neg().mul_exact(&side)),
                scaled(&err),
                within.neg(),
                scaled(&carve).neg(),
            ]);
            prop_assert!(
                !excess.is_gt(),
                "{case}: solidity {s:?}, true {t:?}, error past {within:?} + {carve:?}, over {scale:?}"
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
    check_sol(&case, sol_log10(a), &truth, &Bound::Log10, |e| {
        revert_data(e, a, None)
    })
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
        |e| revert_data(e, x, None),
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

/// pow's bound, with no N term where the contract is an error.
fn pow_bound(a: &Dec, b: &Dec, truth: &Truth) -> Bound {
    let n = if truth.value.is_ok() {
        integer_part(b)
    } else {
        BigInt::zero()
    };
    Bound::Pow(PowTerm::new(a, b, n))
}

pub fn check_pow(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("pow({}, {})", show(a), show(b));
    let truth = truth_pow(a, b);
    let py = ask(json!({"op": "pow", "a": float_json(a), "b": float_json(b)}));
    check_python(&case, &truth, &py)?;
    let bound = pow_bound(a, b, &truth);
    check_sol(&case, sol_pow(a, b), &truth, &bound, |e| {
        revert_data(e, a, Some(b))
    })
}

pub fn check_sqrt(a: &Dec) -> Result<(), TestCaseError> {
    let case = format!("sqrt({})", show(a));
    let half = Dec::new(5, -1);
    let truth = truth_pow(a, &half);
    let py = ask(json!({"op": "pow", "a": float_json(a), "b": float_json(&half)}));
    check_python(&case, &truth, &py)?;
    check_sol(&case, sol_sqrt(a), &truth, &Bound::Sqrt, |e| {
        revert_data(e, a, None)
    })
}

// ------------------------------------------------------------ monotonicity

/// The raw error before rounding, as proven: the distance from a rounding
/// tie within which two results can come out in the wrong order, times the
/// scale it returns with.
fn raw(bound: &Bound, t: &Approx) -> (Dec, Dec) {
    let one = Dec::new(1, 0);
    match bound {
        Bound::Log10 => (log10_raw(), one),
        Bound::Pow10(k) => (Dec::new(POW10_RAW_E52, k - 52), one),
        Bound::Pow(term) => (
            term.relative(Dec::new(POW_RELATIVE_E52 - POW10_HALF_UNIT_E52, -52))
                .mul_exact(&t.value.abs()),
            term.den.clone(),
        ),
        // Correctly rounded: never out of order, which check_monotone asserts.
        Bound::Sqrt => (Dec::zero(), one),
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
    let raws = [raw(&lower.bound, ta), raw(&upper.bound, tb)];
    // Within the larger of the two: within either.
    let within = |off: &Dec| {
        raws.iter()
            .any(|(r, scale)| !off.mul_exact(scale).cmp_value(r).is_gt())
    };
    for t in [ta, tb] {
        let off = sum(&sum(&t.value, &tie.neg()).abs(), &t.err_dec().neg());
        prop_assert!(
            within(&off),
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
    Point {
        sol: sol_pow(a, b),
        bound: pow_bound(a, b, &truth),
        truth,
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
/// below. a > 0 only: for a < 0 the sign of a^b flips with the parity of b,
/// so neighbouring b are not ordered.
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

pub(crate) fn x_pow10() -> BoxedStrategy<Dec> {
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

pub(crate) fn a_log10() -> BoxedStrategy<Dec> {
    prop_oneof![
        4 => float(),
        // Powers of ten, the exact anchors, in every representation.
        1 => (0u64..=66, crate::exact::exponent()).prop_map(|(j, e)| Dec::new(pow10(j), e)),
        // Within 1000 units of a power of ten.
        2 => (0u64..=66, -1000i64..=1000, crate::exact::exponent()).prop_map(|(j, d, e)| Dec::new(pow10(j) + d, e)),
    ]
    .boxed()
}

/// A positive a with any coefficient and any exponent.
fn moderate() -> BoxedStrategy<Dec> {
    (crate::exact::coefficient(), crate::exact::exponent())
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
        1 => float(),
    ]
    .boxed()
}

/// n + 1/2 in any representation, either sign, which `pow` takes as the root
/// of a^(2n + 1).
fn half_b() -> BoxedStrategy<Dec> {
    (-400i64..=400, 0u64..=60)
        .prop_map(|(n, j)| Dec::new(BigInt::from(2 * n + 1) * 5 * pow10(j), -(j as i64) - 1))
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

/// r^q and p/q for r = g 10^e, whose power is exactly r^p, for every q
/// dividing a power of ten that some g > 1 has a q-th power inside int224.
/// Past q 223 only a power of ten has a q-th root.
fn rational_power() -> BoxedStrategy<(Dec, Dec)> {
    (
        prop::sample::select(vec![
            2u32, 4, 5, 8, 10, 16, 20, 25, 32, 40, 50, 64, 80, 100, 125, 128, 160, 200,
        ]),
        2u64..=1000,
        prop_oneof![-3i64..=3, -10_000_000i64..=10_000_000],
        (-100i64..=100).prop_filter("p", |p| *p != 0),
    )
        .prop_filter_map("g^q and e q fit", |(q, g, e, p)| {
            let a = power(&Dec::new(g, e), q);
            let n = (0..=8).find(|n| (pow10(*n) % q).is_zero())?;
            (r::fits_int224(&a.c) && a.e.abs() <= I32_MAX)
                .then(|| (a, Dec::new(BigInt::from(p) * pow10(n) / q, -(n as i64))))
        })
        .boxed()
}

pub(crate) fn pow_pair() -> BoxedStrategy<(Dec, Dec)> {
    prop_oneof![
        2 => (float(), float()),
        4 => (moderate(), small_b()),
        2 => (moderate(), half_b()),
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
        3 => rational_power(),
    ]
    .boxed()
}

/// a within 1e-66 to 1.9e-19 of one, either side, and b of either sign with
/// |b| d near 10^s for d = |a - 1| and s in [-4, 10]: |b| reaches past
/// 1e75, where pow's N term is K2 N d, and the power runs from near one to
/// past every Float.
pub(crate) fn near_one() -> BoxedStrategy<(Dec, Dec)> {
    (
        38u64..=66,
        any::<u64>(),
        any::<bool>(),
        1u64..=67,
        any::<[u8; 32]>(),
        -4i64..=10,
        any::<bool>(),
    )
        .prop_map(|(j, k, below, n, bytes, s, negative)| {
            let k = BigInt::from(k.max(1));
            let c = if below { pow10(j) - &k } else { pow10(j) + &k };
            let a = Dec::new(c, -(j as i64));
            let lo = pow10(n - 1);
            let c = &lo + BigInt::from_bytes_be(num_bigint::Sign::Plus, &bytes) % (pow10(n) - &lo);
            // d is k 10^-j, so |b| d is near 10^s.
            let e = s + j as i64 - (r::digits(&k) as i64 - 1) - (n as i64 - 1);
            (a, Dec::new(if negative { -c } else { c }, e))
        })
        .boxed()
}

pub(crate) fn a_sqrt() -> BoxedStrategy<Dec> {
    prop_oneof![
        3 => float(),
        // Perfect squares of up to 33 digits, whose root is exact.
        2 => (1u32..=33, I32_MIN / 2..=I32_MAX / 2).prop_flat_map(|(n, e)| {
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
    fn monotone_pow_half_neighbours((a, b) in (moderate(), half_b())) { monotone_pow(&a, &b)?; }

    #[test]
    fn monotone_sqrt_neighbours(a in a_sqrt()) { monotone_sqrt(&a)?; }

    #[test]
    fn exact_pow_near_one((a, b) in near_one()) { check_pow(&a, &b)?; }

    #[test]
    fn monotone_pow_near_one((a, b) in near_one()) { monotone_pow(&a, &b)?; }
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

    /// The input of every made-up call.
    fn input() -> Dec {
        Dec::new(-3, -1)
    }

    /// The revert data of `e` from a made-up call.
    fn reverting(e: RefError) -> Sol {
        Err(revert_data(e, &input(), None))
    }

    fn accepts(truth: &Truth, bound: &Bound, sol: Sol) -> bool {
        check_sol("checker", sol, truth, bound, |e| {
            revert_data(e, &input(), None)
        })
        .is_ok()
    }

    /// `v + within - err` is the furthest result the bound admits, and a
    /// step of `step` further is past it.
    fn edge(v: &Dec, bound: &Bound, within: &Dec, step: &Dec) {
        edge_between(v, bound, within, within, step);
    }

    /// `edge` for a bound in [down, up], each side apart.
    fn edge_between(v: &Dec, bound: &Bound, down: &Dec, up: &Dec, step: &Dec) {
        let truth = near(v.clone());
        let err = Dec::new(1, order(v) - 300);
        let at = sum(&sum(v, down), &err.neg());
        assert!(accepts(&truth, bound, Ok(at.clone())), "{at:?} for {v:?}");
        let past = sum(&sum(&sum(v, up), &err.neg()), step);
        assert!(
            !accepts(&truth, bound, Ok(past.clone())),
            "{past:?} for {v:?}"
        );
        let low = sum(&sum(v, &down.neg()), &err);
        assert!(accepts(&truth, bound, Ok(low.clone())), "{low:?} for {v:?}");
        let below = sum(&sum(&sum(v, &up.neg()), &err), &step.neg());
        assert!(
            !accepts(&truth, bound, Ok(below.clone())),
            "{below:?} for {v:?}"
        );
    }

    #[test]
    fn log10_bound() {
        // Half a unit in the 41st digit of 2, plus 1.0037e-50.
        let within = sum(&Dec::new(5, -41), &log10_raw());
        edge(&Dec::new(2, 0), &Bound::Log10, &within, &Dec::new(1, -310));
        // A true value that may be just below one takes the 41st digit there.
        let within = sum(&Dec::new(5, -42), &log10_raw());
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
        let under = || -> Sol { reverting(RefError::ExponentUnderflow) };
        assert!(!accepts(&near(Dec::new(1, I32_MIN)), &Bound::Sqrt, under()));
    }

    #[test]
    fn pow10_bound() {
        // 3.5 has integer part 0: half a unit plus 1.1111e-8 of one, 1e-40.
        let within = pow10_within(0);
        edge(
            &Dec::new(35, -1),
            &Bound::Pow10(0),
            &within,
            &Dec::new(1, -310),
        );
    }

    /// pow's bound with no N term.
    fn pow_zero() -> Bound {
        Bound::Pow(PowTerm::new(
            &Dec::new(2, 0),
            &Dec::new(1, 0),
            BigInt::zero(),
        ))
    }

    /// pow's bound for N `n`, the integer part of |b|.
    fn pow_n(a: &Dec, b: &Dec, n: impl Into<BigInt>) -> Bound {
        Bound::Pow(PowTerm::new(a, b, n.into()))
    }

    #[test]
    fn pow_bound() {
        let v = Dec::new(2, 0);
        let one = Dec::new(1, 0);
        for (a, b, n, term) in [
            // N 7 with d 1: K1, 7 1.7273e-76 for b > 0 and 7 1.1728e-75 for
            // b < 0.
            (Dec::new(2, 0), one.clone(), 7, Dec::new(7 * 17273, -80)),
            (Dec::new(2, 0), one.neg(), 7, Dec::new(7 * 11728, -79)),
            // 1/a has the same d.
            (Dec::new(5, -1), one.neg(), 7, Dec::new(7 * 11728, -79)),
            // d 1e-66: K2 d, 7 1.5e-104 and 7 3.4786e-104.
            (
                Dec::new(pow10(66) + 1, -66),
                one.clone(),
                7,
                Dec::new(105, -105),
            ),
            (
                Dec::new(pow10(66) + 1, -66),
                one.neg(),
                7,
                Dec::new(7 * 34786, -108),
            ),
            // Either side of K1 = K2 d for b > 0, at d 1.15153e-38.
            (
                Dec::new(pow10(43) + 115153, -43),
                one.clone(),
                7,
                Dec::new(7 * 1727295, -82),
            ),
            (
                Dec::new(pow10(43) + 115154, -43),
                one.clone(),
                7,
                Dec::new(7 * 17273, -80),
            ),
        ] {
            let relative = sum(&pow_base(), &term);
            let within = relative.mul_exact(&sum(&v, &Dec::new(-1, -300)));
            // Past 400 digits apart the checker's sums do not align, so the
            // bound is taken to 1e-350, far inside the step.
            let (down, up) = bracket(&within, &one, -350);
            edge_between(&v, &pow_n(&a, &b, n), &down, &up, &Dec::new(1, -310));
        }
    }

    /// Below one d is (1 - |a|) / |a|, which no decimal holds: the bound
    /// admits a result at it rounded down at 1e-350, and none a step past it
    /// rounded up.
    #[test]
    fn pow_bound_below_one() {
        let v = Dec::new(2, 0);
        let a = Dec::new(pow10(50) - 1, -50);
        let b = Dec::new(pow10(40), 0);
        // (5.00000011343e-41 a + 1.5e-38 1e40 1e-50) (v - err) / a.
        let x = sum(&pow_base().mul_exact(&a), &Dec::new(15, -49))
            .mul_exact(&sum(&v, &Dec::new(-1, -300)));
        let (down, up) = bracket(&x, &a, -350);
        edge_between(
            &v,
            &pow_n(&a, &b, pow10(40)),
            &down,
            &up,
            &Dec::new(1, -310),
        );
    }

    /// N 3.3e74 for b < 0 and d past K1 / K2 puts the relative bound past one,
    /// so it reaches below every Float and takes the carve-out,
    /// 1e-2147483648, billions of digits below the bound itself.
    #[test]
    fn pow_bound_past_one() {
        let v = Dec::new(31, 145_000_000);
        let n = BigInt::from(33333347515073147437056u128) * pow10(52);
        let relative = Dec::new(
            BigInt::from(POW_RELATIVE_E52) * pow10(28) + &n * POW_INVERSE_K1_E80,
            -80,
        );
        let within = relative.mul_exact(&sum(&v, &Dec::new(-1, order(&v) - 300)));
        let bound = pow_n(&Dec::new(10, 0), &Dec::new(-1, 0), n);
        edge(&v, &bound, &within, &Dec::new(1, order(&v) - 310));
    }

    /// At or above 1e-2147483608 the bound has no carve-out; below it, it adds
    /// 1e-2147483648.
    #[test]
    fn floor_carve_out() {
        let k = -2147483608;
        let within = pow10_within(k);
        let step = Dec::new(1, I32_MIN - 12);
        edge(&Dec::new(5, k), &Bound::Pow10(k), &within, &step);
        let k = -2147483620;
        let within = sum(&pow10_within(k), &Dec::new(1, I32_MIN));
        edge(&Dec::new(5, k), &Bound::Pow10(k), &within, &step);
    }

    /// A revert is accepted only where the bound reaches past every Float.
    #[test]
    fn reverts() {
        let under = || -> Sol { reverting(RefError::ExponentUnderflow) };
        let over = || -> Sol { reverting(RefError::ExponentOverflow) };
        let ordinary = near(Dec::new(5, -100));
        assert!(!accepts(&ordinary, &pow_zero(), under()));
        assert!(!accepts(&ordinary, &pow_zero(), over()));
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

    /// An exact power one unit in the last place off is within pow's bound,
    /// so only exactness rejects it, for every q and every count of decimals.
    #[test]
    fn pow_exact_past_small_ratios() {
        for (a, b, want) in [
            ("42535295865117307932921825928971026432", "0.008", "2"),
            ("42535295865117307932921825928971026432", "-0.008", "0.5"),
            (
                "42535295865117307932921825928971026432",
                "1.056",
                "5444517870735015415413993718908291383296",
            ),
            (
                "11790184577738583171520872861412518665678211592275841109096961",
                "0.0078125",
                "3",
            ),
            ("1267650600228229401496703205376e-1000", "0.01", "2e-10"),
        ] {
            let (a, b, want) = (
                r::literal_value(a),
                r::literal_value(b),
                r::literal_value(want),
            );
            let bound = pow_n(&a, &b, integer_part(&b));
            let ulp = Dec::new(1, order(&want) - 40);
            let off = sum(&want, &ulp.neg());
            assert!(
                accepts(&near(want.clone()), &bound, Ok(off.clone())),
                "{off:?}"
            );
            assert!(
                !accepts(&truth_pow(&a, &b), &bound, Ok(off.clone())),
                "{off:?}"
            );
            assert!(accepts(&truth_pow(&a, &b), &bound, Ok(want)));
        }
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
            reverting(RefError::ExponentOverflow)
        ));
        assert!(!accepts(
            &past,
            &Bound::Pow10(0),
            reverting(RefError::ExponentUnderflow)
        ));
        let gone = Truth::exact(Dec::new(1, I32_MIN - 1));
        assert!(accepts(
            &gone,
            &Bound::Pow10(0),
            reverting(RefError::ExponentUnderflow)
        ));
        assert!(!accepts(
            &gone,
            &Bound::Pow10(0),
            reverting(RefError::ExponentOverflow)
        ));
        let e = Truth::err(RefError::Log10Zero);
        assert!(accepts(&e, &Bound::Log10, reverting(RefError::Log10Zero)));
        assert!(!accepts(
            &e,
            &Bound::Log10,
            reverting(RefError::Log10Negative)
        ));
        assert!(!accepts(&e, &Bound::Log10, Ok(Dec::zero())));
    }

    /// A revert is accepted only with the call's input as its arguments.
    #[test]
    fn revert_args() {
        let past = Truth::exact(Dec::new(1, I32_MAX + 68));
        let over = RefError::ExponentOverflow;
        let bare = Err(over.selector().to_vec());
        assert!(!accepts(&past, &Bound::Pow10(0), bare));
        let other = Err(revert_data(over, &Dec::new(-3, 0), None));
        assert!(!accepts(&past, &Bound::Pow10(0), other));
        let e = Truth::err(RefError::Log10Negative);
        let bare = Err(RefError::Log10Negative.selector().to_vec());
        assert!(!accepts(&e, &Bound::Log10, bare));
        let other = Err(revert_data(
            RefError::Log10Negative,
            &Dec::new(-3, -2),
            None,
        ));
        assert!(!accepts(&e, &Bound::Log10, other));
        assert!(accepts(
            &e,
            &Bound::Log10,
            reverting(RefError::Log10Negative)
        ));
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
            (Bound::Log10, log10_raw()),
            (Bound::Pow10(0), Dec::new(POW10_RAW_E52, -52)),
            (Bound::Pow10(3), Dec::new(POW10_RAW_E52, -49)),
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
        // pow: 3.3006e-48 relative to the larger true value, the lower point's.
        let tie = Dec::new(BigInt::from(2) * pow10(40) + 1, -40).mul_exact(&Dec::new(5, -1));
        let raw = Dec::new(POW_RELATIVE_E52 - POW10_HALF_UNIT_E52, -52);
        let pow = |d: &Dec| {
            let hi = Dec::new(BigInt::from(1) * pow10(40) + 1, -40);
            check_monotone(
                "m",
                point(hi, tie.clone(), pow_zero()),
                point(Dec::new(1, 0), sum(&tie, &d.neg()), pow_zero()),
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

    /// a^b is exact only for a rational power with at most 41 digits.
    #[test]
    fn exact_power_is_rational_and_short() {
        for (a, b, want) in [
            ("2", "0.5", None),
            ("3", "-1", None),
            ("6", "-1", None),
            ("16", "-0.0000025", None),
            ("2", "137", None),
            (
                "2",
                "136",
                Some("87112285931760246646623899502532662132736"),
            ),
            ("2", "-136", None),
            ("2", "-40", Some("9094947017729282379150390625e-40")),
            ("0.04", "0.5", Some("0.2")),
            ("0.04", "-1.5", Some("125")),
            ("1e-10", "0.2", Some("0.01")),
            ("8e30", "0.3333333", None),
            ("1e3", "1e-50", None),
            ("7", "1e13", None),
        ] {
            let got = exact_power(&d(a), &d(b));
            match want {
                None => assert!(got.is_none(), "{a}^{b}: {got:?}"),
                Some(w) => assert!(
                    got.as_ref().is_some_and(|g| g.eq_value(&d(w))),
                    "{a}^{b}: {got:?}, want {w}"
                ),
            }
        }
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
            // q past 64, or b past 6 decimals.
            ("42535295865117307932921825928971026432", "0.008", "2"),
            ("42535295865117307932921825928971026432", "-0.008", "0.5"),
            (
                "42535295865117307932921825928971026432",
                "1.056",
                "5444517870735015415413993718908291383296",
            ),
            (
                "11790184577738583171520872861412518665678211592275841109096961",
                "0.0078125",
                "3",
            ),
            ("1267650600228229401496703205376e-1000", "0.01", "2e-10"),
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
            // Exact powers past RANGE.
            ("-9e-750000001", "4", RefError::ExponentUnderflow),
            ("9e750000001", "4", RefError::ExponentOverflow),
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

    /// A half power is the root of a^(2N+1) rounded at 41 digits, so it
    /// overflows exactly when that rounding is at least the least overflowing
    /// value, (int224.max / 10 + 1) 10^(int32.max + 1). Here a^1.5 is
    /// sqrt(10 c^3) 10^2147483614, with floor(sqrt(10 c^3)) and one above it
    /// rounding alike, past that value.
    #[test]
    fn pow_half_root_past_the_threshold() {
        let c: BigInt = "2629012728145285679841056168393364475926807479622600963406791093691"
            .parse()
            .unwrap();
        let a = Dec::new(c.clone(), 1431655743);
        let b = Dec::new(15, -1);
        let cube: BigInt = num_traits::pow(c, 3);
        let s = (cube * BigInt::from(10)).sqrt();
        let rounded = round41(&Dec::new(s.clone(), 2147483614));
        assert!(rounded.eq_value(&round41(&Dec::new(s + 1, 2147483614))));
        let least = Dec::new(r::int224_max() / 10 + 1, I32_MAX + 1);
        assert!(!rounded.cmp_value(&least).is_lt(), "{rounded:?}");
        assert_eq!(
            sol_pow(&a, &b).err(),
            Some(revert_data(RefError::ExponentOverflow, &a, Some(&b)))
        );
    }

    /// b past 6 decimals with a large integer part, against `bc -l`, to 45
    /// digits:
    /// - (1 + 1e-20)^(1e20 + 1e-7) is
    ///   2.71828182845904523534669606492864910003961548, at scale 300.
    /// - 1.002^(2e12 + 1e-7) is
    ///   2.84331506279111009690174079886358388810420809 10^1735443062, the
    ///   same at scales 150 and 250. Its log10 is past 1e9, so b times log10's
    ///   1.0037e-50 absolute error would leave the bound: the integer part has to
    ///   be taken by squaring.
    #[test]
    fn pow_integer_part_past_six_decimals() {
        let digits = |s: &str| s.parse::<BigInt>().unwrap();
        for (a, b, bc) in [
            (
                Dec::new(pow10(20) + 1, -20),
                Dec::new(pow10(27) + 1, -7),
                Dec::new(digits("271828182845904523534669606492864910003961548"), -44),
            ),
            (
                Dec::new(1002, -3),
                Dec::new(2 * pow10(19) + 1, -7),
                Dec::new(
                    digits("284331506279111009690174079886358388810420809"),
                    1735443062 - 44,
                ),
            ),
        ] {
            let t = truth_pow(&a, &b);
            let v = &t.value.as_ref().unwrap().value;
            let gap = v.add_exact(&bc.neg()).unwrap().abs();
            assert!(gap.cmp_value(&Dec::new(1, bc.e)).is_lt(), "{t:?}");
            run(check_pow(&a, &b));
        }
    }

    /// (1 + 1e-66)^~3.3e74 is about 10^1.45e8: N d is 3.3e8, so the N term
    /// is K2 N d, 5e-30.
    #[test]
    fn pow_near_one_past_1e74() {
        let a = Dec::new(pow10(66) + 1, -66);
        let b = Dec::new("33333347515073147437056".parse::<BigInt>().unwrap(), 52);
        run(check_pow(&a, &b));
    }

    /// pow(a, b)'s error over its N term, after `check_pow` holds it to the
    /// bound.
    fn n_term_ratio(a: &Dec, b: &Dec) -> f64 {
        run(check_pow(a, b));
        let t = truth_pow(a, b).value.unwrap();
        let s = sol_pow(a, b).unwrap();
        eprintln!("pow({}, {}): {s:?} against {t:?}", show(a), show(b));
        let PowTerm { num, den } = PowTerm::new(a, b, integer_part(b));
        let x = sum(&s, &t.value.neg()).abs().mul_exact(&den);
        let y = num.mul_exact(&t.value.abs());
        let (q, _) = bracket(&x, &y, -20);
        format!("{}e-20", q.c).parse().unwrap()
    }

    /// The error is at least 0.9 of the N term, net of the reference's own:
    /// (|s - t| - err) den >= 0.9 num |t|.
    fn assert_tight(a: &Dec, b: &Dec) {
        let t = truth_pow(a, b).value.unwrap();
        let s = sol_pow(a, b).unwrap();
        let PowTerm { num, den } = PowTerm::new(a, b, integer_part(b));
        let error = sum(&sum(&s, &t.value.neg()).abs(), &t.err_dec().neg());
        let least = Dec::new(9, -1).mul_exact(&num).mul_exact(&t.value.abs());
        assert!(
            !Dec::sign_of_sum(&[error.mul_exact(&den), least.neg()]).is_lt(),
            "pow({}, {}): {s:?} against {t:?}",
            show(a),
            show(b)
        );
    }

    /// The issue's case, (1 + 1e-66)^1e67: N d is 10 and the N term K2 N d,
    /// 1.5e-37, and the error 1.373e-37. For b = -1e67 the N term is
    /// 3.4786e-37.
    #[test]
    fn pow_near_one_issue() {
        let a = Dec::new(pow10(66) + 1, -66);
        let b = Dec::new(1, 67);
        eprintln!("issue b > 0: {}", n_term_ratio(&a, &b));
        assert_tight(&a, &b);
        eprintln!("issue b < 0: {}", n_term_ratio(&a, &b.neg()));
    }

    /// The model's worst case for b < 0: d 3.15e-38, near sqrt(1e-75), where
    /// the squarings and the inverse together drop the most per N d.
    #[test]
    fn pow_near_one_worst() {
        let a = r::literal_value("999999999999999999999999999999999999968486793427e-48");
        let b = r::literal_value("-2077793387360115167471691320350296608394");
        eprintln!("worst: {}", n_term_ratio(&a, &b));
        assert_tight(&a, &b);
    }

    /// b < 0 where K1 is the lesser, d 1.23e-31: the inverse of a drops 0.84
    /// of a unit at 1e-75, which a^-N weighs N.
    #[test]
    fn pow_near_one_inverse_k1() {
        let a =
            r::literal_value("9999999999999999999999999999998765432109876543210987654321099e-61");
        let b = Dec::new(-1, 40);
        eprintln!("inverse k1: {}", n_term_ratio(&a, &b));
    }
}
