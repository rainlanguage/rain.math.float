//! Differential fuzz of the Solidity against dashu-float (#439), an
//! arbitrary precision decimal library this repo did not write, configured to
//! the documented rules. No expected value here comes from `reference.rs`,
//! `LibExactFloat` or the Python oracle: the inputs and the Solidity calls are
//! shared with `exact.rs`, every value the Solidity is checked against is
//! computed by dashu.

use crate::evm::{self, TestDecimalFloat as T, TestDecimalFloatHarness as H};
use crate::exact::{self, Fail, Sol, config, error_matches, pair, show};
use crate::reference::{Dec, RefError};
use crate::transcendental::revert_data;
use alloy::primitives::{B256, U256};
use core::cmp::Ordering;
use dashu_float::round::mode::Zero;
use dashu_float::{Context, FBig};
use dashu_base::Abs;
use dashu_int::IBig;
use proptest::prelude::*;
use proptest::test_runner::TestCaseError;

/// Every value is a base 10 dashu float. Rounding, where an operation rounds,
/// is toward zero.
pub(crate) type D = FBig<Zero, 10>;

/// Digits kept by a rounded dashu operation: past the 68 a Float can hold and
/// the 70-exponent window `toward_zero` reads, so truncating here and then to
/// the Float grid is one truncation of the exact value.
const P: usize = 90;

const I32_MIN: isize = i32::MIN as isize;
const I32_MAX: isize = i32::MAX as isize;

fn ctx() -> Context<Zero> {
    Context::new(P)
}

fn ibig(c: &num_bigint::BigInt) -> IBig {
    c.to_string().parse().unwrap()
}

pub(crate) fn d(x: &Dec) -> D {
    D::from_parts(ibig(&x.c), x.e as isize)
}

fn int224_max() -> IBig {
    (IBig::ONE << 223) - IBig::ONE
}

/// The largest Float of a sign in magnitude: int224.max or int224.min at
/// int32.max.
fn largest_float(negative: bool) -> D {
    D::from_parts(cap(negative), I32_MAX)
}

/// The largest int224 coefficient magnitude of a sign: 2^223 - 1 positive,
/// 2^223 negative.
fn cap(negative: bool) -> IBig {
    if negative { IBig::ONE << 223 } else { int224_max() }
}

pub(crate) fn same(a: &D, b: &D) -> bool {
    a.partial_cmp(b) == Some(Ordering::Equal)
}

/// How a value fails to be a Float.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Range {
    Over,
    Under,
}

impl Range {
    fn error(self) -> RefError {
        match self {
            Range::Over => RefError::ExponentOverflow,
            Range::Under => RefError::ExponentUnderflow,
        }
    }
}

/// The documented packing rule (#333, README "Packing"), as its definition:
/// the Float closest to `v` that does not exceed it in magnitude, the largest
/// of `min(cap, floor(|v| / 10^e)) 10^e` over exponents, cap int224.max for
/// a positive `v` and |int224.min| for a
/// negative one. Past the largest Float of its sign that is `Over`; a
/// non-zero `v` whose largest such Float is zero is `Under`.
///
/// Below 10^(L - 68), L the exponent of |v|'s leading digit, every candidate
/// is cap 10^e and grows with e; above 10^L every candidate is zero.
/// So the window [L - 70, L + 1] holds the largest, with the int32 floor
/// applied, and the ceiling applied after as the comparison with the largest
/// Float.
pub(crate) fn toward_zero(v: &D) -> Result<D, Range> {
    let r = v.repr();
    if r.significand() == &IBig::ZERO {
        return Ok(D::ZERO);
    }
    let negative = r.significand() < &IBig::ZERO;
    let magnitude = r.significand().abs();
    let lead = r.exponent() + r.digits() as isize - 1;
    let cap = cap(negative);
    let mut best = D::ZERO;
    for e in (lead - 70).max(I32_MIN)..=lead + 1 {
        let floor = D::from_parts(magnitude.clone(), r.exponent() - e)
            .floor()
            .to_int()
            .value();
        let c = if floor > cap { cap.clone() } else { floor };
        let candidate = D::from_parts(c, e);
        if candidate > best {
            best = candidate;
        }
    }
    if best > largest_float(negative) {
        return Err(Range::Over);
    }
    if best == D::ZERO {
        return Err(Range::Under);
    }
    Ok(if negative { -best } else { best })
}

// ------------------------------------------------------------------ checking

