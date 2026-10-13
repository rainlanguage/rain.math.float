//! The library's arithmetic, comparisons, conversions and errors, through the
//! concrete in revm.

use crate::evm::{self, TestDecimalFloat as T, TestDecimalFloatHarness as H};
use crate::exact::show;
use crate::reference::{self as r, Dec, I32_MIN, RefError, int224_max};
use T::TestDecimalFloatErrors as Errors;
use alloy::primitives::I256;
use alloy::primitives::aliases::I224;
use alloy::primitives::{B256, Bytes, FixedBytes, U256, fixed_bytes};
use alloy::sol_types::{SolCall, SolInterface};
use core::cmp::Ordering;
use core::fmt::Debug;
use core::str::FromStr;
use proptest::prelude::*;
use proptest::test_runner::TestCaseError;

/// How a call failed: a revert, which must decode as one of the concrete's
/// errors, or the error selector `parse` returns.
#[derive(Debug)]
enum Fail {
    Revert(Box<Errors>),
    Selector(FixedBytes<4>),
}

type R<V> = Result<V, Fail>;

fn call<C: SolCall>(c: C) -> R<C::Return> {
    evm::concrete(c).map_err(|out: Bytes| Fail::Revert(Box::new(Errors::abi_decode(&out).unwrap())))
}

#[derive(Clone, Copy)]
struct Float(B256);

impl Debug for Float {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str(&show(&Dec::from_bytes(self.0)))
    }
}

fn float<C: SolCall<Return = B256>>(c: C) -> R<Float> {
    call(c).map(Float)
}

impl Float {
    fn zero() -> R<Float> {
        float(T::zeroCall {})
    }

    fn max_positive_value() -> R<Float> {
        float(T::maxPositiveValueCall {})
    }

    fn min_positive_value() -> R<Float> {
        float(T::minPositiveValueCall {})
    }

    fn max_negative_value() -> R<Float> {
        float(T::maxNegativeValueCall {})
    }

    fn min_negative_value() -> R<Float> {
        float(T::minNegativeValueCall {})
    }

    fn parse(str: String) -> R<Float> {
        let r = call(T::parseCall { str })?;
        if r._0 != FixedBytes::ZERO {
            return Err(Fail::Selector(r._0));
        }
        Ok(Float(r._1))
    }

    fn pack_lossless(coefficient: I224, exponent: i32) -> R<Float> {
        evm::harness(H::packLosslessCall {
            signedCoefficient: I256::from_dec_str(&coefficient.to_string()).unwrap(),
            exponent: I256::try_from(exponent).unwrap(),
        })
        .map(Float)
        .map_err(|out| Fail::Revert(Box::new(Errors::abi_decode(&out).unwrap())))
    }

    fn show_unpacked(self) -> R<String> {
        Ok(show(&Dec::from_bytes(self.0)))
    }

    fn format_with_scientific(self, scientific: bool) -> R<String> {
        call(T::formatCall {
            a: self.0,
            scientific,
        })
    }

    fn from_fixed_decimal(value: U256, decimals: u8) -> R<Float> {
        float(T::fromFixedDecimalLosslessCall { value, decimals })
    }

    fn from_fixed_decimal_lossy(value: U256, decimals: u8) -> R<(Float, bool)> {
        call(T::fromFixedDecimalLossyCall { value, decimals }).map(|r| (Float(r._0), r._1))
    }

    fn to_fixed_decimal(self, decimals: u8) -> R<U256> {
        call(T::toFixedDecimalLosslessCall {
            float: self.0,
            decimals,
        })
    }

    fn to_fixed_decimal_lossy(self, decimals: u8) -> R<(U256, bool)> {
        call(T::toFixedDecimalLossyCall {
            float: self.0,
            decimals,
        })
        .map(|r| (r._0, r._1))
    }

    fn min(self, b: Float) -> R<Float> {
        float(T::minCall { a: self.0, b: b.0 })
    }

    fn max(self, b: Float) -> R<Float> {
        float(T::maxCall { a: self.0, b: b.0 })
    }

    fn eq(self, b: Float) -> R<bool> {
        call(T::eqCall { a: self.0, b: b.0 })
    }

    fn lt(self, b: Float) -> R<bool> {
        call(T::ltCall { a: self.0, b: b.0 })
    }

    fn gt(self, b: Float) -> R<bool> {
        call(T::gtCall { a: self.0, b: b.0 })
    }

    fn lte(self, b: Float) -> R<bool> {
        call(T::lteCall { a: self.0, b: b.0 })
    }

    fn gte(self, b: Float) -> R<bool> {
        call(T::gteCall { a: self.0, b: b.0 })
    }

    fn neg(self) -> R<Float> {
        float(T::minusCall { a: self.0 })
    }

    fn abs(self) -> R<Float> {
        float(T::absCall { a: self.0 })
    }

    fn inv(self) -> R<Float> {
        float(T::invCall { a: self.0 })
    }

    fn integer(self) -> R<Float> {
        float(T::integerCall { a: self.0 })
    }

    fn frac(self) -> R<Float> {
        float(T::fracCall { a: self.0 })
    }

    fn floor(self) -> R<Float> {
        float(T::floorCall { a: self.0 })
    }

    fn is_zero(self) -> R<bool> {
        call(T::isZeroCall { a: self.0 })
    }
}

macro_rules! binary {
    ($($op:ident $f:ident $call:ident),*) => {$(
        impl core::ops::$op for Float {
            type Output = R<Float>;

            fn $f(self, b: Float) -> R<Float> {
                float(T::$call { a: self.0, b: b.0 })
            }
        }
    )*};
}

binary!(Add add addCall, Sub sub subCall, Mul mul mulCall, Div div divCall);

/// Float::zero() is_zero, formats as "0" and equals parsed "0".
#[test]
fn test_zero() {
    let zero = Float::zero().unwrap();
    assert!(zero.is_zero().unwrap());
    assert_eq!(zero.format_with_scientific(false).unwrap(), "0");

    // Test that zero equals parsed zero
    let parsed_zero = Float::parse("0".to_string()).unwrap();
    assert!(zero.eq(parsed_zero).unwrap());
}

