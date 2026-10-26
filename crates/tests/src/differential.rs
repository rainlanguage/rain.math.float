//! Differential fuzz of the Solidity against dashu-float (#439), an
//! arbitrary precision decimal library this repo did not write, configured to
//! the documented rules. No expected value here comes from `reference.rs`,
//! `LibExactFloat` or the Python oracle: the inputs and the Solidity calls are
//! shared with `exact.rs`, every value the Solidity is checked against is
//! computed by dashu.

use crate::common::{self, PARSE_EMPTY_DECIMAL_STRING, selector};
use crate::evm::{self, TestDecimalFloat as T, TestDecimalFloatHarness as H};
use crate::exact::{self, Fail, Sol, config, error_matches, pair, show, sol_bool, sol_float};
use crate::reference::{self as r, Dec, RefError, pow10};
use crate::transcendental::{self, revert_data};
use alloy::primitives::{B256, I256, U256};
use core::cmp::Ordering;
use dashu_base::Abs;
use dashu_float::round::mode::{Away, HalfAway, Zero};
use dashu_float::{Context, FBig};
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

/// The `P`-digit context every rounded operation uses.
fn ctx() -> Context<Zero> {
    Context::new(P)
}

/// A num-bigint integer as dashu's.
fn ibig(c: &num_bigint::BigInt) -> IBig {
    c.to_string().parse().unwrap()
}

/// The dashu value of a Float's fields.
pub(crate) fn d(x: &Dec) -> D {
    D::from_parts(ibig(&x.c), x.e as isize)
}

/// 2^223 - 1.
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
    if negative {
        IBig::ONE << 223
    } else {
        int224_max()
    }
}

/// Whether two dashu values are the same number.
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

/// The rule's Float for `v`, or its range error.
fn packed(v: D) -> Result<D, RefError> {
    toward_zero(&v).map_err(Range::error)
}

/// An int256 as its ABI word.
fn word(x: &IBig) -> [u8; 32] {
    I256::from_dec_str(&x.to_string())
        .unwrap()
        .to_be_bytes::<32>()
}

/// The ABI word as an int256.
fn int_of(w: &[u8]) -> IBig {
    I256::from_be_bytes::<32>(w.try_into().unwrap())
        .to_string()
        .parse()
        .unwrap()
}

/// The revert data of `e` with `words` as its arguments.
fn revert_with(e: RefError, words: &[[u8; 32]]) -> Vec<u8> {
    let mut out = e.selector().to_vec();
    for w in words {
        out.extend_from_slice(w);
    }
    out
}

/// A range error of add, sub or mul reports the unpacked result passed to
/// packing (SPEC "add, sub" and "mul"). That pair has the same range error
/// under the rule and the exact result's sign, and is the exact result
/// truncated toward zero on a grid at least as fine as the 67 digits a
/// Float holds there, as that truncation composes with packing (PR #434).
fn check_reported(
    case: &str,
    sol: Sol<Dec>,
    want: Result<D, RefError>,
    exact: impl FnOnce() -> D,
) -> Result<(), TestCaseError> {
    if let (Err(Fail::Revert(out)), Err(w)) = (&sol, &want) {
        let range = match w {
            RefError::ExponentOverflow => Range::Over,
            _ => Range::Under,
        };
        prop_assert!(
            out.len() == 68 && out[..4] == w.selector(),
            "{case}: revert data {out:?}, dashu {w:?}"
        );
        let e = isize::try_from(int_of(&out[36..68]));
        prop_assert!(e.is_ok(), "{case}: reported exponent {:?}", e);
        let v = D::from_parts(int_of(&out[4..36]), e.unwrap());
        let x = exact();
        prop_assert_eq!(
            toward_zero(&v).err(),
            Some(range),
            "{}: reported {}",
            case,
            v
        );
        prop_assert!(
            (v < D::ZERO) == (x < D::ZERO) && magnitude(&v) <= magnitude(&x),
            "{case}: reported {v}, exact {x}"
        );
        prop_assert!(
            distance(&x, &v) < D::from_parts(IBig::ONE, lead(&x) - 66),
            "{case}: reported {v}, exact {x}"
        );
    }
    check(case, sol, want, None)
}

/// The exact sum, difference or product, unrounded: only asked for where the
/// result is past or below every Float, so the operands are close in
/// exponent and the sum is short.
fn exact_add(a: &Dec, b: &Dec) -> D {
    rounded(
        Context::<Zero>::new(0)
            .add(d(a).repr(), d(b).repr())
            .unwrap(),
    )
}

/// The exact difference, unrounded.
fn exact_sub(a: &Dec, b: &Dec) -> D {
    rounded(
        Context::<Zero>::new(0)
            .sub(d(a).repr(), d(b).repr())
            .unwrap(),
    )
}

/// The exact product, unrounded.
fn exact_mul(a: &Dec, b: &Dec) -> D {
    rounded(
        Context::<Zero>::new(0)
            .mul(d(a).repr(), d(b).repr())
            .unwrap(),
    )
}

/// The value of a dashu rounding, its inexact flag dropped.
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

/// As `want_add`, for the product.
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

/// Two Floats as their bytes.
fn bin(a: &Dec, b: &Dec) -> (B256, B256) {
    (a.to_bytes(), b.to_bytes())
}

/// `add` against `want_add`; a range error reports the exact sum.
fn check_add(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let (fa, fb) = bin(a, b);
    let case = format!("add({}, {})", show(a), show(b));
    check_reported(
        &case,
        sol_float(T::addCall { a: fa, b: fb }),
        want_add(a, b),
        || exact_add(a, b),
    )
}

/// `sub` against `want_sub`; a range error reports the exact difference.
fn check_sub(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let (fa, fb) = bin(a, b);
    let case = format!("sub({}, {})", show(a), show(b));
    check_reported(
        &case,
        sol_float(T::subCall { a: fa, b: fb }),
        want_sub(a, b),
        || exact_sub(a, b),
    )
}