fn sol_float<C: alloy::sol_types::SolCall<Return = B256>>(c: C) -> Sol<Dec> {
    exact::sol_float(c)
}

fn sol_bool<C: alloy::sol_types::SolCall<Return = bool>>(c: C) -> bool {
    evm::concrete(c).unwrap()
}

/// The Solidity result against dashu's: the same value, or the same error.
/// With `reporting`, a revert must also carry exactly that Float, unpacked.
fn check(
    case: &str,
    sol: Sol<Dec>,
    want: Result<D, RefError>,
    reporting: Option<&Dec>,
) -> Result<(), TestCaseError> {
    match (sol, want) {
        (Ok(s), Ok(w)) => {
            let s = d(&s);
            prop_assert!(same(&s, &w), "{case}: solidity {s}, dashu {w}");
        }
        (Err(s), Err(w)) => {
            prop_assert!(error_matches(&s, w), "{case}: solidity {s:?}, dashu {w:?}");
            if let (Some(input), Fail::Revert(out)) = (reporting, &s) {
                let data = revert_data(w, input, None);
                prop_assert_eq!(out.as_ref(), data.as_slice(), "{}: revert data", case);
            }
        }
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, dashu {w:?}"),
    }
    Ok(())
}

fn packed(v: D) -> Result<D, RefError> {
    toward_zero(&v).map_err(Range::error)
}

fn rounded(r: dashu_float::round::Rounded<D>) -> D {
    r.value()
}

/// add, sub and mul: the exact result rounded once toward zero (#333, #434,
/// #436). dashu truncates to `P` digits first, which the grid truncation
/// absorbs.
pub(crate) fn want_add(a: &Dec, b: &Dec) -> Result<D, RefError> {
    packed(rounded(ctx().add(d(a).repr(), d(b).repr()).unwrap()))
}

/// `b` is negated exactly before the sum (#436).
pub(crate) fn want_sub(a: &Dec, b: &Dec) -> Result<D, RefError> {
    packed(rounded(ctx().sub(d(a).repr(), d(b).repr()).unwrap()))
}

pub(crate) fn want_mul(a: &Dec, b: &Dec) -> Result<D, RefError> {
    packed(rounded(ctx().mul(d(a).repr(), d(b).repr()).unwrap()))
}

/// The closest Float to the exact quotient not above it, `DivisionByZero` for
/// a zero divisor.
pub(crate) fn want_div(a: &Dec, b: &Dec) -> Result<D, RefError> {
    if b.is_zero() {
        return Err(RefError::DivisionByZero);
    }
    packed(rounded(ctx().div(d(a).repr(), d(b).repr()).unwrap()))
}

fn bin(a: &Dec, b: &Dec) -> (B256, B256) {
    (a.to_bytes(), b.to_bytes())
}

fn check_add(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let (fa, fb) = bin(a, b);
    let case = format!("add({}, {})", show(a), show(b));
    check(&case, sol_float(T::addCall { a: fa, b: fb }), want_add(a, b), None)
}

fn check_sub(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let (fa, fb) = bin(a, b);
    let case = format!("sub({}, {})", show(a), show(b));
    check(&case, sol_float(T::subCall { a: fa, b: fb }), want_sub(a, b), None)
}

fn check_mul(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let (fa, fb) = bin(a, b);
    let case = format!("mul({}, {})", show(a), show(b));
    check(&case, sol_float(T::mulCall { a: fa, b: fb }), want_mul(a, b), None)
}

/// Every range error of `div` reports `a`, unpacked (NatSpec).
fn check_div(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let (fa, fb) = bin(a, b);
    let case = format!("div({}, {})", show(a), show(b));
    check(
        &case,
        sol_float(T::divCall { a: fa, b: fb }),
        want_div(a, b),
        Some(a),
    )
}

/// Comparisons are exact; `min` is `a < b ? a : b` and `max` is
/// `a > b ? a : b`, so each returns one of its inputs as given.
fn check_compare(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let (fa, fb) = bin(a, b);
    let case = format!("compare({}, {})", show(a), show(b));
    let order = d(a).partial_cmp(&d(b)).unwrap();
    let got = [
        sol_bool(T::eqCall { a: fa, b: fb }),
        sol_bool(T::ltCall { a: fa, b: fb }),
        sol_bool(T::gtCall { a: fa, b: fb }),
        sol_bool(T::lteCall { a: fa, b: fb }),
        sol_bool(T::gteCall { a: fa, b: fb }),
    ];
    let want = [
        order == Ordering::Equal,
        order == Ordering::Less,
        order == Ordering::Greater,
        order != Ordering::Greater,
        order != Ordering::Less,
    ];
    prop_assert_eq!(got, want, "{}: eq lt gt lte gte, dashu order {:?}", case, order);
    let min = evm::concrete(T::minCall { a: fa, b: fb }).unwrap();
    let max = evm::concrete(T::maxCall { a: fa, b: fb }).unwrap();
    prop_assert_eq!(min, if order == Ordering::Less { fa } else { fb }, "{}: min", case);
    prop_assert_eq!(max, if order == Ordering::Greater { fa } else { fb }, "{}: max", case);
    Ok(())
}