/// Every Float: any int224 coefficient and any int32 exponent, weighted
/// towards their edges.
fn arb_float() -> impl Strategy<Value = Float> {
    crate::exact::float().prop_map(|d| Float(d.to_bytes()))
}

impl Float {
    fn dec(self) -> Dec {
        Dec::from_bytes(self.0)
    }
}

fn fail_is(f: &Fail, e: RefError) -> bool {
    match f {
        Fail::Revert(x) => x.selector() == e.selector(),
        Fail::Selector(s) => s.0 == e.selector(),
    }
}

/// The library's result is the reference's: the same value by `same`, or
/// the same error.
fn agrees<V: Debug, W: Debug>(
    case: &str,
    lib: &R<V>,
    want: &Result<W, RefError>,
    same: impl Fn(&V, &W) -> bool,
) -> Result<(), TestCaseError> {
    match (lib, want) {
        (Ok(l), Ok(w)) => prop_assert!(same(l, w), "{case}: library {l:?}, reference {w:?}"),
        (Err(l), Err(w)) => prop_assert!(fail_is(l, *w), "{case}: library {l:?}, reference {w:?}"),
        (l, w) => prop_assert!(false, "{case}: library {l:?}, reference {w:?}"),
    }
    Ok(())
}

fn agrees_float(
    case: &str,
    lib: &R<Float>,
    want: &Result<Dec, RefError>,
) -> Result<(), TestCaseError> {
    agrees(case, lib, want, |l, w| l.dec().eq_value(w))
}

/// One step of a chain: the library's step from the library's last value,
/// the reference's from the reference's, which must agree before the next.
fn step(
    case: &str,
    lib: R<Float>,
    want: Result<Dec, RefError>,
) -> Result<Option<(Float, Dec)>, TestCaseError> {
    agrees_float(case, &lib, &want)?;
    Ok(lib.ok().zip(want.ok()))
}

fn one() -> (Float, Dec) {
    let d = Dec::new(1, 0);
    (Float(d.to_bytes()), d)
}

/// a - 1, then + 1, then + 1 again, each step the reference's, and each
/// result checked against a by `compare`. Where the steps are exact the
/// results are below, equal to and above a.
fn chain_against(
    a: Float,
    compare: impl Fn(Float, Float) -> Result<(), TestCaseError>,
) -> Result<(), TestCaseError> {
    let (one, one_d) = one();
    let ad = a.dec();
    let case = format!("{a:?} - 1 + 1 + 1");
    let mut x = (a, ad.clone());
    let mut exact = true;
    for (i, rising) in [false, true, true].into_iter().enumerate() {
        let (lib, want, ex) = if rising {
            (x.0 + one, r::add(&x.1, &one_d), x.1.add_exact(&one_d))
        } else {
            (x.0 - one, r::sub(&x.1, &one_d), x.1.add_exact(&one_d.neg()))
        };
        let Some(next) = step(&case, lib, want)? else {
            return Ok(());
        };
        exact &= ex.is_some_and(|e| e.eq_value(&next.1));
        compare(next.0, a)?;
        if exact {
            let want = [Ordering::Less, Ordering::Equal, Ordering::Greater][i];
            prop_assert_eq!(next.1.cmp_value(&ad), want, "{}: step {}", case, i);
        }
        x = next;
    }
    Ok(())
}

/// Parsing an empty string returns an error selector.
#[test]
fn test_parse_empty_string_error() {
    let err = Float::parse("".to_string()).unwrap_err();
    // We don't know the exact selector here, just ensure the error path is hit.
    assert!(matches!(err, Fail::Selector(_)));
}

#[test]
fn test_parse_exponent_overflow_error() {
    // Extremely large exponent expected to overflow (exponent >> i32::MAX),
    // returned by value rather than reverted (#510).
    let err = Float::parse("1e3000000000".to_string()).unwrap_err();
    let want = RefError::ExponentOverflow.selector();
    assert!(matches!(err, Fail::Selector(s) if s.0 == want), "{err:?}");
}

/// Malformed inputs ("1.2.3", "abc") return specific error selectors.
#[test]
fn test_parse_edge_cases() {
    let err = Float::parse("1.2.3".to_string()).unwrap_err();
    assert!(matches!(
        err,
        Fail::Selector(selector)
        if selector == fixed_bytes!("ad384e87")
    ));

    let err = Float::parse("abc".to_string()).unwrap_err();
    assert!(matches!(
        err,
        Fail::Selector(selector)
        if selector == fixed_bytes!("34bd2069")
    ));
}

/// Boundary constants are distinct, correctly signed, correctly ordered,
/// and bound normal values like 1 and -1.
#[test]
fn test_float_constants() {
    // Test that all constant methods return valid floats
    let max_pos = Float::max_positive_value().unwrap();
    let min_pos = Float::min_positive_value().unwrap();
    let max_neg = Float::max_negative_value().unwrap();
    let min_neg = Float::min_negative_value().unwrap();

    let zero = Float::parse("0".to_string()).unwrap();

    // Test mathematical properties without exposing binary representation

    // All constants should be distinct
    assert!(!max_pos.eq(min_pos).unwrap());
    assert!(!max_neg.eq(min_neg).unwrap());
    assert!(!max_pos.eq(max_neg).unwrap());
    assert!(!min_pos.eq(min_neg).unwrap());

    // Test sign properties
    assert!(min_pos.gt(zero).unwrap()); // min positive should be > 0
    assert!(max_pos.gt(zero).unwrap()); // max positive should be > 0
    assert!(max_neg.lt(zero).unwrap()); // max negative should be < 0
    assert!(min_neg.lt(zero).unwrap()); // min negative should be < 0

    // Test ordering relationships
    assert!(min_pos.lt(max_pos).unwrap()); // min positive < max positive
    assert!(min_neg.lt(max_neg).unwrap()); // min negative < max negative

    // Test boundary properties
    let one = Float::parse("1".to_string()).unwrap();
    let neg_one = Float::parse("-1".to_string()).unwrap();

    // Positive constants should be greater than normal values
    assert!(max_pos.gt(one).unwrap());
    assert!(min_pos.lt(one).unwrap());

    // Negative constants should be more extreme than normal negative values
    assert!(max_neg.gt(neg_one).unwrap());
    assert!(min_neg.lt(neg_one).unwrap());
}