/// `mul` against `want_mul`; a range error reports the exact product.
fn check_mul(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let (fa, fb) = bin(a, b);
    let case = format!("mul({}, {})", show(a), show(b));
    check_reported(
        &case,
        sol_float(T::mulCall { a: fa, b: fb }),
        want_mul(a, b),
        || exact_mul(a, b),
    )
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
    prop_assert_eq!(
        got,
        want,
        "{}: eq lt gt lte gte, dashu order {:?}",
        case,
        order
    );
    let min = evm::concrete(T::minCall { a: fa, b: fb }).unwrap();
    let max = evm::concrete(T::maxCall { a: fa, b: fb }).unwrap();
    prop_assert_eq!(
        min,
        if order == Ordering::Less { fa } else { fb },
        "{}: min",
        case
    );
    prop_assert_eq!(
        max,
        if order == Ordering::Greater { fa } else { fb },
        "{}: max",
        case
    );
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
    check(
        &format!("minus({s})"),
        sol_float(T::minusCall { a: fa }),
        packed(-x.clone()),
        None,
    )?;
    let abs = if negative { -x.clone() } else { x.clone() };
    check(
        &format!("abs({s})"),
        sol_float(T::absCall { a: fa }),
        packed(abs),
        None,
    )?;
    let trunc = x.trunc();
    check(
        &format!("integer({s})"),
        sol_float(T::integerCall { a: fa }),
        packed(trunc.clone()),
        None,
    )?;
    // dashu aligns an unlimited subtraction digit by digit, so a zero
    // integer part, whose exponent is 0, is not subtracted from a value at
    // 10^-2^31.
    let frac = if trunc == D::ZERO {
        x.clone()
    } else {
        rounded(Context::<Zero>::new(0).sub(x.repr(), trunc.repr()).unwrap())
    };
    check(
        &format!("frac({s})"),
        sol_float(T::fracCall { a: fa }),
        packed(frac),
        None,
    )?;
    check(
        &format!("floor({s})"),
        sol_float(T::floorCall { a: fa }),
        packed(x.floor()),
        None,
    )?;
    check(
        &format!("ceil({s})"),
        sol_float(T::ceilCall { a: fa }),
        packed(x.ceil()),
        None,
    )?;
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
    let want = if exact {
        want
    } else {
        Err(RefError::LossyConversionToFloat)
    };
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
    let scaled = D::from_parts(
        x.repr().significand().clone(),
        x.repr().exponent() + decimals as isize,
    );
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
    // Every error reports the Float unpacked, and `FixedDecimalOverflow`
    // `decimals` too.
    let data = |e: RefError| {
        let mut words = vec![common::word(&a.c), word(&IBig::from(a.e))];
        if e == RefError::FixedDecimalOverflow {
            words.push(U256::from(decimals).to_be_bytes::<32>());
        }
        revert_with(e, &words)
    };
    let lossy = evm::concrete(T::toFixedDecimalLossyCall { float, decimals });
    match (lossy, want) {
        (Ok(r), Ok(w)) => prop_assert_eq!((r._0, r._1), w, "{}", case),
        (Err(s), Err(w)) => {
            prop_assert_eq!(s.to_vec(), data(w), "{}: revert data, dashu {:?}", case, w)
        }
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, dashu {w:?}"),
    }
    let want = match want {
        Ok((v, true)) => Ok(v),
        Ok((_, false)) => Err(RefError::LossyConversionFromFloat),
        Err(e) => Err(e),
    };
    match (
        evm::concrete(T::toFixedDecimalLosslessCall { float, decimals }),
        want,
    ) {
        (Ok(s), Ok(w)) => prop_assert_eq!(s, w, "{} lossless", case),
        (Err(s), Err(w)) => prop_assert_eq!(
            s.to_vec(),
            data(w),
            "{} lossless: revert data, dashu {:?}",
            case,
            w
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
        prop_assert_eq!(c, B256::ZERO, "canonicalize({}): FLOAT_ZERO", s);
    }
    Ok(())
}

/// `packLossy` and `packLossless` over int256 coefficients and exponents:
/// the rule's Float with `lossless` iff exact; `FLOAT_ZERO` and not lossless
/// for a non-zero value below every Float; `ExponentOverflow` past them all.
/// `packLossless` reverts `ExponentOverflow` on any value past the largest
/// Float of its sign, the band `packLossy` truncates into it included (#509,
/// NatSpec), and `LossyConversionToFloat` on any other inexact value. Every
/// error reports the inputs (SPEC "Packing").
fn check_pack(c: &IBig, e: &IBig) -> Result<(), TestCaseError> {
    let case = format!("pack({c}, {e})");
    let to_i256 = |x: &IBig| alloy::primitives::I256::from_dec_str(&x.to_string()).unwrap();
    let (sc, se) = (to_i256(c), to_i256(e));
    let data = |w: RefError| revert_with(w, &[word(c), word(e)]);
    // An exponent past isize leaves a non-zero value past or below every
    // Float without arithmetic.
    let mut past = false;
    let want: Result<(D, bool), RefError> = match isize::try_from(e.clone()) {
        _ if *c == IBig::ZERO => Ok((D::ZERO, true)),
        Ok(e) if e.unsigned_abs() < (1usize << 60) => {
            let v = D::from_parts(c.clone(), e);
            past = magnitude(&v) > largest_float(v < D::ZERO);
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
    let lossy = evm::harness(H::packLossyCall {
        signedCoefficient: sc,
        exponent: se,
    });
    // `isPastEveryFloat` of the magnitude is exactly where `packLossy`
    // reverts `ExponentOverflow` (#649).
    let is_past = evm::harness(H::isPastEveryFloat_0Call {
        magnitude: sc.unsigned_abs(),
        exponent: se,
    })
    .unwrap();
    prop_assert_eq!(
        is_past,
        matches!(want, Err(RefError::ExponentOverflow)),
        "isPastEveryFloat({}, {})",
        c,
        e
    );
    // The signed overload is the same predicate of the coefficient's
    // magnitude, int256.min as 2^255 included.
    let is_past_signed = evm::harness(H::isPastEveryFloat_1Call {
        signedCoefficient: sc,
        exponent: se,
    })
    .unwrap();
    prop_assert_eq!(
        is_past_signed,
        is_past,
        "signed isPastEveryFloat({}, {})",
        c,
        e
    );
    match (lossy, &want) {
        (Ok(r), Ok((w, l))) => {
            let s = d(&Dec::from_bytes(r._0));
            prop_assert!(same(&s, w), "{case}: solidity {s}, dashu {w}");
            prop_assert_eq!(r._1, *l, "{}: lossless flag", case);
        }
        (Err(s), Err(w)) => {
            prop_assert_eq!(s.to_vec(), data(*w), "{}: revert data, dashu {:?}", case, w)
        }
        (s, w) => prop_assert!(false, "{case}: solidity {s:?}, dashu {w:?}"),
    }
    let want = match want {
        _ if past => Err(RefError::ExponentOverflow),
        Ok((w, true)) => Ok(w),
        Ok((_, false)) => Err(RefError::LossyConversionToFloat),
        Err(e) => Err(e),
    };
    let lossless = evm::harness(H::packLosslessCall {
        signedCoefficient: sc,
        exponent: se,
    });
    match (lossless, want) {
        (Ok(r), Ok(w)) => {
            let s = d(&Dec::from_bytes(r));
            prop_assert!(same(&s, &w), "{case} lossless: solidity {s}, dashu {w}");
        }
        (Err(s), Err(w)) => prop_assert_eq!(
            s.to_vec(),
            data(w),
            "{} lossless: revert data, dashu {:?}",
            case,
            w
        ),
        (s, w) => prop_assert!(false, "{case} lossless: solidity {s:?}, dashu {w:?}"),
    }
    Ok(())
}

/// Every int256, weighted to the int224 and int32 edges and small values.
fn int256() -> BoxedStrategy<IBig> {
    // Two's complement: every int256.
    let from = |b: [u8; 32]| IBig::from_be_bytes(&b);
    prop_oneof![
        2 => any::<[u8; 32]>().prop_map(from),
        2 => exact::coefficient().prop_map(|c| ibig(&c)),
        1 => (0u32..=255, any::<[u8; 32]>(), any::<bool>()).prop_map(move |(bits, b, neg)| {
            // Under 2^bits, so inside int256 at either sign.
            let x = IBig::from(dashu_int::UBig::from_be_bytes(&b) >> (256 - bits as usize));
            if neg { -x } else { x }
        }),
        1 => (-80i64..=80).prop_map(|k| (IBig::ONE << 223) + IBig::from(k)),
        1 => (-80i64..=80).prop_map(|k| -(IBig::ONE << 223) + IBig::from(k)),
        1 => (0i64..=80).prop_map(|k| -(IBig::ONE << 255) + IBig::from(k)),
        1 => (0i64..=80).prop_map(|k| (IBig::ONE << 255) - IBig::ONE - IBig::from(k)),
    ]
    .boxed()
}

/// Every int256 exponent, weighted to the int32 ends and to int256's.
fn exponent256() -> BoxedStrategy<IBig> {
    prop_oneof![
        3 => exact::exponent().prop_map(IBig::from),
        1 => (-200i64..=200).prop_map(|k| IBig::from(I32_MAX as i64 + k)),
        1 => (-200i64..=200).prop_map(|k| IBig::from(I32_MIN as i64 + k)),
        1 => (0i64..=200).prop_map(|k| (IBig::ONE << 255) - IBig::ONE - IBig::from(k)),
        1 => (0i64..=200).prop_map(|k| -(IBig::ONE << 255) + IBig::from(k)),
        1 => int256(),
    ]
    .boxed()
}

// ------------------------------------------------------------ parse, format

/// A run of up to `max` digits, weighted to repeats and to zeros then nines.
fn digits(max: usize) -> BoxedStrategy<String> {
    prop_oneof![
        3 => proptest::collection::vec(0u8..=9, 1..=max),
        1 => (1usize..=max, 0u8..=9).prop_map(|(n, d)| vec![d; n]),
        1 => (0usize..=max.min(80), 1usize..=4).prop_map(|(z, n)| {
            let mut v = vec![0; z];
            v.extend(std::iter::repeat_n(9, n));
            v
        }),
    ]
    .prop_map(|v| {
        v.into_iter()
            .map(|d| char::from(b'0' + d))
            .collect::<String>()
    })
    .boxed()
}

/// An optional `-`, digits, optionally `.` and digits.
fn mantissa() -> BoxedStrategy<String> {
    (any::<bool>(), digits(90), proptest::option::of(digits(90)))
        .prop_map(|(neg, int, frac)| {
            let sign = if neg { "-" } else { "" };
            match frac {
                Some(f) => format!("{sign}{int}.{f}"),
                None => format!("{sign}{int}"),
            }
        })
        .boxed()
}

/// `e` or `E`, an optional sign, `zeros` leading zeros and `|e|`.
fn exponent_part(upper: bool, sign: u8, e: i64, zeros: usize) -> String {
    let mut s = String::from(if upper { 'E' } else { 'e' });
    match (sign, e < 0) {
        (_, true) => s.push('-'),
        (1, false) => s.push('+'),
        _ => {}
    }
    s.push_str(&"0".repeat(zeros));
    s.push_str(&e.unsigned_abs().to_string());
    s
}

/// A literal the parser documents as well formed: an optional `-`, digits,
/// optionally `.` and digits, optionally `e` or `E`, an optional sign and
/// digits. Every part may carry leading or trailing zeros, and the exponent
/// reaches past both int32 ends.
fn literal() -> BoxedStrategy<String> {
    let exp = prop_oneof![
        2 => -100i64..=100,
        2 => (-140i64..=140).prop_map(|k| I32_MAX as i64 + k),
        2 => (-140i64..=140).prop_map(|k| I32_MIN as i64 + k),
        1 => any::<i32>().prop_map(i64::from),
        1 => any::<i64>().prop_map(|e| e / 4),
    ];
    (
        mantissa(),
        proptest::option::of((any::<bool>(), 0u8..3, exp, 0usize..3)),
    )
        .prop_map(|(m, exp)| match exp {
            Some((upper, sign, e, zeros)) => m + &exponent_part(upper, sign, e, zeros),
            None => m,
        })
        .boxed()
}

/// What `parse` must return for an input, by how it is built.
#[derive(Debug, Clone, Copy)]
enum Shape {
    /// A literal alone: its value decides.
    WellFormed,
    /// A literal then a character that cannot continue it.
    Excess,
    /// No integer digits, a `.` without digits or an `e` without digits:
    /// the error's signature.
    Malformed(&'static str),
}

const DECIMAL_POINT: &str = "MalformedDecimalPoint(uint256)";
const EXPONENT_DIGITS: &str = "MalformedExponentDigits(uint256)";

/// Up to five characters after a first one drawn from `first`.
fn tail(first: &'static [u8]) -> BoxedStrategy<String> {
    let any_char = proptest::sample::select(b" x.eE+-_a09\t,".to_vec());
    (
        proptest::sample::select(first.to_vec()),
        proptest::collection::vec(any_char, 0..5),
    )
        .prop_map(|(f, rest)| {
            std::iter::once(f)
                .chain(rest)
                .map(char::from)
                .collect::<String>()
        })
        .boxed()
}

/// Inputs to `parse`: well formed literals; exponents past int256 of either
/// sign; malformed literals, each with its error; literals with characters
/// after them; and literals at the largest Float of each sign ± 4 units of
/// 10^int32.max, written at up to two lower exponents.
fn parse_input() -> BoxedStrategy<(String, Shape)> {
    let past_int256 = (
        mantissa(),
        any::<bool>(),
        0u8..3,
        any::<bool>(),
        1u8..=9,
        proptest::collection::vec(0u8..=9, 77..=90),
    )
        .prop_map(|(m, upper, sign, neg, first, rest)| {
            let mut s = m + if upper { "E" } else { "e" };
            match (sign, neg) {
                (_, true) => s.push('-'),
                (1, false) => s.push('+'),
                _ => {}
            }
            s.extend(
                std::iter::once(first)
                    .chain(rest)
                    .map(|d| char::from(b'0' + d)),
            );
            (s, Shape::WellFormed)
        });
    let sign = || prop_oneof![Just(""), Just("-")];
    fn end(first: &'static [u8]) -> impl Strategy<Value = String> {
        proptest::option::of(tail(first)).prop_map(Option::unwrap_or_default)
    }
    let empty = (sign(), end(b" x.eE+_a\t,")).prop_map(|(s, t)| {
        (
            format!("{s}{t}"),
            Shape::Malformed(PARSE_EMPTY_DECIMAL_STRING),
        )
    });
    let empty_after_minus = end(b" x.eE+-_a\t,").prop_map(|t| {
        (
            format!("-{t}"),
            Shape::Malformed(PARSE_EMPTY_DECIMAL_STRING),
        )
    });
    let point = (sign(), digits(20), end(b" x.eE+-_a\t,"))
        .prop_map(|(s, i, t)| (format!("{s}{i}.{t}"), Shape::Malformed(DECIMAL_POINT)));
    let exponent = (
        mantissa(),
        any::<bool>(),
        prop_oneof![Just(""), Just("+"), Just("-")],
    )
        .prop_flat_map(|(m, upper, sign)| {
            let first: &'static [u8] = if sign.is_empty() {
                b" x.eE_a\t,"
            } else {
                b" x.eE+-_a\t,"
            };
            end(first).prop_map(move |t| {
                (
                    format!("{m}{}{sign}{t}", if upper { "E" } else { "e" }),
                    Shape::Malformed(EXPONENT_DIGITS),
                )
            })
        });
    let excess = (literal(), tail(b" x+-_a\t,")).prop_map(|(l, t)| (l + &t, Shape::Excess));
    let largest = (any::<bool>(), -4i64..=4, 0usize..=2).prop_map(|(neg, k, shift)| {
        let c = cap(neg) + IBig::from(k);
        let sign = if neg { "-" } else { "" };
        (
            format!(
                "{sign}{c}{}e{}",
                "0".repeat(shift),
                I32_MAX - shift as isize
            ),
            Shape::WellFormed,
        )
    });
    prop_oneof![
        8 => literal().prop_map(|s| (s, Shape::WellFormed)),
        1 => past_int256,
        1 => empty,
        1 => empty_after_minus,
        1 => point,
        1 => exponent,
        2 => excess,
        2 => largest,
    ]
    .boxed()
}

/// The value of a well formed literal: dashu reads the mantissa and the
/// exponent is added. A zero literal is zero at any exponent; a non-zero one
/// whose exponent is past 2^40 is past or below every Float by that alone.
fn literal_value(s: &str) -> Result<D, RefError> {
    let (m, e) = match s.find(['e', 'E']) {
        Some(i) => (&s[..i], &s[i + 1..]),
        None => (s, "0"),
    };
    let m: D = m
        .parse()
        .unwrap_or_else(|err| panic!("dashu parse {m:?}: {err:?}"));
    let e: IBig = e.strip_prefix('+').unwrap_or(e).parse().unwrap();
    if m == D::ZERO {
        return Ok(D::ZERO);
    }
    let e = match isize::try_from(e.clone()) {
        Ok(e) if e.unsigned_abs() < 1 << 40 => e,
        _ if e > IBig::ZERO => return Err(RefError::ExponentOverflow),
        _ => return Err(RefError::ParseDecimalPrecisionLoss),
    };
    let v = D::from_parts(m.repr().significand().clone(), m.repr().exponent() + e);
    match toward_zero(&v) {
        Ok(w) if same(&w, &v) => Ok(v),
        Err(Range::Over) => Err(RefError::ExponentOverflow),
        _ => Err(RefError::ParseDecimalPrecisionLoss),
    }
}

/// `parse` returns every error by value, never a revert (#375, #510), with a
/// zero Float. A well formed literal is its exact value when that is a
/// Float, `ExponentOverflow` at or past (2^223 + 2) 10^int32.max in
/// magnitude, an exponent past int256 included, and
/// `ParseDecimalPrecisionLoss` for any other inexact value; with characters
/// after it, `ParseDecimalFloatExcessCharacters` whatever its value. A
/// malformed literal returns its own error, characters after it or not
/// (SPEC "Parsing", `parseDecimalFloat` NatSpec).
fn check_parse(s: &str, shape: Shape) -> Result<(), TestCaseError> {
    let case = format!("parse({s:?}) {shape:?}");
    let want: Result<D, [u8; 4]> = match shape {
        Shape::WellFormed => literal_value(s).map_err(RefError::selector),
        Shape::Excess => Err(RefError::ParseDecimalFloatExcessCharacters.selector()),
        Shape::Malformed(signature) => Err(selector(signature)),
    };
    let got = match evm::concrete(T::parseCall { str: s.to_string() }) {
        Ok(r) => r,
        Err(out) => {
            return Err(TestCaseError::fail(format!(
                "{case}: solidity reverted {out:?}, want {want:?} by value"
            )));
        }
    };
    match want {
        Ok(w) => {
            prop_assert_eq!(got._0.0, [0u8; 4], "{}: selector", case);
            let v = d(&Dec::from_bytes(got._1));
            prop_assert!(same(&v, &w), "{case}: solidity {v}, dashu {w}");
        }
        Err(w) => {
            prop_assert_eq!(got._0.0, w, "{}: selector", case);
            prop_assert_eq!(got._1, B256::ZERO, "{}: float on error", case);
        }
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
    let lead_ok = mantissa
        .as_bytes()
        .first()
        .is_some_and(|b| (b'1'..=b'9').contains(b));
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
/// `UnformatableExponent` with the canonical exponent, dashu's with trailing
/// zeros stripped, when that is past ±1000 (#496,
/// `MAX_NON_SCIENTIFIC_EXPONENT`); scientific notation leads with the first
/// significant digit and omits `e0`.
fn check_format(a: &Dec) -> Result<(), TestCaseError> {
    let x = d(a);
    for scientific in [false, true] {
        let case = format!("format({}, {scientific})", show(a));
        let got = evm::concrete(T::formatCall {
            a: a.to_bytes(),
            scientific,
        });
        if x == D::ZERO {
            prop_assert_eq!(got.ok(), Some("0".to_string()), "{}", case);
            continue;
        }
        let canonical = x.repr().exponent();
        if !scientific && canonical.abs() > 1000 {
            let mut want = RefError::UnformatableExponent.selector().to_vec();
            want.extend_from_slice(&I256::try_from(canonical).unwrap().to_be_bytes::<32>());
            prop_assert!(
                got.as_ref()
                    .is_err_and(|out| out.as_ref() == want.as_slice()),
                "{case}: solidity {got:?}, want UnformatableExponent({canonical})"
            );
            continue;
        }
        let s = match got {
            Ok(s) => s,
            Err(out) => return Err(TestCaseError::fail(format!("{case}: reverted {out:?}"))),
        };
        let shaped = if scientific {
            scientific_shape(&s)
        } else {
            plain_shape(&s)
        };
        prop_assert!(shaped, "{case}: shape of {s:?}");
        let back: D = s
            .parse()
            .unwrap_or_else(|e| panic!("dashu parse {s:?}: {e:?}"));
        prop_assert!(same(&back, &x), "{case}: {s:?} reads as {back}, not {x}");
    }
    Ok(())
}

// ------------------------------------------------------------ transcendentals

/// The exponent of the leading digit of a non-zero value.
fn lead(x: &D) -> isize {
    let r = x.repr();
    r.exponent() + r.digits() as isize - 1
}

/// |x|.
fn magnitude(x: &D) -> D {
    if *x < D::ZERO { -x.clone() } else { x.clone() }
}

/// The larger of two values.
fn max_of(x: D, y: D) -> D {
    if x > y { x } else { y }
}

/// The smaller of two values.
fn min_of(x: D, y: D) -> D {
    if x < y { x } else { y }
}

/// `k 10^-j` units in the 41st significant digit of a non-zero `x`.
fn ulp41(x: &D, k: u64, j: isize) -> D {
    D::from_parts(IBig::from(k), lead(x) - 40 - j)
}

/// |x - y|, rounded away from zero at 200 digits: never under the distance
/// between the two values given, and bound terms round toward zero, so this
/// arithmetic never loosens a check. The reference values themselves carry
/// dashu's truncation error, which a check inherits: `log10_of` under 1e-98
/// absolute (log10 of a coefficient under 1e68 at 100 digits); `ten_to` under
/// 1e-99 relative (10^f at 100 digits, f at 120); pow's under 3e-51 relative
/// (|b| at most 2e77, as |z| <= 2^33 and |log10 a| >= 4.3e-68, times
/// log10_of's 6e-129 at 130 digits). Each is at least ten orders under the
/// bound it meets.
fn distance(x: &D, y: &D) -> D {
    let s = Context::<Away>::new(200)
        .sub(x.repr(), y.repr())
        .unwrap()
        .value();
    magnitude(&s.with_rounding::<Zero>())
}

/// Sums and products of non-negative bound terms, rounded toward zero:
/// never over the exact bound.
fn bound_sum(x: &D, y: &D) -> D {
    rounded(Context::<Zero>::new(200).add(x.repr(), y.repr()).unwrap())
}

/// As `bound_sum`, for the product.
fn bound_mul(x: &D, y: &D) -> D {
    rounded(Context::<Zero>::new(200).mul(x.repr(), y.repr()).unwrap())
}

/// The smallest positive Float, 1e-2147483648: the absolute term the pow10
/// and pow bounds add for a true value below 1e-2147483608, and the
/// `ExponentUnderflow` threshold.
fn smallest() -> D {
    D::from_parts(IBig::ONE, I32_MIN)
}

/// Whether |t| is below 1e-2147483608, where the exponent floor sheds
/// digits from a 41-digit result.
fn sheds(t: &D) -> bool {
    magnitude(t) < D::from_parts(IBig::ONE, I32_MIN + 40)
}

/// Past 2^33 in magnitude, 10^y is past every Float either way, whatever
/// the pow bound's relative term.
fn huge() -> D {
    D::from_parts(IBig::ONE << 33, 0)
}

/// log10 of a positive value: log10 of its coefficient at `digits` digits,
/// plus its exponent, so the exponent never enters a logarithm.
fn log10_of(x: &D, digits: usize) -> D {
    let r = x.repr();
    let c = D::from_parts(r.significand().clone(), 0);
    let l = Context::<HalfAway>::new(digits)
        .log10(c.repr(), None)
        .unwrap()
        .value()
        .with_rounding::<Zero>();
    let e = D::from_parts(IBig::from(r.exponent()), 0);
    rounded(
        Context::<Zero>::new(digits + 20)
            .add(l.repr(), e.repr())
            .unwrap(),
    )
}

/// 10^y for |y| at most 2^33: 10^f at 100 digits, f = y - floor(y) at 120,
/// shifted by floor(y).
fn ten_to(y: &D) -> D {
    let n = y.floor();
    let f = rounded(Context::<Zero>::new(120).sub(y.repr(), n.repr()).unwrap());
    let n = isize::try_from(n.to_int().value()).unwrap();
    // 10^f - 1 is under 2.31 f, so below 1e-101 the 100-digit truncation
    // of 10^f is 1, and dashu is not asked to reach f's exponent.
    let p = if f < D::from_parts(IBig::ONE, -101) {
        D::ONE
    } else {
        let ten = D::from_parts(IBig::ONE, 1);
        Context::<HalfAway>::new(100)
            .powf(ten.repr(), f.repr(), None)
            .unwrap()
            .value()
            .with_rounding::<Zero>()
    };
    D::from_parts(p.repr().significand().clone(), p.repr().exponent() + n)
}

/// The true value a rounded transcendental is checked against.
enum Truth {
    /// `t`, and `top`, the largest magnitude the band reaches.
    Value { t: D, top: D },
    /// Past or below every Float: only a range error may result.
    Past,
    /// The band reaches from zero past every Float: any result of the sign
    /// may (#424's bound at rel >= 1).
    Anywhere,
}

/// What a rounded transcendental may return. `exact` demands `t` exactly,
/// `bound(r, t)` is the admissible |r - t| otherwise. `signed` demands a
/// non-zero result of the true value's sign, as a result below every Float
/// reverts. `over` and `under` are the range errors its band reaches, which
/// report `input` unpacked.
struct Band<'a, F: Fn(&D, &D) -> D> {
    truth: Truth,
    exact: bool,
    bound: F,
    negative: bool,
    signed: bool,
    over: bool,
    under: bool,
    input: &'a Dec,
}

/// The least magnitude whose 41-digit rounding, half away from zero, is past
/// the largest Float of the sign: the midpoint above its first 41 digits.
/// Its 68-digit coefficient keeps 41 digits above 10^27.
fn carry_threshold(negative: bool) -> D {
    let head = cap(negative) / IBig::from(10).pow(27);
    D::from_parts(head * IBig::from(10) + IBig::from(5), I32_MAX + 26)
}

/// A rounding past the largest Float is instead truncated to int224 (SPEC
/// "pow"): the result is over 41 digits only when the band reaches the
/// carry threshold and the result is within one unit of 10^int32.max below
/// it, the truncation of a value at or past it.
fn truncated_from_past(r: &D, top: Option<&D>, negative: bool) -> bool {
    let carry = carry_threshold(negative);
    let c = carry.repr();
    let floor = D::from_parts(
        c.significand() * IBig::from(10).pow((c.exponent() - I32_MAX) as usize) - IBig::ONE,
        I32_MAX,
    );
    top.is_none_or(|t| *t >= carry) && magnitude(r) >= floor
}

/// The Solidity result against its `Band`: the truth exactly or within
/// `bound` of it, of its sign where `signed`, at most 41 digits unless
/// truncated from past the largest Float; or an allowed range error
/// reporting `input`.
fn check_band<F: Fn(&D, &D) -> D>(
    case: &str,
    sol: Sol<Dec>,
    band: Band<F>,
) -> Result<(), TestCaseError> {
    match sol {
        Ok(r) => {
            let r = d(&r);
            let top = match &band.truth {
                Truth::Past => {
                    return Err(TestCaseError::fail(format!(
                        "{case}: solidity {r}, dashu past every Float"
                    )));
                }
                Truth::Anywhere => None,
                Truth::Value { t, top } => {
                    if band.exact {
                        prop_assert!(same(&r, t), "{case}: solidity {r}, exact {t}");
                    } else {
                        let b = (band.bound)(&r, t);
                        let gap = distance(&r, t);
                        prop_assert!(
                            gap <= b,
                            "{case}: solidity {r}, dashu {t}, |r - t| {gap} past {b}"
                        );
                    }
                    Some(top)
                }
            };
            if band.signed {
                prop_assert!(
                    r != D::ZERO && (r < D::ZERO) == band.negative,
                    "{case}: solidity {r}, true value negative {}",
                    band.negative
                );
            }
            // Rounded at 41 significant digits, but for a rounding past the
            // largest Float, truncated to int224.
            prop_assert!(
                r.repr().digits() <= 41 || truncated_from_past(&r, top, band.negative),
                "{case}: {r} has over 41 digits"
            );
        }
        Err(f) => {
            let hit = [
                (band.over, RefError::ExponentOverflow),
                (band.under, RefError::ExponentUnderflow),
            ]
            .into_iter()
            .find(|(ok, e)| *ok && error_matches(&f, *e));
            let Some((_, e)) = hit else {
                return Err(TestCaseError::fail(format!(
                    "{case}: solidity {f:?}, dashu {} (overflow allowed {}, underflow allowed {})",
                    match &band.truth {
                        Truth::Value { t, .. } => t.to_string(),
                        Truth::Past => "past every Float".into(),
                        Truth::Anywhere => "anywhere".into(),
                    },
                    band.over,
                    band.under
                )));
            };
            if let Fail::Revert(out) = &f {
                let data = revert_data(e, band.input, None);
                prop_assert_eq!(out.as_ref(), data.as_slice(), "{}: revert data", case);
            }
        }
    }
    Ok(())
}

/// Range errors for a true magnitude `t` within relative `rel` (plus the
/// absolute term below 1e-2147483608): overflow when the band reaches past
/// the largest Float of the sign, underflow when it reaches below the
/// smallest.
fn reach(t: &D, rel: &D, negative: bool) -> (D, D, bool, bool) {
    let mut tb = bound_mul(t, rel);
    if sheds(t) {
        tb = bound_sum(&tb, &smallest());
    }
    let hi = rounded(Context::<Zero>::new(200).add(t.repr(), tb.repr()).unwrap());
    let lo = Context::<Away>::new(200)
        .sub(t.repr(), tb.repr())
        .unwrap()
        .value()
        .with_rounding::<Zero>();
    let (over, under) = (hi > largest_float(negative), lo < smallest());
    (tb, hi, over, under)
}

/// The root of a non-negative value correctly rounded to nearest at 41
/// digits, half away from zero: the 100-digit truncated root rounded once.
/// dashu's own 41-digit root is not used: it rounds sqrt(1 - 1e-41) up to 1.
/// For a 67-digit coefficient a, |a - t^2| for a 42-digit tie t is at least
/// one unit of t^2's last digit, so the root is at least about 1e-84
/// relative from every tie, past the 1e-99 the truncation moves it.
fn want_sqrt(x: &D) -> D {
    let s = Context::<Zero>::new(100).sqrt(x.repr()).unwrap().value();
    s.with_rounding::<HalfAway>()
        .with_precision(41)
        .value()
        .with_rounding::<Zero>()
}

/// sqrt is correctly rounded to nearest at 41 digits (NatSpec). Negative
/// reverts `PowNegativeBase(a)`.
fn check_sqrt(a: &Dec) -> Result<(), TestCaseError> {
    let x = d(a);
    let case = format!("sqrt({})", show(a));
    let sol = sol_float(T::sqrtCall { a: a.to_bytes() });
    if x < D::ZERO {
        return check(&case, sol, Err(RefError::PowNegativeBase), Some(a));
    }
    let want = want_sqrt(&x);
    check(&case, sol, Ok(want), None)
}

/// gm (NatSpec): `FLOAT_ZERO` for a zero input; otherwise negative iff
/// exactly one input is, between |a| and |b| in magnitude (the lesser as it
/// packs toward zero), within half a unit in its 41st digit plus 6e-76
/// relative of sqrt(|a b|), plus 1e-2147483648 below 1e-2147483608, and at
/// most 41 digits unless clamped to |a| or |b|. Never reverts.
fn check_gm(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    let (fa, fb) = bin(a, b);
    let case = format!("gm({}, {})", show(a), show(b));
    let r = match sol_float(T::gmCall { a: fa, b: fb }) {
        Ok(r) => r,
        Err(f) => return Err(TestCaseError::fail(format!("{case}: solidity {f:?}"))),
    };
    if a.is_zero() || b.is_zero() {
        prop_assert_eq!(r.to_bytes(), B256::ZERO, "{}: not FLOAT_ZERO", case);
        return Ok(());
    }
    let r = d(&r);
    let negative = a.is_negative() != b.is_negative();
    prop_assert!(
        r != D::ZERO && (r < D::ZERO) == negative,
        "{case}: solidity {r}, negative {negative}"
    );
    let m = magnitude(&r);
    let (x, y) = (magnitude(&d(a)), magnitude(&d(b)));
    let hi = max_of(x.clone(), y.clone());
    let lo = toward_zero(&min_of(x, y)).unwrap();
    prop_assert!(
        m <= hi && m >= lo,
        "{case}: solidity {r} outside [{lo}, {hi}]"
    );
    let t = Context::<Zero>::new(100)
        .sqrt(magnitude(&exact_mul(a, b)).repr())
        .unwrap()
        .value();
    let mut bound = bound_sum(
        &ulp41(&m, 5, 1),
        &bound_mul(&t, &D::from_parts(IBig::from(6), -76)),
    );
    if sheds(&t) {
        bound = bound_sum(&bound, &smallest());
    }
    let gap = distance(&m, &t);
    prop_assert!(
        gap <= bound,
        "{case}: solidity {r}, dashu {t}, |r - t| {gap} past {bound}"
    );
    prop_assert!(
        m.repr().digits() <= 41 || same(&m, &hi) || same(&m, &lo),
        "{case}: {r} has over 41 digits"
    );
    Ok(())
}

/// gm's inputs: `pair`; both at the top, both at the bottom, or one at each
/// end of the exponent range, so the product is past every Float; and a value
/// with a neighbour or its negation, where the clamp acts.
fn gm_input() -> BoxedStrategy<(Dec, Dec)> {
    let top = || {
        (exact::coefficient(), I32_MAX as i64 - 80..=I32_MAX as i64)
            .prop_map(|(c, e)| Dec::new(c, e))
    };
    let bottom = || {
        (exact::coefficient(), I32_MIN as i64..=I32_MIN as i64 + 80)
            .prop_map(|(c, e)| Dec::new(c, e))
    };
    prop_oneof![
        3 => pair(),
        1 => (top(), top()),
        1 => (bottom(), bottom()),
        1 => (top(), bottom()),
        1 => (exact::float(), -1i64..=1, any::<bool>()).prop_map(|(a, k, neg)| {
            let c = (&a.c + k).clamp(r::int224_min(), r::int224_max());
            let c = if neg && r::fits_int224(&-&c) { -c } else { c };
            let e = a.e;
            (a, Dec::new(c, e))
        }),
    ]
    .boxed()
}

/// log10 within half a unit in the 41st digit plus 1.0037e-50 absolute,
/// at most 41 digits, exact for a power of ten; zero reverts `Log10Zero`,
/// negative `Log10Negative(a)` (NatSpec, README).
fn check_log10(a: &Dec) -> Result<(), TestCaseError> {
    check_log10_with(a, sol_float(T::log10Call { a: a.to_bytes() }))
}

/// The half unit is of the result's 41st digit: a rounding to nearest is
/// within half the spacing above its result's leading digit.
fn check_log10_with(a: &Dec, sol: Sol<Dec>) -> Result<(), TestCaseError> {
    let x = d(a);
    let case = format!("log10({})", show(a));
    if x == D::ZERO {
        return check(&case, sol, Err(RefError::Log10Zero), Some(a));
    }
    if x < D::ZERO {
        return check(&case, sol, Err(RefError::Log10Negative), Some(a));
    }
    let t = log10_of(&x, 100);
    let band = Band {
        exact: x.repr().significand() == &IBig::ONE,
        truth: Truth::Value {
            top: magnitude(&t),
            t: t.clone(),
        },
        bound: |r: &D, _: &D| {
            let abs = D::from_parts(IBig::from(10037), -54);
            if *r == D::ZERO {
                abs
            } else {
                bound_sum(&ulp41(&magnitude(r), 5, 1), &abs)
            }
        },
        negative: t < D::ZERO,
        signed: false,
        over: false,
        under: false,
        input: a,
    };
    check_band(&case, sol, band)
}

/// 10^x within 0.5000000112 units in the 41st digit, plus 1e-2147483648
/// below 1e-2147483608; exactly 10^k for integer k; under 1e-2147483648
/// `ExponentUnderflow(x)`, past the largest Float `ExponentOverflow(x)`,
/// either allowed where the 5.00000012e-41 relative band reaches the
/// threshold (NatSpec, README).
fn check_pow10(a: &Dec) -> Result<(), TestCaseError> {
    check_pow10_with(a, sol_float(T::pow10Call { a: a.to_bytes() }))
}

/// The unit is of the smaller of the result and the true value: rounding
/// to nearest across a power of ten is within half the spacing below it,
/// and the 1.12e-8 units of raw error are of the true value's digit.
fn check_pow10_with(a: &Dec, sol: Sol<Dec>) -> Result<(), TestCaseError> {
    let x = d(a);
    let case = format!("pow10({})", show(a));
    let value = |r: &D, t: &D| {
        let m = if *r == D::ZERO {
            t.clone()
        } else {
            min_of(magnitude(r), t.clone())
        };
        let b = ulp41(&m, 5000000112, 10);
        if sheds(t) {
            bound_sum(&b, &smallest())
        } else {
            b
        }
    };
    if magnitude(&x) > huge() {
        let rising = x > D::ZERO;
        let band = Band {
            truth: Truth::Past,
            exact: false,
            bound: value,
            negative: false,
            signed: true,
            over: rising,
            under: !rising,
            input: a,
        };
        return check_band(&case, sol, band);
    }
    let t = ten_to(&x);
    let exact = same(&x.trunc(), &x);
    let (top, over, under) = if exact {
        (t.clone(), t > largest_float(false), t < smallest())
    } else {
        let (_, hi, over, under) = reach(&t, &D::from_parts(IBig::from(500000012), -49), false);
        (hi, over, under)
    };
    check_band(
        &case,
        sol,
        Band {
            truth: Truth::Value { t, top },
            exact,
            bound: value,
            negative: false,
            signed: true,
            over,
            under,
            input: a,
        },
    )
}

/// The true a^b when it has at most 41 significant digits, for b = p/q in
/// lowest terms with |p| <= 2000 and q <= 1000: the 41-digit rounding of
/// the approximation `t`, kept only when its q-th power is exactly a^p.
fn exact_power(a: &D, b: &D, t: &D) -> Option<D> {
    if magnitude(b) > D::from_parts(IBig::from(1000), 0) || t == &D::ZERO {
        return None;
    }
    let r = b.repr();
    if r.exponent() < -12 {
        return None;
    }
    let (p, q) = if r.exponent() >= 0 {
        (
            r.significand() * IBig::from(10).pow(r.exponent() as usize),
            IBig::ONE,
        )
    } else {
        let den = IBig::from(10).pow((-r.exponent()) as usize);
        let g: IBig = dashu_base::Gcd::gcd(r.significand(), &den).into();
        (r.significand() / &g, den / g)
    };
    let q = usize::try_from(q).ok().filter(|q| *q <= 1000)?;
    let p = isize::try_from(p)
        .ok()
        .filter(|p| p.unsigned_abs() <= 2000)?;
    let g = t
        .clone()
        .with_rounding::<HalfAway>()
        .with_precision(41)
        .value()
        .with_rounding::<Zero>();
    let pow = |x: &D, k: usize| {
        let r = x.repr();
        D::from_parts(r.significand().pow(k), r.exponent() * k as isize)
    };
    let gq = pow(&g, q);
    let ap = pow(a, p.unsigned_abs());
    let holds = if p > 0 {
        same(&gq, &ap)
    } else {
        same(
            &rounded(Context::<Zero>::new(0).mul(gq.repr(), ap.repr()).unwrap()),
            &D::ONE,
        )
    };
    holds.then_some(g)
}

/// pow's d = max(|a|, 1/|a|) - 1, rounded toward zero, so the bound it
/// enters is never over the stated one. 1/|a| - 1 is taken as
/// (1 - |a|) / |a|: each step rounds relative to its own result, so a d
/// near 1e-66 keeps its digits.
fn distance_from_one(ax: &D) -> D {
    let one = D::ONE;
    let ctx = Context::<Zero>::new(60);
    if *ax > one {
        rounded(ctx.sub(ax.repr(), one.repr()).unwrap())
    } else {
        let gap = rounded(ctx.sub(one.repr(), ax.repr()).unwrap());
        rounded(ctx.div(gap.repr(), ax.repr()).unwrap())
    }
}

/// pow (NatSpec, README): `0^0 = 1`, `a^0 = 1`, `0^b = 0` for b > 0 and
/// `ZeroNegativePower(b)` for b < 0 (SPEC "pow", #86). A negative a needs a
/// whole b and takes its sign when b is odd, else `PowNegativeBase(a)`;
/// |a| = 1 is exact. Otherwise within 5.00000012e-41 + N min(K1, K2 d)
/// relative of the true value, N = floor|b|, d = max(|a|, 1/|a|) - 1, plus
/// 1e-2147483648 below 1e-2147483608; exact when the true value has at most
/// 41 digits, `10^(k b)` for |a| = 10^k and k b whole included at any b;
/// range errors report a, either allowed where the band reaches the
/// threshold. A non-zero true value never results in zero or the wrong sign:
/// below every Float reverts.
fn check_pow(a: &Dec, b: &Dec) -> Result<(), TestCaseError> {
    check_pow_with(
        a,
        b,
        sol_float(T::powCall {
            a: a.to_bytes(),
            b: b.to_bytes(),
        }),
    )
}

/// `check_pow` on a result already obtained.
fn check_pow_with(a: &Dec, b: &Dec, sol: Sol<Dec>) -> Result<(), TestCaseError> {
    let (x, y) = (d(a), d(b));
    let case = format!("pow({}, {})", show(a), show(b));
    if y == D::ZERO {
        return check(&case, sol, Ok(D::ONE), None);
    }
    if x == D::ZERO {
        if y > D::ZERO {
            return check(&case, sol, Ok(D::ZERO), None);
        }
        let want = RefError::ZeroNegativePower;
        match &sol {
            Err(f @ Fail::Revert(out)) => {
                prop_assert!(
                    error_matches(f, want),
                    "{case}: solidity {f:?}, dashu {want:?}"
                );
                let data = revert_data(want, a, Some(b));
                prop_assert_eq!(out.as_ref(), data.as_slice(), "{}: revert data", case);
            }
            s => prop_assert!(false, "{case}: solidity {s:?}, dashu {want:?}"),
        }
        return Ok(());
    }
    let whole = same(&y.trunc(), &y);
    if x < D::ZERO && !whole {
        return check(&case, sol, Err(RefError::PowNegativeBase), Some(a));
    }
    let negative = x < D::ZERO && odd(&y);
    let sign = |v: D| if negative { -v } else { v };
    let ax = magnitude(&x);
    if ax == D::ONE {
        return check(&case, sol, Ok(sign(D::ONE)), None);
    }
    let range = |rising: bool, truth: Truth| Band {
        truth,
        exact: false,
        bound: |_: &D, _: &D| D::ZERO,
        negative,
        signed: true,
        over: rising,
        under: !rising,
        input: a,
    };
    if ax.repr().significand() == &IBig::ONE {
        // |a| = 10^k: k b whole is 10^(k b) exactly. Past 1e12, |k b| is
        // past every Float whatever its fraction; under it, a whole k b is
        // an exponent dashu holds.
        let k = D::from_parts(IBig::from(ax.repr().exponent()), 0);
        let rising = (k > D::ZERO) == (y > D::ZERO);
        let kb = rounded(Context::<Zero>::new(0).mul(k.repr(), y.repr()).unwrap());
        if lead(&kb) >= 12 {
            return check_band(&case, sol, range(rising, Truth::Past));
        }
        if same(&kb.trunc(), &kb) {
            let n = isize::try_from(kb.to_int().value()).unwrap();
            let e = D::from_parts(IBig::ONE, n);
            let band = Band {
                truth: Truth::Value {
                    t: sign(e.clone()),
                    top: e.clone(),
                },
                exact: true,
                bound: |_: &D, _: &D| D::ZERO,
                negative,
                signed: true,
                over: e > largest_float(negative),
                under: e < smallest(),
                input: a,
            };
            return check_band(&case, sol, band);
        }
    }
    let z = rounded(
        Context::<Zero>::new(120)
            .mul(y.repr(), log10_of(&ax, 130).repr())
            .unwrap(),
    );
    let dd = distance_from_one(&ax);
    let (k1, k2) = if y > D::ZERO {
        (
            D::from_parts(IBig::from(17273), -80),
            D::from_parts(IBig::from(15), -39),
        )
    } else {
        (
            D::from_parts(IBig::from(11728), -79),
            D::from_parts(IBig::from(34786), -42),
        )
    };
    let k2d = bound_mul(&k2, &dd);
    let n = magnitude(&y).trunc();
    let rel = bound_sum(
        &D::from_parts(IBig::from(500000012), -49),
        &bound_mul(&n, if k1 < k2d { &k1 } else { &k2d }),
    );
    if magnitude(&z) > huge() {
        let rising = z > D::ZERO;
        let truth = if rising && rel >= D::ONE {
            Truth::Anywhere
        } else {
            Truth::Past
        };
        return check_band(&case, sol, range(rising, truth));
    }
    let t = ten_to(&z);
    if let Some(e) = exact_power(&ax, &y, &t) {
        let (over, under) = (e > largest_float(negative), e < smallest());
        let band = Band {
            truth: Truth::Value {
                t: sign(e.clone()),
                top: e,
            },
            exact: true,
            bound: |_: &D, _: &D| D::ZERO,
            negative,
            signed: true,
            over,
            under,
            input: a,
        };
        return check_band(&case, sol, band);
    }
    let (tb, top, over, under) = reach(&t, &rel, negative);
    let band = Band {
        truth: Truth::Value { t: sign(t), top },
        exact: false,
        bound: move |_: &D, _: &D| tb.clone(),
        negative,
        signed: true,
        over,
        under,
        input: a,
    };
    check_band(&case, sol, band)
}

/// A 67-digit coefficient a with |a - t^2| at most one unit of t^2's last
/// kept digit, t a 42-digit tie (41 digits then 5): roots as near a 41-digit
/// rounding tie as a Float allows.
fn sqrt_near_tie() -> BoxedStrategy<Dec> {
    (any::<[u8; 18]>(), any::<bool>(), -1000i64..1000)
        .prop_map(|(b, up, e)| {
            let ten = dashu_int::UBig::from(10u8);
            let t = (dashu_int::UBig::from_be_bytes(&b) % ten.pow(40) + ten.pow(40)) * &ten
                + dashu_int::UBig::from(5u8);
            let sq = &t * &t;
            let cut = sq.to_string().len() - 67;
            let a = &sq / ten.pow(cut)
                + if up {
                    dashu_int::UBig::ONE
                } else {
                    dashu_int::UBig::ZERO
                };
            Dec::new(
                a.to_string().parse::<num_bigint::BigInt>().unwrap(),
                e * 2 + cut as i64,
            )
        })
        .boxed()
}

/// sqrt's inputs: `a_sqrt`, and roots near a 41-digit rounding tie.
fn sqrt_input() -> BoxedStrategy<Dec> {
    prop_oneof![3 => transcendental::a_sqrt(), 1 => sqrt_near_tie()].boxed()
}

/// Floats whose canonical exponent, trailing zeros stripped, sits at the
/// plain notation cap of ±1000 and across ±1100 (#496).
fn format_input() -> BoxedStrategy<Dec> {
    let near_cap = (
        exact::coefficient(),
        prop_oneof![-1003i64..=-995, 995i64..=1003, -1100i64..=1100],
    )
        .prop_map(|(c, canonical)| {
            let s = c.to_string();
            let zeros = (s.len() - s.trim_end_matches('0').len()) as i64;
            Dec::new(c, canonical - zeros)
        });
    prop_oneof![2 => exact::float(), 1 => near_cap].boxed()
}

/// A dashu value as a Float's fields: its stripped coefficient, lifted back
/// to int32.max where stripping took the exponent past it.
fn to_dec(x: &D) -> Dec {
    let r = x.repr();
    let mut c: num_bigint::BigInt = r.significand().to_string().parse().unwrap();
    let mut e = r.exponent();
    while e > I32_MAX {
        c *= 10;
        e -= 1;
    }
    Dec::new(c, e as i64)
}

/// `agree` (NatSpec, SPEC "agree"): a negative tolerance reverts
/// `AgreeToleranceNegative(absolute, proportional)` and neither positive
/// `AgreeNoPositiveTolerance(absolute, proportional)`. Otherwise it is
/// `|x - y| <= max(absolute, proportional × max(|x|, |y|))` with the
/// extremes in either order, but that a spread past the limit by under
/// 1.7273e-76 of the spread may be accepted, the spread being a truncating
/// `sub`.
/// dashu bounds the spread at 200 digits each way; within that of the
/// boundary either answer passes.
///
/// What `agree` must answer: an error, or `Some` answer, or `None` where
/// either is allowed.
fn want_agree(
    absolute: &Dec,
    proportional: &Dec,
    x: &Dec,
    y: &Dec,
) -> Result<Option<bool>, RefError> {
    let (ta, tp) = (d(absolute), d(proportional));
    if ta < D::ZERO || tp < D::ZERO {
        return Err(RefError::AgreeToleranceNegative);
    }
    if ta == D::ZERO && tp == D::ZERO {
        return Err(RefError::AgreeNoPositiveTolerance);
    }
    let (dx, dy) = (d(x), d(y));
    let spread_hi = distance(&dx, &dy);
    let spread_lo = magnitude(&rounded(
        Context::<Zero>::new(200).sub(dx.repr(), dy.repr()).unwrap(),
    ));
    let anchor = max_of(magnitude(&dx), magnitude(&dy));
    let scaled = rounded(
        Context::<Zero>::new(0)
            .mul(tp.repr(), anchor.repr())
            .unwrap(),
    );
    let limit = max_of(ta, scaled);
    let within = D::from_parts(IBig::from(10).pow(80) - IBig::from(17_273), -80);
    Ok(if spread_hi <= limit {
        Some(true)
    } else if bound_mul(&spread_lo, &within) >= limit {
        Some(false)
    } else {
        None
    })
}

/// `agree` against `want_agree`, the extremes in both orders; a revert
/// carries both tolerances.
fn check_agree(absolute: &Dec, proportional: &Dec, x: &Dec, y: &Dec) -> Result<(), TestCaseError> {
    let (fa, fp) = (absolute.to_bytes(), proportional.to_bytes());
    let want = want_agree(absolute, proportional, x, y);
    for (lowest, highest) in [(x, y), (y, x)] {
        let case = format!(
            "agree({}, {}, {}, {})",
            show(absolute),
            show(proportional),
            show(lowest),
            show(highest)
        );
        let got = evm::harness(H::agreeCall {
            absolute: fa,
            proportional: fp,
            lowest: lowest.to_bytes(),
            highest: highest.to_bytes(),
        });
        match (got, want) {
            (Err(out), Err(e)) => prop_assert_eq!(
                out.to_vec(),
                revert_with(e, &[fa.0, fp.0]),
                "{}: revert data, want {:?}",
                case,
                e
            ),
            (Ok(g), Ok(w)) => prop_assert!(
                w.is_none_or(|w| w == g),
                "{case}: solidity {g}, dashu {w:?}"
            ),
            (g, w) => prop_assert!(false, "{case}: solidity {g:?}, dashu {w:?}"),
        }
    }
    Ok(())
}

/// A tolerance: mostly non-negative, sometimes zero at any exponent, sometimes
/// any Float.
fn tolerance() -> BoxedStrategy<Dec> {
    let non_negative = exact::float().prop_map(|f| {
        if f.c < num_bigint::BigInt::from(0) {
            let c = -f.c;
            let max = r::int224_max();
            Dec::new(if c > max { max } else { c }, f.e)
        } else {
            f
        }
    });
    prop_oneof![
        3 => non_negative,
        1 => exact::exponent().prop_map(|e| Dec::new(0, e)),
        1 => exact::float(),
        1 => (1u32..=1000, -80i64..=2).prop_map(|(c, e)| Dec::new(c, e)),
    ]
    .boxed()
}

/// Tolerances and extremes: at random, and with one tolerance zero and the
/// other on the spread as `sub` gives it (absolute) or on the spread over
/// the anchor as `div` gives it (proportional), nudged by -1..=1 in its last
/// digit.
fn agree_input() -> BoxedStrategy<(Dec, Dec, Dec, Dec)> {
    let nudge = |v: &D, k: i64| {
        let f = to_dec(v);
        let c = f.c + k;
        let max = r::int224_max();
        (c >= num_bigint::BigInt::from(0) && c <= max).then(|| Dec::new(c, f.e))
    };
    let on_absolute =
        (pair(), -1i64..=1).prop_filter_map("spread past every Float", move |((x, y), k)| {
            let s = magnitude(&want_sub(&y, &x).ok()?);
            Some((nudge(&s, k)?, Dec::zero(), x, y))
        });
    let on_proportional =
        (pair(), -1i64..=1).prop_filter_map("spread or ratio not a Float", move |((x, y), k)| {
            let s = to_dec(&magnitude(&want_sub(&y, &x).ok()?));
            let anchor = to_dec(&max_of(magnitude(&d(&x)), magnitude(&d(&y))));
            let p = want_div(&s, &anchor).ok()?;
            Some((Dec::zero(), nudge(&p, k)?, x, y))
        });
    prop_oneof![
        2 => (tolerance(), tolerance(), pair()).prop_map(|(a, p, (x, y))| (a, p, x, y)),
        1 => on_absolute,
        1 => on_proportional,
    ]
    .boxed()
}

proptest! {
    #![proptest_config(config())]

    #[test]
    fn differential_sqrt(a in sqrt_input()) { check_sqrt(&a)?; }

    #[test]
    fn differential_gm((a, b) in gm_input()) { check_gm(&a, &b)?; }

    #[test]
    fn differential_log10(a in transcendental::a_log10()) { check_log10(&a)?; }

    #[test]
    fn differential_pow10(x in transcendental::x_pow10()) { check_pow10(&x)?; }

    #[test]
    fn differential_pow((a, b) in transcendental::pow_pair()) { check_pow(&a, &b)?; }

    #[test]
    fn differential_pow_near_one((a, b) in transcendental::near_one()) { check_pow(&a, &b)?; }
}

proptest! {
    #![proptest_config(config())]

    #[test]
    fn differential_parse((s, shape) in parse_input()) { check_parse(&s, shape)?; }

    #[test]
    fn differential_format(a in format_input()) { check_format(&a)?; }
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

    #[test]
    fn differential_agree((absolute, proportional, x, y) in agree_input()) {
        check_agree(&absolute, &proportional, &x, &y)?;
    }
}

/// pow of 10^k at a b under 1e12 whose k b is whole and past isize, the
/// inputs the fuzz reaches rarely: the Solidity against the oracle at each.
#[test]
fn differential_pow_power_of_ten_past_isize() {
    let cases = [
        (Dec::new(1, 92233721), Dec::new(9999999999i64, 1)),
        (Dec::new(1, 92233721), Dec::new(pow10(57), -46)),
        (Dec::new(1, 153722868), Dec::new(6, 10)),
        (Dec::new(1, -92233721), Dec::new(9999999999i64, 1)),
        (Dec::new(-1, 92233721), Dec::new(99999999991i64, 0)),
    ];
    for (a, b) in cases {
        if let Err(err) = check_pow(&a, &b) {
            panic!("{err}");
        }
    }
}

/// The oracle on fixed examples whose values are the README's and #333's,
/// so a misconfigured dashu context fails here and not only under fuzz.
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
        let b = Dec::new(pow10(33) + 1, 0);
        assert!(same(&want_sub(&Dec::new(1, 100), &b).unwrap(), &want));
        assert!(same(
            &want_sub(&Dec::new(1, 100), &Dec::new(17, 32)).unwrap(),
            &want
        ));
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
        let big: num_bigint::BigInt = pow10(66) * 13 + 7;
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
        assert!(same(
            &toward_zero(&two223).unwrap(),
            &D::from_parts(int224_max(), 5)
        ));
        assert!(same(
            &toward_zero(&-two223.clone()).unwrap(),
            &-two223.clone()
        ));
        let past = D::from_parts(-(IBig::ONE << 223) - IBig::ONE, 5);
        assert!(same(&toward_zero(&past).unwrap(), &-two223.clone()));
        // Overflow starts at (2^223 + 2) 10^int32.max (#433, revertIfPastLargestFloat).
        let edge = (IBig::ONE << 223) + IBig::from(2);
        assert_eq!(
            toward_zero(&D::from_parts(edge.clone(), I32_MAX)),
            Err(Range::Over)
        );
        assert_eq!(
            toward_zero(&D::from_parts(-edge.clone(), I32_MAX)),
            Err(Range::Over)
        );
        let below = D::from_parts(edge.clone() * IBig::from(10) - IBig::ONE, I32_MAX - 1);
        assert!(same(&toward_zero(&below).unwrap(), &largest_float(false)));
        assert!(same(&toward_zero(&-below).unwrap(), &-largest_float(true)));
        // Below 1e-2147483648 nothing non-zero is left.
        assert_eq!(
            toward_zero(&D::from_parts(IBig::from(9), I32_MIN - 1)),
            Err(Range::Under)
        );
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
        assert!(
            plain_shape("-0.5") && plain_shape("120") && !plain_shape("1.50") && !plain_shape("01")
        );
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
        assert!(same(
            &w,
            &-D::from_parts(nines(67) * IBig::from(2) / IBig::from(3), -67)
        ));
        assert_eq!(
            want_div(&Dec::new(1, 0), &Dec::zero()),
            Err(RefError::DivisionByZero)
        );
    }

    /// The transcendental oracle against published constants: sqrt 2, log10 2
    /// and sqrt 10 to 50 places.
    #[test]
    fn transcendental_constants() {
        // sqrt(1 - 1e-41) is 1 - 5e-42 - 1.25e-83 - ..., below the midpoint
        // 1 - 5e-42 of 41 nines and 1.
        let below_one = D::from_parts(nines(41), -41);
        assert!(same(&want_sqrt(&below_one), &below_one));
        let root2 = want_sqrt(&dec("2"));
        assert!(same(
            &root2,
            &dec("1.4142135623730950488016887242096980785697")
        ));
        let within = |x: &D, s: &str| distance(x, &dec(s)) < dec("1e-49");
        assert!(within(
            &log10_of(&dec("2"), 100),
            "0.30102999566398119521373889472449302676818988146211"
        ));
        assert!(within(
            &log10_of(&dec("2e-5"), 100),
            "-4.69897000433601880478626110527550697323181011853789"
        ));
        assert!(within(
            &ten_to(&dec("0.5")),
            "3.16227766016837933199889354443271853371955513932521"
        ));
        assert!(within(
            &ten_to(&dec("-1.5")),
            "0.0316227766016837933199889354443271853371955513932521"
        ));
        assert!(same(&log10_of(&dec("1000"), 100), &dec("3")));
        assert!(same(&ten_to(&dec("-7")), &dec("1e-7")));
    }

    /// The oracle's checks of a power-of-ten log10 and of 41 digits read
    /// dashu's coefficient with its trailing zeros removed.
    #[test]
    fn coefficients_are_stripped() {
        assert_eq!(
            D::from_parts(IBig::from(1000), 4).repr().significand(),
            &IBig::ONE
        );
        assert_eq!(D::from_parts(IBig::from(1200), 0).repr().digits(), 2);
    }

    /// Exact powers come from the 41-digit candidate only when its power is
    /// exactly a^p.
    #[test]
    fn exact_powers() {
        let t = |a: &D, b: &D| {
            ten_to(&rounded(
                Context::<Zero>::new(120)
                    .mul(b.repr(), log10_of(a, 130).repr())
                    .unwrap(),
            ))
        };
        let (a, b) = (dec("4"), dec("0.5"));
        assert!(same(&exact_power(&a, &b, &t(&a, &b)).unwrap(), &dec("2")));
        let (a, b) = (
            dec("0.008"),
            dec("-0.3333333333333333333333333333333333333333"),
        );
        assert!(exact_power(&a, &b, &t(&a, &b)).is_none());
        let (a, b) = (dec("1.5"), dec("-3"));
        assert!(exact_power(&a, &b, &t(&a, &b)).is_none());
        let (a, b) = (dec("2"), dec("-3"));
        assert!(same(
            &exact_power(&a, &b, &t(&a, &b)).unwrap(),
            &dec("0.125")
        ));
        let (a, b) = (dec("3"), dec("100"));
        assert!(exact_power(&a, &b, &t(&a, &b)).is_none());
    }

    /// d for a within 1e-66 of one either side: 1e-66 above, and
    /// 1/(1 - 1e-66) - 1 = 1e-66 / (1 - 1e-66) below, just over 1e-66.
    #[test]
    fn distance_near_one() {
        let below = distance_from_one(&D::from_parts(nines(66), -66));
        // 1e-66 + 1e-132 + ..., truncated at 60 digits.
        assert!(same(&below, &dec("1e-66")));
        assert!(same(
            &distance_from_one(&D::from_parts(IBig::from(10).pow(66) + IBig::ONE, -66)),
            &dec("1e-66")
        ));
        assert!(same(&distance_from_one(&dec("0.5")), &D::ONE));
    }

    fn extremes() -> [D; 3] {
        [
            largest_float(false),
            D::from_parts(IBig::ONE, I32_MIN),
            D::from_parts(int224_max(), I32_MIN),
        ]
    }

    /// Inputs at both exponent ends stay cheap for the transcendental oracle.
    #[test]
    fn sqrt_extremes_are_cheap() {
        for a in extremes() {
            let _ = want_sqrt(&a);
        }
    }

    #[test]
    fn log10_extremes_are_cheap() {
        for a in extremes() {
            let _ = log10_of(&a, 130);
        }
    }

    #[test]
    fn ten_to_extremes_are_cheap() {
        let _ = ten_to(&huge());
        let _ = ten_to(&-huge());
        let _ = ten_to(&D::from_parts(IBig::from(7), I32_MIN));
        let _ = ten_to(&-D::from_parts(IBig::from(7), I32_MIN));
        let _ = ten_to(&D::from_parts(int224_max(), I32_MIN + 60));
    }
}

/// The checks reject wrong results the bounds once let through, and the
/// oracle's own rounding agrees with exact integer arithmetic.
mod oracle_checks {
    use super::*;
    use dashu_base::SquareRoot;
    use dashu_int::UBig;

    /// x = 5 + 1e-50: 10^x = 1e5 (1 + 2.3e-50). 1e5 - 4e-36 is 4 units of
    /// its own 41st digit off, inside half a unit of 1e5's.
    #[test]
    fn pow10_unit_is_the_smaller_values() {
        let x = Dec::new(pow10(50) * 5 + 1, -50);
        assert!(check_pow10_with(&x, Ok(Dec::new(1, 5))).is_ok());
        let wrong = Dec::new(pow10(41) - 4, 5 - 41);
        assert!(check_pow10_with(&x, Ok(wrong)).is_err());
    }

    /// a = 10 + 1e-66: log10 a = 1 + 4.3e-68. 1 - 4e-41 is 4 units of its
    /// own 41st digit off, inside half a unit of 1's.
    #[test]
    fn log10_unit_is_the_results() {
        let a = Dec::new(pow10(67) + 1, -66);
        assert!(check_log10_with(&a, Ok(Dec::new(1, 0))).is_ok());
        let wrong = Dec::new(pow10(41) - 4, -41);
        assert!(check_log10_with(&a, Ok(wrong)).is_err());
    }

    /// 0.1^5000 is exactly 1e-5000 though |b| is past exact_power's 1000.
    #[test]
    fn pow_of_a_power_of_ten_is_exact() {
        let (a, b) = (Dec::new(1, -1), Dec::new(5000, 0));
        assert!(check_pow_with(&a, &b, Ok(Dec::new(1, -5000))).is_ok());
        let wrong = Dec::new(pow10(41) - 4, -5041);
        assert!(check_pow_with(&a, &b, Ok(wrong)).is_err());
        let (a, b) = (Dec::new(-1, 2), Dec::new(3001, 0));
        assert!(check_pow_with(&a, &b, Ok(Dec::new(-1, 6002))).is_ok());
        assert!(check_pow_with(&a, &b, Ok(Dec::new(1, 6002))).is_err());
    }

    /// |a| = 10^k with k b whole, under 1e12 in b alone but past isize in
    /// k b: 10^(k b) is past every Float, so only the range error of its
    /// direction passes.
    #[test]
    fn pow_of_a_power_of_ten_past_isize_is_past() {
        let revert = |e: RefError, a: &Dec| Fail::Revert(revert_data(e, a, None).into());
        let cases = [
            (Dec::new(1, 92233721), Dec::new(9999999999i64, 1)),
            (Dec::new(1, 92233721), Dec::new(pow10(57), -46)),
            (Dec::new(1, 153722868), Dec::new(6, 10)),
        ];
        for (a, b) in cases {
            let over = revert(RefError::ExponentOverflow, &a);
            let under = revert(RefError::ExponentUnderflow, &a);
            assert!(check_pow_with(&a, &b, Err(over)).is_ok());
            assert!(check_pow_with(&a, &b, Err(under)).is_err());
            assert!(check_pow_with(&a, &b, Ok(Dec::new(1, 5))).is_err());
            let (a, b) = (a.neg(), b.neg());
            let over = revert(RefError::ExponentOverflow, &a);
            let under = revert(RefError::ExponentUnderflow, &a);
            assert!(check_pow_with(&a, &b, Err(under)).is_ok());
            assert!(check_pow_with(&a, &b, Err(over)).is_err());
            assert!(check_pow_with(&a, &b, Ok(Dec::new(1, -5))).is_err());
        }
    }

    /// pow(2, 1e76) is past every Float, but its band at rel >= 1 reaches
    /// zero: any result passes but zero, the wrong sign or over 41 digits.
    #[test]
    fn pow_unbounded_band_keeps_sign_and_digits() {
        let (a, b) = (Dec::new(2, 0), Dec::new(1, 76));
        assert!(check_pow_with(&a, &b, Ok(Dec::new(7, 5))).is_ok());
        assert!(check_pow_with(&a, &b, Ok(Dec::zero())).is_err());
        assert!(check_pow_with(&a, &b, Ok(Dec::new(-7, 5))).is_err());
        assert!(check_pow_with(&a, &b, Ok(Dec::new(pow10(41) + 1, 5))).is_err());
    }

    /// The carry threshold rounds past the largest Float at 41 digits, half
    /// away from zero, and the value one unit of its 100th digit below does
    /// not.
    #[test]
    fn carry_threshold_is_the_rounding_midpoint() {
        let round41 = |v: &D| {
            v.clone()
                .with_rounding::<HalfAway>()
                .with_precision(41)
                .value()
                .with_rounding::<Zero>()
        };
        for negative in [false, true] {
            let t = carry_threshold(negative);
            let below = rounded(
                Context::<Zero>::new(200)
                    .sub(t.repr(), D::from_parts(IBig::ONE, lead(&t) - 99).repr())
                    .unwrap(),
            );
            assert!(round41(&t) > largest_float(negative), "{negative}");
            assert!(round41(&below) <= largest_float(negative), "{negative}");
        }
    }

    #[test]
    fn literal_values() {
        let ok = |s: &str, v: D| assert!(same(&literal_value(s).unwrap(), &v), "{s}");
        let err = |s: &str, e: RefError| assert_eq!(literal_value(s).map(|_| ()), Err(e), "{s}");
        ok("0.5", D::from_parts(IBig::from(5), -1));
        ok("1e2147483647", D::from_parts(IBig::ONE, I32_MAX));
        ok("1e2147483714", D::from_parts(IBig::ONE, I32_MAX + 67));
        ok(&format!("0e{}", "9".repeat(80)), D::ZERO);
        ok(
            &format!("-{}e2147483647", IBig::ONE << 223),
            -largest_float(true),
        );
        ok(
            &format!("{}e2147483647", int224_max()),
            largest_float(false),
        );
        err("1e2147483715", RefError::ExponentOverflow);
        err(&format!("1e{}", "9".repeat(80)), RefError::ExponentOverflow);
        err(
            &format!("{}e2147483647", (IBig::ONE << 223) + IBig::from(2)),
            RefError::ExponentOverflow,
        );
        err(
            &format!("{}e2147483647", (IBig::ONE << 223) + IBig::ONE),
            RefError::ParseDecimalPrecisionLoss,
        );
        err(
            &format!("1e-{}", "9".repeat(80)),
            RefError::ParseDecimalPrecisionLoss,
        );
        err("1e-2147483649", RefError::ParseDecimalPrecisionLoss);
        err("1.5e-2147483648", RefError::ParseDecimalPrecisionLoss);
    }

    #[test]
    fn agree_rules() {
        let n = |c: i64, e: i64| Dec::new(c, e);
        let z = Dec::zero();
        let want = |a: &Dec, p: &Dec, x: &Dec, y: &Dec| {
            let w = want_agree(a, p, x, y);
            assert_eq!(w, want_agree(a, p, y, x), "order");
            w
        };
        assert_eq!(
            want(&n(-1, 0), &n(1, 0), &z, &z),
            Err(RefError::AgreeToleranceNegative)
        );
        assert_eq!(
            want(&n(1, 0), &n(-1, -80), &z, &z),
            Err(RefError::AgreeToleranceNegative)
        );
        assert_eq!(
            want(&z, &n(0, 9), &z, &z),
            Err(RefError::AgreeNoPositiveTolerance)
        );
        assert_eq!(want(&n(1, 0), &z, &z, &n(1, 0)), Ok(Some(true)));
        assert_eq!(
            want(&n(1, 0), &z, &z, &n(10000000001, -10)),
            Ok(Some(false))
        );
        // proportional against the larger magnitude: 0.1 * 11 >= 1, 0.1 * 12 < 2.
        assert_eq!(want(&z, &n(1, -1), &n(10, 0), &n(11, 0)), Ok(Some(true)));
        assert_eq!(want(&z, &n(1, -1), &n(-10, 0), &n(-11, 0)), Ok(Some(true)));
        assert_eq!(want(&z, &n(1, -1), &n(10, 0), &n(12, 0)), Ok(Some(false)));
        // the larger tolerance applies.
        assert_eq!(
            want(&n(2, 0), &n(1, -1), &n(10, 0), &n(12, 0)),
            Ok(Some(true))
        );
        // a spread past the limit by under 1.7273e-76 of itself may go either way.
        let close = Dec::new(pow10(78) - 1, -78);
        assert_eq!(want(&close, &z, &z, &n(1, 0)), Ok(None));
        let far = Dec::new(pow10(70) - 1, -70);
        assert_eq!(want(&far, &z, &z, &n(1, 0)), Ok(Some(false)));
        // a limit past int256.max that mul would truncate below the spread.
        let h = Dec::new(
            "5789604461865809771178549250434395392663499233282028201969066711282"
                .parse::<num_bigint::BigInt>()
                .unwrap(),
            10,
        );
        let l = Dec::new(num_bigint::BigInt::from(-38124891136564819967i128), 0);
        let p = Dec::new(pow10(66) + 658505972u32, -66);
        assert_eq!(want(&z, &p, &l, &h), Ok(Some(true)));
        // 6 against -9e-76 is past 6 by 1.5e-76 of the spread, which the
        // truncated spread holds as 6: the library accepts it.
        let past = (n(6, 0), z.clone(), n(-9, -76), n(6, 0));
        assert_ne!(want(&past.0, &past.1, &past.2, &past.3), Ok(Some(false)));
        check_agree(&past.0, &past.1, &past.2, &past.3).unwrap();
    }

    /// sqrt(c 10^e) correctly rounded half away at 41 digits, by integer
    /// square root of c 10^m at about 200 digits, e - m even.
    fn isqrt_round41(c: &UBig, e: isize) -> D {
        let digits = c.to_string().len() as isize;
        let mut m = 200 - digits;
        if (e - m).rem_euclid(2) != 0 {
            m += 1;
        }
        let root = (c * UBig::from(10u8).pow(m as usize)).sqrt();
        let drop = root.to_string().len() - 41;
        let p = UBig::from(10u8).pow(drop);
        let head = &root / &p;
        let half = UBig::from(5u8) * UBig::from(10u8).pow(drop - 1);
        let head = if &root % &p >= half {
            head + UBig::ONE
        } else {
            head
        };
        D::from_parts(IBig::from(head), (e - m) / 2 + drop as isize)
    }

    fn sig() -> impl Strategy<Value = IBig> {
        (any::<[u8; 28]>(), 1usize..=28).prop_map(|(b, n)| IBig::from_be_bytes(&b[..n]))
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(config().cases.saturating_mul(10)))]

        /// dashu's division at P digits is the exact quotient truncated at
        /// P digits.
        #[test]
        fn dashu_div_truncates(a in sig(), b in sig()) {
            prop_assume!(b != IBig::ZERO);
            let got = rounded(ctx().div(D::from_parts(a.clone(), 0).repr(), D::from_parts(b.clone(), 0).repr()).unwrap());
            // floor(|a| 10^200 / |b|), signed: exact to 200 places.
            let q = a.clone().abs() * IBig::from(10).pow(200) / b.clone().abs();
            let q = if (a < IBig::ZERO) != (b < IBig::ZERO) { -q } else { q };
            let exact = D::from_parts(q, -200);
            let want = rounded(Context::<Zero>::new(P).add(exact.repr(), D::ZERO.repr()).unwrap());
            prop_assert!(same(&got, &want), "{a}/{b}: dashu {got}, exact {want}");
        }

        #[test]
        fn want_sqrt_is_correctly_rounded(x in sqrt_near_tie()) {
            let c: UBig = x.c.to_string().parse().unwrap();
            let want = isqrt_round41(&c, x.e as isize);
            let got = want_sqrt(&d(&x));
            prop_assert!(same(&got, &want), "sqrt({c}e{}): oracle {got}, isqrt {want}", x.e);
        }
    }
}