/// The exact unary results, packed by the rule: minus and abs negate exactly
/// (int224.min's negation then packs as any value does), integer truncates,
/// frac is what integer drops, floor and ceil are exact.
fn check_unary(a: &Dec) -> Result<(), TestCaseError> {
    let fa = a.to_bytes();
    let x = d(a);
    let s = show(a);
    let negative = x < D::ZERO;
    check(&format!("minus({s})"), sol_float(T::minusCall { a: fa }), packed(-x.clone()), None)?;
    let abs = if negative { -x.clone() } else { x.clone() };
    check(&format!("abs({s})"), sol_float(T::absCall { a: fa }), packed(abs), None)?;
    let trunc = x.trunc();
    check(&format!("integer({s})"), sol_float(T::integerCall { a: fa }), packed(trunc.clone()), None)?;
    // dashu aligns an unlimited subtraction digit by digit, so a zero
    // integer part, whose exponent is 0, is not subtracted from a value at
    // 10^-2^31.
    let frac = if trunc == D::ZERO {
        x.clone()
    } else {
        rounded(Context::<Zero>::new(0).sub(x.repr(), trunc.repr()).unwrap())
    };
    check(&format!("frac({s})"), sol_float(T::fracCall { a: fa }), packed(frac), None)?;
    check(&format!("floor({s})"), sol_float(T::floorCall { a: fa }), packed(x.floor()), None)?;
    check(&format!("ceil({s})"), sol_float(T::ceilCall { a: fa }), packed(x.ceil()), None)?;
    prop_assert_eq!(
        sol_bool(T::isZeroCall { a: fa }),
        x == D::ZERO,
        "isZero({})",
        s
    );
    // inv is div of one by `a`, its errors reporting `a`.
    let one = Dec::new(1, 0);
    check(
        &format!("inv({s})"),
        sol_float(T::invCall { a: fa }),
        want_div(&one, a),
        Some(a),
    )
}

/// `value × 10^-decimals` packed by the rule, `lossless` iff that is exact;
/// the lossless form reverts `LossyConversionToFloat` where it is not.
fn check_from_fixed(value: U256, decimals: u8) -> Result<(), TestCaseError> {
    let case = format!("fromFixedDecimal({value}, {decimals})");
    let x = D::from_parts(value.to_string().parse().unwrap(), -(decimals as isize));
    let want = packed(x.clone());
    let exact = matches!(&want, Ok(w) if same(w, &x));
    let lossy = evm::concrete(T::fromFixedDecimalLossyCall { value, decimals });
    match (lossy, &want) {
        (Ok(r), Ok(w)) => {
            let s = d(&Dec::from_bytes(r._0));
            prop_assert!(same(&s, w), "{case}: solidity {s}, dashu {w}");
            prop_assert_eq!(r._1, exact, "{}: lossless flag", case);
        }
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, dashu {w:?}"),
    }
    let want = if exact { want } else { Err(RefError::LossyConversionToFloat) };
    check(
        &format!("{case} lossless"),
        sol_float(T::fromFixedDecimalLosslessCall { value, decimals }),
        want,
        None,
    )
}

