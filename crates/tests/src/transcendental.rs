//! log10, pow10, pow and sqrt, over the full Float domain, against the true
//! value from two independent references: astro-float (`precise.rs`) and the
//! Python `decimal` oracle. Each result must be within the bound the library
//! proves (README "log10, pow10, pow and sqrt", and the NatSpec), with no
//! tolerance added; an exact result must be exact; an error must be the one
//! error the documented contract gives.
//!
//! The bounds, as documented:
//! - pow10: half a unit in the 41st digit plus 5.1662e-6 of a unit.
//! - log10: half a unit in the 41st digit plus 2.245e-47 absolute.
//! - pow: 5.00006e-41 + 3N 1e-75 relative, N the integer part of |b|.
//! - sqrt: 5.00006e-41 relative.
//! - pow10 and pow: a result below 1e-2147483608 adds 1e-2147483648.

use crate::exact::{config, float, show};
use crate::oracle::{self, ask};
use crate::precise::{self, Approx, RANGE, order};
use crate::reference::{self as r, Dec, I32_MAX, I32_MIN, Packed, RefError, pow10};
use alloy::primitives::{Address, B256, Bytes, address};
use alloy::sol_types::SolCall;
use num_bigint::BigInt;
use num_integer::Integer;
use num_traits::{One, Signed, Zero};
use proptest::prelude::*;
use proptest::test_runner::TestCaseError;
use revm::context::result::{ExecutionResult, Output, SuccessReason};
use revm::context::{BlockEnv, CfgEnv, TxEnv};
use revm::database::InMemoryDB;
use revm::state::{AccountInfo, Bytecode};
use revm::{Context, DatabaseCommit, MainBuilder, MainContext, MainnetEvm, SystemCallEvm};
use serde_json::{Value, json};
use std::cell::RefCell;

// ----------------------------------------------------------------- the EVM

alloy::sol! {
    interface Transcendental {
        function pow10(bytes32 a) external view returns (bytes32);
        function log10(bytes32 a) external view returns (bytes32);
        function pow(bytes32 a, bytes32 b) external view returns (bytes32);
        function sqrt(bytes32 a) external view returns (bytes32);
    }
}

const CONCRETE: Address = address!("00000000000000000000000000000000000f10a4");

type Evm = MainnetEvm<Context<BlockEnv, TxEnv, CfgEnv, InMemoryDB>>;

fn put(db: &mut InMemoryDB, code: Bytes) {
    db.insert_account_info(
        CONCRETE,
        AccountInfo::default().with_code(Bytecode::new_legacy(code)),
    );
}

/// `TestDecimalFloat` compiled from this source, constructed so that it
/// deploys its log tables, as the bindings do with `create`.
fn build() -> Evm {
    let path = std::env::var("RAIN_MATH_FLOAT_ARTIFACT").expect(".cargo/config.toml sets it");
    let json: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
    let creation: Bytes = json["bytecode"]["object"].as_str().unwrap().parse().unwrap();
    let mut db = InMemoryDB::default();
    put(&mut db, creation);
    let mut evm = Context::mainnet().with_db(db.clone()).build_mainnet();
    let created = evm.system_call(CONCRETE, Bytes::new()).unwrap();
    let ExecutionResult::Success {
        output: Output::Call(runtime),
        ..
    } = created.result
    else {
        panic!("constructor: {:?}", created.result);
    };
    db.commit(created.state);
    put(&mut db, runtime);
    Context::mainnet().with_db(db).build_mainnet()
}

thread_local! {
    static EVM: RefCell<Evm> = RefCell::new(build());
}

/// A result, or the selector of the error it reverted with.
type Sol = Result<Dec, [u8; 4]>;

fn call<C: SolCall<Return = B256>>(c: C) -> Sol {
    let result = EVM.with(|evm| {
        evm.borrow_mut()
            .system_call(CONCRETE, c.abi_encode().into())
            .unwrap()
            .result
    });
    match result {
        ExecutionResult::Success {
            reason: SuccessReason::Return,
            output: Output::Call(out),
            ..
        } => Ok(Dec::from_float(rain_math_float::Float::from_raw(
            C::abi_decode_returns(&out).unwrap(),
        ))),
        ExecutionResult::Revert { output, .. } if output.len() >= 4 => {
            Err(output[..4].try_into().unwrap())
        }
        other => panic!("{other:?}"),
    }
}