proptest! {
    #[test]
    /// Formatting in either notation is the documented string, and parsing
    /// it is the reference's parse, an equal value wherever it formats.
    fn test_format_parse(float in arb_float(), scientific in any::<bool>()) {
        let case = format!("format({float:?}, {scientific})");
        let formatted = float.format_with_scientific(scientific);
        let want = if scientific {
            r::format_scientific(&float.dec())
        } else {
            r::format_plain(&float.dec())
        };
        agrees(&case, &formatted, &want, |l, w| l == w)?;
        if let Ok(s) = formatted {
            let want = r::parse(&s);
            prop_assert!(
                matches!(&want, Ok(w) if w.eq_value(&float.dec())),
                "{case}: {s} parses to {want:?}"
            );
            agrees_float(&format!("parse({s})"), &Float::parse(s.clone()), &want)?;
        }
    }
}

/// Adding two max-exponent floats overflows with ExponentOverflow.
#[test]
fn test_add_exponent_overflow_error() {
    let max_coeff_str = "13479973333575319897333507543509815336818572211270286240551805124607";
    let large_coeff_i224 = I224::from_str(max_coeff_str).unwrap();
    let exponent_max = i32::MAX;

    let a = Float::pack_lossless(large_coeff_i224, exponent_max).unwrap();

    let err = (a + a).unwrap_err();

    assert!(matches!(err, Fail::Revert(e) if matches!(*e, Errors::ExponentOverflow(_))));
}

/// Subtracting opposite-sign max-exponent floats overflows.
#[test]
fn test_sub_exponent_overflow_error() {
    let max_coeff_str = "13479973333575319897333507543509815336818572211270286240551805124607";
    let large_coeff_i224 = I224::from_str(max_coeff_str).unwrap();
    let exponent_max = i32::MAX;

    let a = Float::pack_lossless(large_coeff_i224, exponent_max).unwrap();
    let b = Float::pack_lossless(-large_coeff_i224, exponent_max).unwrap();

    let err = (b - a).unwrap_err();

    assert!(matches!(err, Fail::Revert(e) if matches!(*e, Errors::ExponentOverflow(_))));
}

proptest! {
    #[test]
    /// Addition is the reference's.
    fn test_add(a in arb_float(), b in arb_float()) {
        agrees_float(&format!("{a:?} + {b:?}"), &(a + b), &r::add(&a.dec(), &b.dec()))?;
    }
}

proptest! {
    #[test]
    /// Subtraction is the reference's.
    fn test_sub(a in arb_float(), b in arb_float()) {
        agrees_float(&format!("{a:?} - {b:?}"), &(a - b), &r::sub(&a.dec(), &b.dec()))?;
    }
}

proptest! {
    #[test]
    /// (a + b) - b is the reference's chain, and a wherever both steps are
    /// exact.
    fn test_add_sub(a in arb_float(), b in arb_float()) {
        let (ad, bd) = (a.dec(), b.dec());
        let case = format!("({a:?} + {b:?}) - {b:?}");
        let Some((sum, sum_d)) = step(&case, a + b, r::add(&ad, &bd))? else {
            return Ok(());
        };
        let Some((diff, _)) = step(&case, sum - b, r::sub(&sum_d, &bd))? else {
            return Ok(());
        };
        if ad.add_exact(&bd).is_some_and(|s| s.eq_value(&sum_d)) {
            prop_assert!(diff.dec().eq_value(&ad), "{case}: exact steps, {diff:?}");
        }
    }
}

/// Manual check: -1 < 0 < 3, with correct lt/eq/gt for each pair.
#[test]
fn test_lt_eq_gt() {
    let negone = Float::parse("-1".to_string()).unwrap();
    let zero = Float::parse("0".to_string()).unwrap();
    let three = Float::parse("3".to_string()).unwrap();

    assert!(negone.lt(zero).unwrap());
    assert!(!negone.eq(zero).unwrap());
    assert!(!negone.gt(zero).unwrap());

    assert!(!three.lt(zero).unwrap());
    assert!(!three.eq(zero).unwrap());
    assert!(three.gt(zero).unwrap());

    assert!(zero.lt(three).unwrap());
    assert!(!zero.eq(three).unwrap());
    assert!(!zero.gt(three).unwrap());
}

proptest! {
    #[test]
    /// a == a; a - 1, then + 1, then + 1 again are the reference's chain,
    /// and each compares with a as the reference values do.
    fn test_lt_eq_gt_with_add(a in arb_float()) {
        prop_assert!(a.eq(a).unwrap());
        chain_against(a, |x, y| {
            let o = x.dec().cmp_value(&y.dec());
            prop_assert_eq!(x.lt(y).unwrap(), o == Ordering::Less);
            prop_assert_eq!(x.eq(y).unwrap(), o == Ordering::Equal);
            prop_assert_eq!(x.gt(y).unwrap(), o == Ordering::Greater);
            Ok(())
        })?;
    }

    #[test]
    /// Trichotomy: exactly one of lt, eq, gt is true for any two floats.
    fn test_exactly_one_lt_eq_gt(a in arb_float(), b in arb_float()) {
        let eq = a.eq(b).unwrap();
        let lt = a.lt(b).unwrap();
        let gt = a.gt(b).unwrap();

        let a_str = a.show_unpacked().unwrap();
        let b_str = b.show_unpacked().unwrap();

        prop_assert!(lt || eq || gt, "a: {a_str}, b: {b_str}");
        prop_assert!(!(lt && eq), "both less than and equal: a: {a_str}, b: {b_str}");
        prop_assert!(!(eq && gt), "both equal and greater than: a: {a_str}, b: {b_str}");
        prop_assert!(!(lt && gt), "both less than and greater than: a: {a_str}, b: {b_str}");
    }
}