/// `a × 10^decimals` truncated toward zero: a negative `a` reverts
/// `NegativeFixedDecimalConversion`, a value at or above 2^256
/// `FixedDecimalOverflow`, and the lossless form reverts
/// `LossyConversionFromFloat` where anything was truncated.
fn check_to_fixed(a: &Dec, decimals: u8) -> Result<(), TestCaseError> {
    let case = format!("toFixedDecimal({}, {decimals})", show(a));
    let float = a.to_bytes();
    let x = d(a);
    // Exact: only the exponent moves.
    let scaled = D::from_parts(x.repr().significand().clone(), x.repr().exponent() + decimals as isize);
    let bound = D::from_parts(IBig::ONE << 256, 0);
    let want: Result<(U256, bool), RefError> = if x < D::ZERO {
        Err(RefError::NegativeFixedDecimalConversion)
    } else if scaled >= bound {
        Err(RefError::FixedDecimalOverflow)
    } else {
        let t = scaled.trunc();
        let v: U256 = t.to_int().value().to_string().parse().unwrap();
        Ok((v, same(&t, &scaled)))
    };
    let lossy = evm::concrete(T::toFixedDecimalLossyCall { float, decimals });
    match (lossy, want) {
        (Ok(r), Ok(w)) => prop_assert_eq!((r._0, r._1), w, "{}", case),
        (Err(s), Err(w)) => prop_assert!(
            error_matches(&Fail::Revert(s.clone()), w),
            "{case}: solidity {s:?}, dashu {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, dashu {w:?}"),
    }
    let want = match want {
        Ok((v, true)) => Ok(v),
        Ok((_, false)) => Err(RefError::LossyConversionFromFloat),
        Err(e) => Err(e),
    };
    match (evm::concrete(T::toFixedDecimalLosslessCall { float, decimals }), want) {
        (Ok(s), Ok(w)) => prop_assert_eq!(s, w, "{} lossless", case),
        (Err(s), Err(w)) => prop_assert!(
            error_matches(&Fail::Revert(s.clone()), w),
            "{case} lossless: solidity {s:?}, dashu {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case} lossless: solidity {s:?}, dashu {w:?}"),
    }
    Ok(())
}

/// Whether `x` is a whole odd number, by dashu's integer remainder.
fn odd(x: &D) -> bool {
    let r = x.repr();
    if r.exponent() > 0 {
        // A multiple of ten.
        return false;
    }
    let t = x.trunc();
    same(&t, x) && (t.to_int().value() % IBig::from(2)) != IBig::ZERO
}

/// Harness-only surface: `isOdd`, and `canonicalize`, which keeps the value
/// and returns its largest int224 coefficient at an exponent no lower than
/// int32.min, so equal values canonicalize to equal bytes.
fn check_harness_unary(a: &Dec) -> Result<(), TestCaseError> {
    let fa = a.to_bytes();
    let x = d(a);
    let s = show(a);
    prop_assert_eq!(
        evm::harness(H::isOddCall { float: fa }).unwrap(),
        odd(&x),
        "isOdd({})",
        s
    );
    let c = evm::harness(H::canonicalizeCall { float: fa }).unwrap();
    let cd = Dec::from_bytes(c);
    prop_assert!(same(&d(&cd), &x), "canonicalize({s}): value {}", show(&cd));
    if x != D::ZERO {
        let r = x.repr();
        let mut sig = r.significand().clone();
        let mut e = r.exponent();
        let ten = IBig::from(10);
        let cap = cap(sig < IBig::ZERO);
        while (&sig * &ten).abs() <= cap && e > I32_MIN {
            sig *= &ten;
            e -= 1;
        }
        prop_assert_eq!(
            (ibig(&cd.c), cd.e as isize),
            (sig, e),
            "canonicalize({})",
            s
        );
    } else {
        let zero = evm::harness(H::canonicalizeCall { float: B256::ZERO }).unwrap();
        prop_assert_eq!(c, zero, "canonicalize({}): zero", s);
    }
    Ok(())
}