fn bytes(a: &Dec) -> B256 {
    a.to_float().get_inner()
}

fn sol_log10(a: &Dec) -> Sol {
    call(Transcendental::log10Call { a: bytes(a) })
}

fn sol_pow10(a: &Dec) -> Sol {
    call(Transcendental::pow10Call { a: bytes(a) })
}

fn sol_pow(a: &Dec, b: &Dec) -> Sol {
    call(Transcendental::powCall {
        a: bytes(a),
        b: bytes(b),
    })
}

fn sol_sqrt(a: &Dec) -> Sol {
    call(Transcendental::sqrtCall { a: bytes(a) })
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
    if r::digits(&a.c) as u64 * p.magnitude().to_u64_digits().first().copied().unwrap_or(0) > 20_000 {
        return None;
    }
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
}

fn sum(a: &Dec, b: &Dec) -> Dec {
    a.add_exact(b).expect("terms within 400 digits of each other")
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
    let reverted = |e: RefError| sol == Err(e.selector());
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
                prop_assert!(reverted(RefError::ExponentOverflow), "{case}: solidity {sol:?}, want overflow");
                return Ok(());
            }
            Packed::Underflow => {
                prop_assert!(reverted(RefError::ExponentUnderflow), "{case}: solidity {sol:?}, want underflow");
                return Ok(());
            }
            // Shed at the exponent floor: the bound, with its carve-out.
            Packed::Value(_, false) => {}
        }
    }
    let err = t.err_dec();
    let magnitude = t.value.abs();
    let (within, carve) = match bound {
        Bound::Log10 => {
            // The unit of the true value's 41st digit, the smaller one if the
            // reference's error straddles a power of ten.
            let lowest = sum(&magnitude, &err.neg());
            let half_unit = Dec::new(5, order(&lowest) - 41);
            (sum(&half_unit, &Dec::new(2245, -50)), Dec::zero())
        }
        Bound::Pow10(k) => (Dec::new(5_000_051_662i64, k - 50), Dec::new(1, I32_MIN)),
        Bound::Pow(n) => {
            let relative = Dec::new(BigInt::from(500_006) * pow10(29) + n * 3, -75);
            (relative.mul_exact(&sum(&magnitude, &err.neg())), Dec::new(1, I32_MIN))
        }
    };
    let lowest = sum(&sum(&magnitude, &err.neg()), &within.neg());
    let highest = sum(&sum(&magnitude, &err), &within);
    let carve = if carve.is_zero() { carve } else { floor_carve(&lowest) };
    let below = matches!(bound, Bound::Log10).then_some(false).unwrap_or_else(|| lowest.cmp_value(&Dec::new(1, I32_MIN)).is_lt());
    let above = !matches!(bound, Bound::Log10) && highest.cmp_value(&largest(t.value.is_negative())).is_gt();
    let under = !matches!(bound, Bound::Log10) && highest.cmp_value(&Dec::new(1, I32_MIN)).is_lt();
    let over = !matches!(bound, Bound::Log10) && lowest.cmp_value(&largest(t.value.is_negative())).is_gt();
    match &sol {
        Ok(s) => {
            prop_assert!(!under && !over, "{case}: solidity {s:?}, true {t:?} is past every Float");
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
    check_python(&case, &truth, &ask(json!({"op": "log10", "a": float_json(a)})))?;
    check_sol(&case, sol_log10(a), &truth, &Bound::Log10)
}

pub fn check_pow10(x: &Dec) -> Result<(), TestCaseError> {
    let case = format!("pow10({})", show(x));
    let truth = truth_pow10(x);
    check_python(&case, &truth, &ask(json!({"op": "pow10", "a": float_json(x)})))?;
    let k = r::floor(x).ok().and_then(|f| i64::try_from(&(&f.c * pow10(f.e.max(0) as u64))).ok());
    check_sol(&case, sol_pow10(x), &truth, &Bound::Pow10(k.unwrap_or(0)))
}

fn integer_part(b: &Dec) -> BigInt {
    let t = b.abs().trunc();
    &t.c * pow10(t.e.max(0) as u64)
}

pub fn check_pow(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let case = format!("pow({}, {})", show(a), show(b));
    let truth = truth_pow(a, b);
    let py = ask(json!({"op": "pow", "a": float_json(a), "b": float_json(b)}));
    check_python(&case, &truth, &py)?;
    let n = if truth.value.is_ok() { integer_part(b) } else { BigInt::zero() };
    check_sol(&case, sol_pow(a, b), &truth, &Bound::Pow(n))
}

pub fn check_sqrt(a: &Dec) -> Result<(), TestCaseError> {
    let case = format!("sqrt({})", show(a));
    let half = Dec::new(5, -1);
    let truth = truth_pow(a, &half);
    let py = ask(json!({"op": "pow", "a": float_json(a), "b": float_json(&half)}));
    check_python(&case, &truth, &py)?;
    check_sol(&case, sol_sqrt(a), &truth, &Bound::Pow(BigInt::zero()))
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
            digits_below(n).prop_map(move |f| Dec::new(BigInt::from(k) * pow10(n as u64) + f, -(n as i64)))
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

/// g^k and 1/k, whose power is exactly g.
fn root_anchor() -> BoxedStrategy<(Dec, Dec)> {
    (
        1u64..=100_000_000,
        -5i64..=5,
        prop_oneof![Just(2u32), Just(4), Just(5), Just(8), Just(10), Just(16), Just(20), Just(25)],
    )
        .prop_filter_map("int224", |(g, e, k)| {
            let a = power(&Dec::new(g, e), k);
            let inv = Dec::new(BigInt::from(10u64.pow(4) / k as u64), -4);
            r::fits_int224(&a.c).then_some((a, inv))
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
        // Perfect squares, whose root is exact.
        2 => (crate::exact::coefficient(), -1_000_000_000i64..=1_000_000_000).prop_filter_map("33 digits", |(c, e)| {
            (r::digits(&c) <= 33).then(|| Dec::new(&c * &c, 2 * e))
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
        for k in ["0", "1", "-1", "41", "-2147483648", "2147483647", "2147483713"] {
            exactly(truth_pow10(&d(k)), &format!("1e{k}"));
            run(check_pow10(&d(k)));
        }
        run(check_pow10(&Dec::new(20, -1)));
        // Past the ceiling with 68 digits, and below the floor.
        run(check_pow10(&d("2147483714")));
        run(check_pow10(&d("-2147483649")));
        assert!(matches!(truth_pow10(&d("-2147483649")).exact, Some(_)));
    }

    #[test]
    fn log10_of_a_power_of_ten_is_exact() {
        for (a, k) in [("1", "0"), ("1000", "3"), ("0.001", "-3"), ("1e-2147483648", "-2147483648"), ("1e2147483647", "2147483647")] {
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
            ("7", "0", "1"),
            ("1", "1e100", "1"),
        ] {
            exactly(truth_pow(&d(a), &d(b)), want);
            run(check_pow(&d(a), &d(b)));
        }
        exactly(truth_pow(&d("152415787532388367501905199875019052100"), &d("0.5")), "12345678901234567890");
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

    #[test]
    fn errors() {
        for (a, b, e) in [
            ("0", "-1", RefError::ZeroNegativePower),
            ("-2", "0.5", RefError::PowNegativeBase),
            ("2", "1e100", RefError::ExponentOverflow),
            ("2", "-1e100", RefError::ExponentUnderflow),
            ("0.5", "1e100", RefError::ExponentUnderflow),
            ("10", "2147483714", RefError::ExponentOverflow),
        ] {
            assert!(matches!(truth_pow(&d(a), &d(b)).value, Err(x) if x == e), "{a}^{b}");
            run(check_pow(&d(a), &d(b)));
        }
        assert!(matches!(truth_log10(&d("0")).value, Err(RefError::Log10Zero)));
        assert!(matches!(truth_log10(&d("-1")).value, Err(RefError::Log10Negative)));
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