/// abs(-x) == abs(x) == |x| for manual positive, negative, and zero cases.
#[test]
fn test_abs() {
    let float = Float::parse("-3613.1324123".to_string()).unwrap();
    let abs = float.abs().unwrap();
    let formatted = abs.format_with_scientific(false).unwrap();
    assert_eq!(formatted, "3613.1324123");

    let float = Float::parse("3613.1324123".to_string()).unwrap();
    let abs = float.abs().unwrap();
    let formatted = abs.format_with_scientific(false).unwrap();
    assert_eq!(formatted, "3613.1324123");

    let float = Float::parse("0".to_string()).unwrap();
    let abs = float.abs().unwrap();
    let formatted = abs.format_with_scientific(false).unwrap();
    assert_eq!(formatted, "0");
}

proptest! {
    #[test]
    /// Multiplication is the reference's.
    fn test_mul(a in arb_float(), b in arb_float()) {
        agrees_float(&format!("{a:?} * {b:?}"), &(a * b), &r::mul(&a.dec(), &b.dec()))?;
    }
}

/// Negating a negative produces positive format in either notation; negating
/// zero stays "0".
#[test]
fn test_minus_format() {
    let float = Float::parse("-123.1234234625468391".to_string()).unwrap();
    let negated = float.neg().unwrap();

    let formatted_decimal = negated.format_with_scientific(false).unwrap();
    assert_eq!(formatted_decimal, "123.1234234625468391");

    let formatted_scientific = negated.format_with_scientific(true).unwrap();
    assert_eq!(formatted_scientific, "1.231234234625468391e2");

    let float = Float::parse("0".to_string()).unwrap();
    let negated = float.neg().unwrap();
    let formatted = negated.format_with_scientific(false).unwrap();
    assert_eq!(formatted, "0");
}

proptest! {
    #[test]
    /// -(-a) is the reference's chain, and a wherever -a is exact.
    fn test_minus_minus(float in arb_float()) {
        let fd = float.dec();
        let case = format!("-(-{float:?})");
        let Some((negated, negated_d)) = step(&case, float.neg(), r::minus(&fd))? else {
            return Ok(());
        };
        let Some((renegated, _)) = step(&case, negated.neg(), r::minus(&negated_d))? else {
            return Ok(());
        };
        if negated_d.eq_value(&fd.neg()) {
            prop_assert!(float.eq(renegated).unwrap(), "{case}: exact, {renegated:?}");
        }
    }
}

proptest! {
    #[test]
    /// inv(a) and a * inv(a) are the reference's chain, and the product is in
    /// (1 - 2 / c_min, 1] wherever inv(a) packs above the exponent floor.
    fn test_inv_prod(float in arb_float()) {
        let fd = float.dec();
        let case = format!("{float:?} * inv({float:?})");
        let Some((inv, inv_d)) = step(&case, float.inv(), r::inv(&fd))? else {
            return Ok(());
        };
        let Some((product, _)) = step(&case, float * inv, r::mul(&fd, &inv_d))? else {
            return Ok(());
        };
        let product = product.dec();

        // inv and mul each give the Float closest to the exact result that
        // does not exceed its magnitude. That is the exact result, or has a
        // coefficient above int224 max / 10 (else one more digit fits), so
        // each loses a relative error below 1 / c_min. The product is
        // (1 - d1)(1 - d2): at most 1, and above 1 - 2 / c_min.
        let one = Dec::new(1, 0);
        prop_assert!(
            product.cmp_value(&one).is_le(),
            "float: {}, inv: {}, product: {} above 1",
            float.show_unpacked().unwrap(),
            inv.show_unpacked().unwrap(),
            show(&product),
        );
        // At the exponent floor inv(a) keeps only the digits above it, so its
        // relative error has no bound there.
        if inv_d.e == I32_MIN {
            return Ok(());
        }
        let c_min = Dec::new(int224_max() / 10 + 1, 0);
        let shortfall = one.add_exact(&product.neg()).unwrap();
        prop_assert!(
            shortfall.mul_exact(&c_min).cmp_value(&Dec::new(2, 0)).is_lt(),
            "float: {}, inv: {}, product: {} not above 1 - 2 / c_min",
            float.show_unpacked().unwrap(),
            inv.show_unpacked().unwrap(),
            show(&product),
        );
    }
}

/// For a = ±2^i 5^j the inverse 2^(n-i) 5^(n-j) 10^-n, n = max(i, j), is
/// exact. When it fits a Float, inv(a) is that value and a * inv(a) is 1.
#[test]
fn test_inv_prod_exact() {
    let max = int224_max();
    let one = Dec::new(1, 0);
    for i in 0u32..=223 {
        for j in 0u32..=96 {
            let c = num_bigint::BigInt::from(2).pow(i) * num_bigint::BigInt::from(5).pow(j);
            if c > max {
                break;
            }
            let n = i.max(j);
            let inv_c =
                num_bigint::BigInt::from(2).pow(n - i) * num_bigint::BigInt::from(5).pow(n - j);
            if inv_c > max {
                continue;
            }
            for neg in [false, true] {
                let sign = if neg { -1 } else { 1 };
                let a = Dec::new(sign * c.clone(), 0);
                let expected = Dec::new(sign * inv_c.clone(), -i64::from(n));
                let float = Float(a.to_bytes());
                let inv = float.inv().unwrap();
                let got = Dec::from_bytes(inv.0);
                assert!(
                    got.eq_value(&expected),
                    "inv({}) = {}, expected {}",
                    show(&a),
                    show(&got),
                    show(&expected),
                );
                let product = Dec::from_bytes((float * inv).unwrap().0);
                assert!(
                    product.eq_value(&one),
                    "{} * inv = {}, expected 1",
                    show(&a),
                    show(&product),
                );
            }
        }
    }
}