/// `packLossy` and `packLossless` over int256 coefficients and exponents:
/// the rule's Float with `lossless` iff exact; `FLOAT_ZERO` and not lossless
/// for a non-zero value below every Float; `ExponentOverflow` past them all.
/// `packLossless` reverts `LossyConversionToFloat` on any inexact value.
fn check_pack(c: &IBig, e: &IBig) -> Result<(), TestCaseError> {
    let case = format!("pack({c}, {e})");
    let to_i256 = |x: &IBig| alloy::primitives::I256::from_dec_str(&x.to_string()).unwrap();
    let (sc, se) = (to_i256(c), to_i256(e));
    // An exponent past isize leaves a non-zero value past or below every
    // Float without arithmetic.
    let want: Result<(D, bool), RefError> = match isize::try_from(e.clone()) {
        _ if *c == IBig::ZERO => Ok((D::ZERO, true)),
        Ok(e) if e.unsigned_abs() < (1usize << 60) => {
            let v = D::from_parts(c.clone(), e);
            match toward_zero(&v) {
                Ok(w) => {
                    let exact = same(&w, &v);
                    Ok((w, exact))
                }
                Err(Range::Under) => Ok((D::ZERO, false)),
                Err(Range::Over) => Err(RefError::ExponentOverflow),
            }
        }
        _ if *e > IBig::ZERO => Err(RefError::ExponentOverflow),
        _ => Ok((D::ZERO, false)),
    };
    let lossy = evm::harness(H::packLossyCall { signedCoefficient: sc, exponent: se });
    match (lossy, &want) {
        (Ok(r), Ok((w, l))) => {
            let s = d(&Dec::from_bytes(r._0));
            prop_assert!(same(&s, w), "{case}: solidity {s}, dashu {w}");
            prop_assert_eq!(r._1, *l, "{}: lossless flag", case);
        }
        (Err(s), Err(w)) => prop_assert!(
            error_matches(&Fail::Harness(s.clone()), *w),
            "{case}: solidity {s:?}, dashu {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, dashu {w:?}"),
    }
    let want = match want {
        Ok((w, true)) => Ok(w),
        Ok((_, false)) => Err(RefError::LossyConversionToFloat),
        Err(e) => Err(e),
    };
    let lossless = evm::harness(H::packLosslessCall { signedCoefficient: sc, exponent: se });
    match (lossless, want) {
        (Ok(r), Ok(w)) => {
            let s = d(&Dec::from_bytes(r));
            prop_assert!(same(&s, &w), "{case} lossless: solidity {s}, dashu {w}");
        }
        (Err(s), Err(w)) => prop_assert!(
            error_matches(&Fail::Harness(s.clone()), w),
            "{case} lossless: solidity {s:?}, dashu {w:?}"
        ),
        (s, w) => prop_assert!(false, "{case} lossless: solidity {s:?}, dashu {w:?}"),
    }
    Ok(())
}

/// Every int256, weighted to the int224 and int32 edges and small values.
fn int256() -> BoxedStrategy<IBig> {
    let from = |b: [u8; 32]| IBig::from_be_bytes(&b) - (IBig::ONE << 255);
    prop_oneof![
        2 => any::<[u8; 32]>().prop_map(from),
        2 => exact::coefficient().prop_map(|c| ibig(&c)),
        1 => (0u32..=255, any::<[u8; 32]>(), any::<bool>()).prop_map(move |(bits, b, neg)| {
            let x = from(b).abs() >> (255 - bits as usize);
            if neg { -x } else { x }
        }),
        1 => (-80i64..=80).prop_map(|k| (IBig::ONE << 223) + IBig::from(k)),
        1 => (-80i64..=80).prop_map(|k| -(IBig::ONE << 223) + IBig::from(k)),
    ]
    .boxed()
}

fn exponent256() -> BoxedStrategy<IBig> {
    prop_oneof![
        3 => exact::exponent().prop_map(IBig::from),
        1 => (-200i64..=200).prop_map(|k| IBig::from(I32_MAX as i64 + k)),
        1 => (-200i64..=200).prop_map(|k| IBig::from(I32_MIN as i64 + k)),
        1 => int256(),
    ]
    .boxed()
}

// ------------------------------------------------------------ parse, format

/// A literal the parser documents as well formed: an optional `-`, digits,
/// optionally `.` and digits, optionally `e` or `E`, an optional sign and
/// digits. Every part may carry leading or trailing zeros, and the exponent
/// reaches past both int32 ends.
fn literal() -> BoxedStrategy<String> {
    let digits = |max: usize| {
        prop_oneof![
            3 => proptest::collection::vec(0u8..=9, 1..=max),
            1 => (1usize..=max, 0u8..=9).prop_map(|(n, d)| vec![d; n]),
            1 => (0usize..=max.min(80), 1usize..=4).prop_map(|(z, n)| {
                let mut v = vec![0; z];
                v.extend(std::iter::repeat_n(9, n));
                v
            }),
        ]
        .prop_map(|v| v.into_iter().map(|d| char::from(b'0' + d)).collect::<String>())
    };
    let exp = prop_oneof![
        2 => -100i64..=100,
        2 => (-140i64..=140).prop_map(|k| I32_MAX as i64 + k),
        2 => (-140i64..=140).prop_map(|k| I32_MIN as i64 + k),
        1 => any::<i32>().prop_map(i64::from),
        1 => any::<i64>().prop_map(|e| e / 4),
    ];
    (
        any::<bool>(),
        digits(90),
        proptest::option::of(digits(90)),
        proptest::option::of((any::<bool>(), 0u8..3, exp, 0usize..3)),
    )
        .prop_map(|(neg, int, frac, exp)| {
            let mut s = String::new();
            if neg {
                s.push('-');
            }
            s.push_str(&int);
            if let Some(f) = frac {
                s.push('.');
                s.push_str(&f);
            }
            if let Some((upper, sign, e, zeros)) = exp {
                s.push(if upper { 'E' } else { 'e' });
                match (sign, e < 0) {
                    (_, true) => s.push('-'),
                    (1, false) => s.push('+'),
                    _ => {}
                }
                s.push_str(&"0".repeat(zeros));
                s.push_str(&e.unsigned_abs().to_string());
            }
            s
        })
        .boxed()
}

/// A well formed literal is its exact value when that is a Float,
/// `ExponentOverflow` (returned or reverted) when it is past every Float, and
/// `ParseDecimalPrecisionLoss` otherwise, with a zero Float on any error
/// (#433, `parseDecimalFloat` NatSpec). dashu reads the literal.
fn check_parse(s: &str) -> Result<(), TestCaseError> {
    let case = format!("parse({s:?})");
    let v: D = s.parse().unwrap_or_else(|e| panic!("dashu parse {s:?}: {e:?}"));
    let want = match toward_zero(&v) {
        Ok(w) if same(&w, &v) => Ok(v.clone()),
        Err(Range::Over) => Err(RefError::ExponentOverflow),
        _ => Err(RefError::ParseDecimalPrecisionLoss),
    };
    match (evm::concrete(T::parseCall { str: s.to_string() }), want) {
        (Ok(r), Ok(w)) => {
            prop_assert_eq!(r._0.0, [0u8; 4], "{}: selector", case);
            let got = d(&Dec::from_bytes(r._1));
            prop_assert!(same(&got, &w), "{case}: solidity {got}, dashu {w}");
        }
        (Ok(r), Err(w)) => {
            prop_assert_eq!(r._0.0, w.selector(), "{}: selector, dashu {:?}", case, w);
            prop_assert_eq!(r._1, B256::ZERO, "{}: float on error", case);
        }
        (Err(out), Err(w)) => prop_assert!(
            w == RefError::ExponentOverflow && error_matches(&Fail::Revert(out.clone()), w),
            "{case}: solidity revert {out:?}, dashu {w:?}"
        ),
        (Err(out), Ok(w)) => prop_assert!(false, "{case}: solidity revert {out:?}, dashu {w}"),
    }
    Ok(())
}

/// `-`? then `0` or a digit string with no leading zero, then optionally `.`
/// and digits ending in a non-zero digit.
fn plain_shape(s: &str) -> bool {
    let s = s.strip_prefix('-').unwrap_or(s);
    let (int, frac) = match s.split_once('.') {
        Some((i, f)) => (i, Some(f)),
        None => (s, None),
    };
    let int_ok = int == "0"
        || (!int.is_empty() && !int.starts_with('0') && int.bytes().all(|b| b.is_ascii_digit()));
    let frac_ok = frac.is_none_or(|f| {
        !f.is_empty() && f.bytes().all(|b| b.is_ascii_digit()) && !f.ends_with('0')
    });
    int_ok && frac_ok
}

/// `-`? then one non-zero digit, optionally `.` and digits ending in a
/// non-zero digit, then optionally `e`, `-`? and a decimal with no leading
/// zero, never `e0`.
fn scientific_shape(s: &str) -> bool {
    let s = s.strip_prefix('-').unwrap_or(s);
    let (mantissa, exp) = match s.split_once('e') {
        Some((m, e)) => (m, Some(e)),
        None => (s, None),
    };
    let lead_ok = mantissa.as_bytes().first().is_some_and(|b| (b'1'..=b'9').contains(b));
    let rest = &mantissa[1.min(mantissa.len())..];
    let rest_ok = rest.is_empty()
        || rest.strip_prefix('.').is_some_and(|f| {
            !f.is_empty() && f.bytes().all(|b| b.is_ascii_digit()) && !f.ends_with('0')
        });
    let exp_ok = exp.is_none_or(|e| {
        let e = e.strip_prefix('-').unwrap_or(e);
        !e.is_empty() && !e.starts_with('0') && e.bytes().all(|b| b.is_ascii_digit())
    });
    lead_ok && rest_ok && exp_ok
}