proptest! {
    #[test]
    /// abs and its string are the reference's, never starting with "-".
    fn test_abs_no_minus_sign(float in arb_float(), scientific in any::<bool>()) {
        let case = format!("abs({float:?})");
        let Some((abs, abs_d)) = step(&case, float.abs(), r::abs(&float.dec()))? else {
            return Ok(());
        };
        let formatted = abs.format_with_scientific(scientific);
        let want = if scientific {
            r::format_scientific(&abs_d)
        } else {
            r::format_plain(&abs_d)
        };
        agrees(&case, &formatted, &want, |l, w| l == w)?;
        if let Ok(s) = formatted {
            prop_assert!(!s.starts_with('-'), "{case}: {s}");
        }
    }

    #[test]
    /// abs is idempotent: abs(abs(a)) == abs(a).
    fn test_abs_abs(float in arb_float()) {
        let abs = float.abs().unwrap();
        let abs_abs = abs.abs().unwrap();
        prop_assert!(abs.eq(abs_abs).unwrap());
    }
}

proptest! {
    #[test]
    /// Division is the reference's, a zero divisor included.
    fn test_div(a in arb_float(), b in arb_float()) {
        agrees_float(&format!("{a:?} / {b:?}"), &(a / b), &r::div(&a.dec(), &b.dec()))?;
    }
}

proptest! {
    #[test]
    /// (a * b) / b is the reference's chain, and a wherever the product is
    /// exact.
    fn test_mul_div_int(a in arb_float(), b in arb_float()) {
        let (ad, bd) = (a.dec(), b.dec());
        let case = format!("({a:?} * {b:?}) / {b:?}");
        let Some((product, product_d)) = step(&case, a * b, r::mul(&ad, &bd))? else {
            return Ok(());
        };
        let Some((quotient, _)) = step(&case, product / b, r::div(&product_d, &bd))? else {
            return Ok(());
        };
        if ad.mul_exact(&bd).eq_value(&product_d) {
            prop_assert!(quotient.dec().eq_value(&ad), "{case}: exact product, {quotient:?}");
        }
    }
}

/// 6/3 == 2 and 2*3 == 6.
#[test]
fn test_mul_div_manual() {
    let two = Float::parse("2".to_string()).unwrap();
    let three = Float::parse("3".to_string()).unwrap();
    let six = Float::parse("6".to_string()).unwrap();

    assert!(two.eq((six / three).unwrap()).unwrap());
    assert!(six.eq((two * three).unwrap()).unwrap());
}

/// 1/0 returns DivisionByZero error.
#[test]
fn test_divide_by_zero_error() {
    let one = Float::parse("1".to_string()).unwrap();
    let zero = Float::parse("0".to_string()).unwrap();
    let err = (one / zero).unwrap_err();

    assert!(matches!(err, Fail::Revert(e) if matches!(*e, Errors::DivisionByZero(_))));
}

/// Multiplying near-max exponents overflows.
#[test]
fn test_mul_exponent_overflow_error() {
    let near_max_exp = Float::parse("1e2147483646".to_string()).unwrap();
    let one_e_hundred = Float::parse("1e100".to_string()).unwrap();

    let err = (near_max_exp * one_e_hundred).unwrap_err();
    assert!(matches!(err, Fail::Revert(e) if matches!(*e, Errors::ExponentOverflow(_))));
}

/// Dividing near-max exponent by small exponent overflows.
#[test]
fn test_div_exponent_overflow_error() {
    let near_max_exp = Float::parse("1e2147483646".to_string()).unwrap();
    let one_e_neg_hundred = Float::parse("1e-100".to_string()).unwrap();

    let err = (near_max_exp / one_e_neg_hundred).unwrap_err();
    assert!(matches!(err, Fail::Revert(e) if matches!(*e, Errors::ExponentOverflow(_))));
}

/// Multiplying near-min exponents underflows; the public arithmetic
/// surface reverts with `ExponentUnderflow` rather than silently
/// producing zero.
#[test]
fn test_mul_exponent_underflow_error() {
    let near_min_exp = Float::parse("1e-2147483646".to_string()).unwrap();
    let one_e_neg_three = Float::parse("1e-3".to_string()).unwrap();

    let err = (near_min_exp * one_e_neg_three).unwrap_err();
    assert!(matches!(err, Fail::Revert(e) if matches!(*e, Errors::ExponentUnderflow(_))));
}

/// from_fixed_decimal for known value/decimals pairs matches parsed strings.
#[test]
fn test_from_fixed_decimal() {
    let cases = vec![
        (U256::from(0u128), 0u8, "0"),
        (U256::from(0u128), 18u8, "0"),
        (U256::from(1u128), 18u8, "1e-18"),
        (U256::from(123456789u128), 0u8, "123456789"),
        (U256::from(123456789u128), 2u8, "123456789e-2"),
        (U256::from(1000000000000000000u128), 18u8, "1"),
    ];

    for (amount, decimals, expected) in cases {
        let float = Float::from_fixed_decimal(amount, decimals).expect("should convert");
        let expected = Float::parse(expected.to_string()).unwrap();
        assert!(float.eq(expected).unwrap());
    }
}

/// U256::MAX with 1 decimal overflows (LossyConversionToFloat).
#[test]
fn test_from_fixed_decimal_err() {
    let err = Float::from_fixed_decimal(U256::MAX, 1).unwrap_err();
    assert!(matches!(
        err,
        Fail::Revert(e) if matches!(*e, Errors::LossyConversionToFloat(_))
    ));
}

/// to_fixed_decimal for known inputs matches expected U256 values.
#[test]
fn test_to_fixed_decimal() {
    let cases = vec![
        ("0", 0u8, 0u128),
        ("0", 18u8, 0u128),
        ("1e-18", 18u8, 1u128),
        ("123456789", 0u8, 123456789u128),
        ("123456789e-2", 2u8, 123456789u128),
        ("1", 18u8, 1000000000000000000u128),
    ];

    for (input, decimals, expected) in cases {
        let float = Float::parse(input.to_string()).unwrap();
        let fixed = float.to_fixed_decimal(decimals).unwrap();
        assert_eq!(fixed, U256::from(expected));
    }
}

/// For integers: floor == self, frac == 0, and floor + frac == self.
#[test]
fn test_frac_and_floor_integers() {
    let int_float = Float::parse("12345".to_string()).unwrap();
    let floor = int_float.floor().unwrap();
    let frac = int_float.frac().unwrap();
    let zero = Float::parse("0".to_string()).unwrap();

    assert!(int_float.eq(floor).unwrap());
    assert!(frac.eq(zero).unwrap());

    let int_float = Float::parse("-98765".to_string()).unwrap();
    let floor = int_float.floor().unwrap();
    let frac = int_float.frac().unwrap();
    let zero = Float::parse("0".to_string()).unwrap();

    assert!(int_float.eq(floor).unwrap());
    assert!(frac.eq(zero).unwrap());

    let recombined = (floor + frac).unwrap();
    assert!(int_float.eq(recombined).unwrap());
}

/// floor(12345.6789) == 12345, frac(12345.6789) == 0.6789.
#[test]
fn test_frac_and_floor_floats() {
    let float = Float::parse("12345.6789".to_string()).unwrap();
    let floor = float.floor().unwrap();
    let frac = float.frac().unwrap();

    let expected_floor = Float::parse("12345".to_string()).unwrap();
    let expected_frac = Float::parse("0.6789".to_string()).unwrap();

    assert!(floor.eq(expected_floor).unwrap());
    assert!(frac.eq(expected_frac).unwrap());
}

/// integer(12345.6789) == 12345, and integer + frac == original.
#[test]
fn test_integer_positive() {
    let float = Float::parse("12345.6789".to_string()).unwrap();
    let int = float.integer().unwrap();
    let expected = Float::parse("12345".to_string()).unwrap();
    assert!(int.eq(expected).unwrap());

    let frac = float.frac().unwrap();
    let recombined = (int + frac).unwrap();
    assert!(float.eq(recombined).unwrap());
}

/// integer truncates toward zero: integer(-12345.6789) == -12345.
#[test]
fn test_integer_negative() {
    let float = Float::parse("-12345.6789".to_string()).unwrap();
    let int = float.integer().unwrap();
    let frac = float.frac().unwrap();

    // integer truncates toward zero, so -12345.6789 -> -12345
    let expected_int = Float::parse("-12345".to_string()).unwrap();
    let expected_frac = Float::parse("-0.6789".to_string()).unwrap();

    assert!(int.eq(expected_int).unwrap());
    assert!(frac.eq(expected_frac).unwrap());

    // integer + frac == original
    let recombined = (int + frac).unwrap();
    assert!(float.eq(recombined).unwrap());
}

/// integer(42) == 42, frac(42) == 0 for positive and negative whole numbers.
#[test]
fn test_integer_whole_numbers() {
    let pos = Float::parse("42".to_string()).unwrap();
    assert!(pos.integer().unwrap().eq(pos).unwrap());
    let zero = Float::parse("0".to_string()).unwrap();
    assert!(pos.frac().unwrap().eq(zero).unwrap());

    let neg = Float::parse("-42".to_string()).unwrap();
    assert!(neg.integer().unwrap().eq(neg).unwrap());
    assert!(neg.frac().unwrap().eq(zero).unwrap());
}

proptest! {
    #[test]
    /// from_fixed_decimal then to_fixed_decimal are the reference's, and
    /// round-trip wherever the first is lossless.
    fn test_from_to_fixed_decimal_valid_range(value in crate::exact::u256(), decimals in any::<u8>()) {
        let case = format!("from_fixed_decimal({value}, {decimals})");
        let want = r::from_fixed_decimal_lossless(value, decimals);
        let Some((float, float_d)) = step(&case, Float::from_fixed_decimal(value, decimals), want)? else {
            return Ok(());
        };
        let want = r::to_fixed_decimal_lossless(&float_d, decimals);
        prop_assert!(matches!(want, Ok(v) if v == value), "{case}: back to {want:?}");
        agrees(&case, &float.to_fixed_decimal(decimals), &want, |l, w| l == w)?;
    }
}

proptest! {
    #[test]
    /// integer(a) + frac(a) == a, frac has no integer part, integer has
    /// no fractional part, and |frac| < 1.
    fn test_int_frac_properties(float in arb_float()) {
        let int = float.integer().unwrap();
        let frac = float.frac().unwrap();

        let zero = Float::parse("0".to_string()).unwrap();

        prop_assert!(
            int.frac().unwrap().eq(zero).unwrap(),
            "int.frac() is not zero: {}",
            int.show_unpacked().unwrap()
        );

        prop_assert!(
            frac.integer().unwrap().eq(zero).unwrap(),
            "frac.integer() is not zero: {}",
            frac.show_unpacked().unwrap()
        );

        let recombined = (int + frac).unwrap();
        prop_assert!(
            float.eq(recombined).unwrap(),
            "original: {}, int: {}, frac: {}, recombined: {}",
            float.show_unpacked().unwrap(),
            int.show_unpacked().unwrap(),
            frac.show_unpacked().unwrap(),
            recombined.show_unpacked().unwrap()
        );

        let one = Float::parse("1".to_string()).unwrap();
        let neg_one = one.neg().unwrap();
        prop_assert!(
            frac.lt(one).unwrap(),
            "frac not < 1: {}",
            frac.show_unpacked().unwrap()
        );
        prop_assert!(
            frac.gt(neg_one).unwrap(),
            "frac not > -1: {}",
            frac.show_unpacked().unwrap()
        );
    }
}

/// min/max for known value pairs, including identical arguments.
#[test]
fn test_min_max_manual() {
    let negone = Float::parse("-1".to_string()).unwrap();
    let zero = Float::parse("0".to_string()).unwrap();
    let three = Float::parse("3".to_string()).unwrap();
    let seven = Float::parse("7".to_string()).unwrap();

    // --- min ---
    assert!(negone.eq(negone.min(zero).unwrap()).unwrap());
    assert!(negone.eq(negone.min(three).unwrap()).unwrap());
    assert!(zero.eq(zero.min(three).unwrap()).unwrap());
    // min with identical arguments should return that argument
    assert!(seven.eq(seven.min(seven).unwrap()).unwrap());

    // --- max ---
    assert!(zero.eq(negone.max(zero).unwrap()).unwrap());
    assert!(three.eq(negone.max(three).unwrap()).unwrap());
    assert!(three.eq(zero.max(three).unwrap()).unwrap());
    // max with identical arguments should return that argument
    assert!(seven.eq(seven.max(seven).unwrap()).unwrap());
}