/// `format` writes the value exactly, as dashu reads it back, in the one
/// string of its documented shape: zero is `0`; plain notation reverts
/// `UnformatableExponent` for a stored exponent past ±1000; scientific
/// notation leads with the first significant digit and omits `e0`.
fn check_format(a: &Dec) -> Result<(), TestCaseError> {
    let x = d(a);
    for scientific in [false, true] {
        let case = format!("format({}, {scientific})", show(a));
        let got = evm::concrete(T::formatCall { a: a.to_bytes(), scientific });
        if x == D::ZERO {
            prop_assert_eq!(got.ok(), Some("0".to_string()), "{}", case);
            continue;
        }
        if !scientific && a.e.abs() > 1000 {
            let want = RefError::UnformatableExponent;
            prop_assert!(
                got.as_ref().is_err_and(|out| error_matches(&Fail::Revert(out.clone()), want)),
                "{case}: solidity {got:?}, want {want:?}"
            );
            continue;
        }
        let s = match got {
            Ok(s) => s,
            Err(out) => return Err(TestCaseError::fail(format!("{case}: reverted {out:?}"))),
        };
        let shaped = if scientific { scientific_shape(&s) } else { plain_shape(&s) };
        prop_assert!(shaped, "{case}: shape of {s:?}");
        let back: D = s.parse().unwrap_or_else(|e| panic!("dashu parse {s:?}: {e:?}"));
        prop_assert!(same(&back, &x), "{case}: {s:?} reads as {back}, not {x}");
    }
    Ok(())
}

proptest! {
    #![proptest_config(config())]

    #[test]
    fn differential_parse(s in literal()) { check_parse(&s)?; }

    #[test]
    fn differential_format(a in exact::float()) { check_format(&a)?; }
}

proptest! {
    #![proptest_config(config())]

    #[test]
    fn differential_from_fixed_decimal(value in exact::u256(), decimals in any::<u8>()) {
        check_from_fixed(value, decimals)?;
    }

    #[test]
    fn differential_to_fixed_decimal(a in exact::float(), decimals in prop_oneof![any::<u8>(), 0u8..=80]) {
        check_to_fixed(&a, decimals)?;
    }

    #[test]
    fn differential_harness_unary(a in exact::float()) { check_harness_unary(&a)?; }

    #[test]
    fn differential_pack(c in int256(), e in exponent256()) { check_pack(&c, &e)?; }

    #[test]
    fn differential_add((a, b) in pair()) { check_add(&a, &b)?; }

    #[test]
    fn differential_sub((a, b) in pair()) { check_sub(&a, &b)?; }

    #[test]
    fn differential_mul((a, b) in pair()) { check_mul(&a, &b)?; }

    #[test]
    fn differential_div((a, b) in pair()) { check_div(&a, &b)?; }

    #[test]
    fn differential_compare_min_max((a, b) in pair()) { check_compare(&a, &b)?; }

    #[test]
    fn differential_unary(a in exact::float()) { check_unary(&a)?; }
}

/// The oracle on fixed examples whose values are the README's and #333's,
/// so a misconfigured dashu context fails here and not only under fuzz.
#[cfg(test)]
mod oracle {
    use super::*;

    fn dec(s: &str) -> D {
        s.parse().unwrap()
    }

    fn nines(n: usize) -> IBig {
        IBig::from(10).pow(n) - IBig::ONE
    }

    #[test]
    fn readme_sums() {
        let one = Dec::new(1, 0);
        // 1e100 + 1e-100 is 1e100.
        let w = want_add(&Dec::new(1, 100), &Dec::new(1, -100)).unwrap();
        assert!(same(&w, &dec("1e100")));
        // 1e100 - 1 is (1e67 - 1)e33.
        let w = want_sub(&Dec::new(1, 100), &one).unwrap();
        assert!(same(&w, &D::from_parts(nines(67), 33)));
        // 1 - 1e-100 is 0. then 67 nines.
        let w = want_sub(&one, &Dec::new(1, -100)).unwrap();
        assert!(same(&w, &D::from_parts(nines(67), -67)));
        // 1e100 - (1e33 + 1) is 1e100 - 2e33, and so is 1e100 - 1.7e33.
        let want = D::from_parts(IBig::from(10).pow(67) - IBig::from(2), 33);
        let b = Dec::new(num_bigint::BigInt::from(10).pow(33) + 1, 0);
        assert!(same(&want_sub(&Dec::new(1, 100), &b).unwrap(), &want));
        assert!(same(&want_sub(&Dec::new(1, 100), &Dec::new(17, 32)).unwrap(), &want));
    }