/// is_zero for "0", "-0", "0.0" (all true) and "1" (false).
#[test]
fn test_is_zero_manual() {
    let zero = Float::parse("0".to_string()).unwrap();
    assert!(zero.is_zero().unwrap());

    // Alternative zero representations that should also be considered zero.
    let neg_zero = Float::parse("-0".to_string()).unwrap();
    assert!(neg_zero.is_zero().unwrap());
    let zero_point = Float::parse("0.0".to_string()).unwrap();
    assert!(zero_point.is_zero().unwrap());

    let one = Float::parse("1".to_string()).unwrap();
    assert!(!one.is_zero().unwrap());
}

proptest! {
    #[test]
    /// min(a,b) <= both, max(a,b) >= both, each equals one operand,
    /// and min <= max.
    fn test_min_max_properties(a in arb_float(), b in arb_float()) {
        let min = a.min(b).unwrap();
        let max = a.max(b).unwrap();

        let a_below = a.dec().cmp_value(&b.dec()) != Ordering::Greater;
        let (lo, hi) = if a_below { (a, b) } else { (b, a) };
        prop_assert!(min.dec().eq_value(&lo.dec()), "min({a:?}, {b:?}) = {min:?}");
        prop_assert!(max.dec().eq_value(&hi.dec()), "max({a:?}, {b:?}) = {max:?}");

        prop_assert!(
            !min.gt(a).unwrap(),
            "min > a: min={}, a={}",
            min.show_unpacked().unwrap(),
            a.show_unpacked().unwrap()
        );
        prop_assert!(
            !min.gt(b).unwrap(),
            "min > b: min={}, b={}",
            min.show_unpacked().unwrap(),
            b.show_unpacked().unwrap()
        );

        prop_assert!(
            !max.lt(a).unwrap(),
            "max < a: max={}, a={}",
            max.show_unpacked().unwrap(),
            a.show_unpacked().unwrap()
        );
        prop_assert!(
            !max.lt(b).unwrap(),
            "max < b: max={}, b={}",
            max.show_unpacked().unwrap(),
            b.show_unpacked().unwrap()
        );

        let min_is_a = min.eq(a).unwrap();
        let min_is_b = min.eq(b).unwrap();
        prop_assert!(
            min_is_a || min_is_b,
            "min is not equal to either operand: a={}, b={}, min={}",
            a.show_unpacked().unwrap(),
            b.show_unpacked().unwrap(),
            min.show_unpacked().unwrap()
        );

        let max_is_a = max.eq(a).unwrap();
        let max_is_b = max.eq(b).unwrap();
        prop_assert!(
            max_is_a || max_is_b,
            "max is not equal to either operand: a={}, b={}, max={}",
            a.show_unpacked().unwrap(),
            b.show_unpacked().unwrap(),
            max.show_unpacked().unwrap()
        );

        prop_assert!(
            !min.gt(max).unwrap(),
            "min > max: min={}, max={}",
            min.show_unpacked().unwrap(),
            max.show_unpacked().unwrap()
        );
    }
}

/// Manual lte/gte checks: -1 <= 0 <= 3, 0 >= -1, 3 >= 0.
#[test]
fn test_lte_gte() {
    let negone = Float::parse("-1".to_string()).unwrap();
    let zero = Float::parse("0".to_string()).unwrap();
    let three = Float::parse("3".to_string()).unwrap();

    assert!(negone.lte(zero).unwrap());
    assert!(zero.lte(three).unwrap());
    assert!(negone.lte(three).unwrap());

    assert!(zero.gte(negone).unwrap());
    assert!(three.gte(zero).unwrap());
    assert!(three.gte(negone).unwrap());
}

proptest! {
    #[test]
    /// a lte a and gte a; a - 1, then + 1, then + 1 again are the
    /// reference's chain, and each lte and gte a as the reference values do.
    fn test_lte_gte_fuzz(a in arb_float()) {
        prop_assert!(a.lte(a).unwrap());
        prop_assert!(a.gte(a).unwrap());
        chain_against(a, |x, y| {
            let o = x.dec().cmp_value(&y.dec());
            prop_assert_eq!(x.lte(y).unwrap(), o != Ordering::Greater);
            prop_assert_eq!(x.gte(y).unwrap(), o != Ordering::Less);
            Ok(())
        })?;
    }
}

/// from_fixed_decimal_lossy: lossless for small values, lossy for U256::MAX.
#[test]
fn test_from_fixed_decimal_lossy() {
    // Test lossless conversions (values that fit in Float's precision)
    let lossless_cases = vec![
        (U256::from(0u128), 0u8, "0"),
        (U256::from(0u128), 18u8, "0"),
        (U256::from(1u128), 18u8, "1e-18"),
        (U256::from(123456789u128), 0u8, "123456789"),
        (U256::from(123456789u128), 2u8, "123456789e-2"),
        (U256::from(1000000000000000000u128), 18u8, "1"),
    ];

    for (amount, decimals, expected) in lossless_cases {
        let (float, lossless) =
            Float::from_fixed_decimal_lossy(amount, decimals).expect("should convert");
        let expected = Float::parse(expected.to_string()).unwrap();
        assert!(float.eq(expected).unwrap());
        assert!(
            lossless,
            "conversion should be lossless for amount={}, decimals={}",
            amount, decimals
        );
    }

    // Test lossy conversion with U256::MAX (too large to fit in Float's 224-bit coefficient)
    let (float, lossless) = Float::from_fixed_decimal_lossy(U256::MAX, 1).unwrap();
    assert!(!lossless, "U256::MAX conversion should be lossy");
    assert!(!float.is_zero().unwrap(), "result should not be zero");
}

/// to_fixed_decimal_lossy: correctly reports lossy/lossless for precision loss.
#[test]
fn test_to_fixed_decimal_lossy() {
    // Test lossy conversions (loss of precision)
    let lossy_cases = vec![
        (U256::from(1), 18u8, 0u128),
        (U256::from(123456789), 0u8, 12345678u128),
        (U256::from(123456789), 2u8, 12345678u128),
    ];

    for (input, decimals, expected) in lossy_cases {
        let float = Float::from_fixed_decimal(input, decimals + 1).unwrap();
        let (fixed, lossless) = float.to_fixed_decimal_lossy(decimals).unwrap();
        assert_eq!(
            fixed,
            U256::from(expected),
            "wrong value for input={}, decimals={}",
            input,
            decimals
        );
        assert!(
            !lossless,
            "should be lossy for input={}, decimals={}",
            input, decimals
        );
    }

    // Test lossless conversions (no loss of precision)
    let lossless_cases = vec![
        // Zero is always lossless
        (U256::from(0), 0u8, 0u128),
        (U256::from(0), 18u8, 0u128),
        // Converting 12340 with 3 decimals (12.340) to 2 decimals (12.34) is lossless
        (U256::from(12340), 3u8, 1234u128),
    ];

    for (input, decimals, expected) in lossless_cases {
        let float = Float::from_fixed_decimal(input, decimals + 1).unwrap();
        let (fixed, lossless) = float.to_fixed_decimal_lossy(decimals).unwrap();
        assert_eq!(
            fixed,
            U256::from(expected),
            "wrong value for input={}, decimals={}",
            input,
            decimals
        );
        assert!(
            lossless,
            "should be lossless for input={}, decimals={}",
            input, decimals
        );
    }
}

proptest! {
    #[test]
    /// Lossy fixed-decimal round-trip: from(d) then to(d'), for d' one below
    /// d or any, are the reference's. Where from(d) is lossless and d' is
    /// d - 1, to(d') is value / 10, lossy iff the last digit is nonzero.
    fn test_from_to_fixed_decimal_lossy_valid_range(
        value in crate::exact::u256(),
        decimals in any::<u8>(),
        other in any::<u8>(),
        below in any::<bool>(),
    ) {
        let to = if below { decimals.wrapping_sub(1) } else { other };
        let case = format!("from_fixed_decimal_lossy({value}, {decimals}), to {to}");
        let (from_d, from_lossless) = r::from_fixed_decimal_lossy(value, decimals);
        let (float, lossless) = Float::from_fixed_decimal_lossy(value, decimals).unwrap();
        prop_assert!(float.dec().eq_value(&from_d), "{case}: library {float:?}, reference {from_d:?}");
        prop_assert_eq!(lossless, from_lossless, "{}", case);

        let want = r::to_fixed_decimal_lossy(&from_d, to);
        agrees(&case, &float.to_fixed_decimal_lossy(to), &want, |l, w| l == w)?;
        if from_lossless && decimals > 0 && to == decimals - 1 {
            let ten = U256::from(10);
            prop_assert!(
                matches!(want, Ok((v, l)) if v == value / ten && l == (value % ten).is_zero()),
                "{case}: {want:?}"
            );
        }
    }
}

proptest! {
    #[test]
    /// Every positive Float is bounded by min/max_positive_value,
    /// every negative one by min/max_negative_value.
    fn test_constants_relationships(float in arb_float()) {
        let max_pos = Float::max_positive_value().unwrap();
        let min_pos = Float::min_positive_value().unwrap();
        let max_neg = Float::max_negative_value().unwrap();
        let min_neg = Float::min_negative_value().unwrap();
        let zero = Float::parse("0".to_string()).unwrap();

        // Test that constants are the extremes
        // Any positive float should be <= max_positive and >= min_positive
        if float.gt(zero).unwrap() {
            prop_assert!(float.lte(max_pos).unwrap());
            prop_assert!(float.gte(min_pos).unwrap());
        }

        // Any negative float should be <= max_negative and >= min_negative
        // (max_negative is closest to zero, min_negative is furthest from zero)
        if float.lt(zero).unwrap() {
            prop_assert!(float.lte(max_neg).unwrap());
            prop_assert!(float.gte(min_neg).unwrap());
        }

        // Constants should be consistent regardless of arbitrary float
        prop_assert!(max_pos.gt(zero).unwrap());
        prop_assert!(min_pos.gt(zero).unwrap());
        prop_assert!(max_neg.lt(zero).unwrap());
        prop_assert!(min_neg.lt(zero).unwrap());

        // Verify constants maintain their ordering
        prop_assert!(min_pos.lt(max_pos).unwrap());
        prop_assert!(min_neg.lt(max_neg).unwrap());
        prop_assert!(max_neg.lt(zero).unwrap());
        prop_assert!(min_pos.gt(zero).unwrap());
    }
}

proptest! {
    #[test]
    /// No arbitrary float exceeds max_positive or is below min_negative.
    fn test_constants_edge_cases(float in arb_float()) {
        let max_pos = Float::max_positive_value().unwrap();
        let min_pos = Float::min_positive_value().unwrap();
        let max_neg = Float::max_negative_value().unwrap();
        let min_neg = Float::min_negative_value().unwrap();

        // Constants should always be distinct
        prop_assert!(!max_pos.eq(min_pos).unwrap());
        prop_assert!(!max_neg.eq(min_neg).unwrap());
        prop_assert!(!max_pos.eq(max_neg).unwrap());
        prop_assert!(!min_pos.eq(min_neg).unwrap());

        // Test that constants are at the boundaries
        // (Note: We can't test arithmetic operations that would overflow/underflow
        // since those would fail, but we can test comparisons)

        // No arbitrary float should be greater than max_pos or less than min_neg
        if !float.eq(max_pos).unwrap() {
            prop_assert!(!float.gt(max_pos).unwrap());
        }
        if !float.eq(min_neg).unwrap() {
            prop_assert!(!float.lt(min_neg).unwrap());
        }
    }
}