    #[test]
    fn extreme_exponent_gap() {
        // The gap is past any materialised sum: dashu must round it lazily.
        let a = Dec::new(1, I32_MAX as i64);
        let b = Dec::new(-1, I32_MIN as i64);
        // The largest Float below 10^int32.max: 67 nines.
        let w = want_add(&a, &b).unwrap();
        assert!(same(&w, &D::from_parts(nines(67), I32_MAX - 67)));
    }

    /// Full coefficients at both exponent ends, each way round and each sign:
    /// the oracle must answer without materialising the gap.
    #[test]
    fn extreme_gaps_are_cheap() {
        let big: num_bigint::BigInt = num_bigint::BigInt::from(10).pow(66) * 13 + 7;
        for (ea, eb) in [(I32_MAX, I32_MIN), (I32_MIN, I32_MAX)] {
            for sb in [1i32, -1] {
                let a = Dec::new(big.clone(), ea as i64);
                let b = Dec::new(&big * sb, eb as i64);
                let _ = want_add(&a, &b);
                let _ = want_sub(&a, &b);
                let _ = want_mul(&a, &b);
                let _ = want_div(&a, &b);
            }
        }
    }

    #[test]
    fn packing_bound() {
        // 2^223 packs as int224.max at the same exponent, and -2^223 is
        // int224.min (#333).
        let two223 = D::from_parts(IBig::ONE << 223, 5);
        assert!(same(&toward_zero(&two223).unwrap(), &D::from_parts(int224_max(), 5)));
        assert!(same(&toward_zero(&-two223.clone()).unwrap(), &-two223.clone()));
        let past = D::from_parts(-(IBig::ONE << 223) - IBig::ONE, 5);
        assert!(same(&toward_zero(&past).unwrap(), &-two223.clone()));
        // Overflow starts at (2^223 + 2) 10^int32.max (#433, revertIfPastLargestFloat).
        let edge = (IBig::ONE << 223) + IBig::from(2);
        assert_eq!(toward_zero(&D::from_parts(edge.clone(), I32_MAX)), Err(Range::Over));
        assert_eq!(toward_zero(&D::from_parts(-edge.clone(), I32_MAX)), Err(Range::Over));
        let below = D::from_parts(edge.clone() * IBig::from(10) - IBig::ONE, I32_MAX - 1);
        assert!(same(&toward_zero(&below).unwrap(), &largest_float(false)));
        assert!(same(&toward_zero(&-below).unwrap(), &-largest_float(true)));
        // Below 1e-2147483648 nothing non-zero is left.
        assert_eq!(toward_zero(&D::from_parts(IBig::from(9), I32_MIN - 1)), Err(Range::Under));
        let lifted = toward_zero(&D::from_parts(IBig::from(19), I32_MIN - 1)).unwrap();
        assert!(same(&lifted, &D::from_parts(IBig::ONE, I32_MIN)));
    }

    /// dashu reads every literal shape `literal()` writes as the parser
    /// documents it.
    #[test]
    fn dashu_reads_literals() {
        for (s, c, e) in [
            ("1E+05", 1, 5),
            ("-0.0e-0", 0, 0),
            ("007.50e0003", 75, 2),
            ("-12.5E-002", -125, -3),
            ("0", 0, 0),
        ] {
            assert!(same(&dec(s), &D::from_parts(IBig::from(c), e)), "{s}");
        }
        assert!(plain_shape("-0.5") && plain_shape("120") && !plain_shape("1.50") && !plain_shape("01"));
        assert!(scientific_shape("-1.5e-7") && scientific_shape("3") && !scientific_shape("1e0"));
        assert!(!scientific_shape("15e1") && !scientific_shape("1.0e2"));
    }

    #[test]
    fn division_truncates() {
        let w = want_div(&Dec::new(1, 0), &Dec::new(3, 0)).unwrap();
        // 1/3 at the largest coefficient that fits: 67 threes (3.3e66 < 1.3e67
        // < 3.3e67).
        assert!(same(&w, &D::from_parts(nines(67) / IBig::from(3), -67)));
        let w = want_div(&Dec::new(-2, 0), &Dec::new(3, 0)).unwrap();
        assert!(same(&w, &-D::from_parts(nines(67) * IBig::from(2) / IBig::from(3), -67)));
        assert_eq!(want_div(&Dec::new(1, 0), &Dec::zero()), Err(RefError::DivisionByZero));
    }
}
