#[cfg(test)]
mod tests {
    use crate::Float;
    use alloy::primitives::{aliases::I224, I256};
    use proptest::prelude::*;

    /// Convert a Solidity Float to f64 via unpack.
    fn sol_to_f64(f: Float) -> Option<f64> {
        let (coeff, exp) = f.unpack().ok()?;
        let c: f64 = i256_to_f64(coeff);
        let e: i32 = exp.as_i32();
        Some(c * 10.0_f64.powi(e))
    }

    fn i256_to_f64(v: I256) -> f64 {
        if v.is_negative() {
            let abs = (!v).wrapping_add(I256::ONE);
            -(u256_to_f64(abs.into_raw()))
        } else {
            u256_to_f64(v.into_raw())
        }
    }

    fn u256_to_f64(v: alloy::primitives::U256) -> f64 {
        // Convert U256 to f64 via string parsing for accuracy.
        v.to_string().parse::<f64>().unwrap_or(f64::INFINITY)
    }

    /// Generate floats in a range where f64 can represent them without
    /// overflow/underflow. Coefficients up to ~1e15 and exponents -15..15
    /// keep values in f64's comfortable range.
    prop_compose! {
        fn f64_compatible_float()(
            coefficient in -10i64.pow(15)..10i64.pow(15),
            exponent in -15i32..15i32,
        ) -> Float {
            Float::pack_lossless(
                I224::try_from(coefficient).unwrap(),
                exponent,
            ).unwrap()
        }
    }

    /// Check that two f64 values are approximately equal, allowing for
    /// f64 rounding errors. Returns true if they're within a relative
    /// tolerance of 1e-10 or both are effectively zero.
    fn approx_eq(a: f64, b: f64) -> bool {
        if a == b {
            return true;
        }
        if a.is_nan() || b.is_nan() {
            return false;
        }
        let max_abs = a.abs().max(b.abs());
        if max_abs < 1e-30 {
            return true;
        }
        ((a - b).abs() / max_abs) < 1e-10
    }

    proptest! {
        #[test]
        fn fuzz_add(
            a in f64_compatible_float(),
            b in f64_compatible_float(),
        ) {
            let sol_result = (a + b).unwrap();
            let a_f64 = sol_to_f64(a).unwrap();
            let b_f64 = sol_to_f64(b).unwrap();
            let expected = a_f64 + b_f64;
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "add: {a_f64} + {b_f64} = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_sub(
            a in f64_compatible_float(),
            b in f64_compatible_float(),
        ) {
            let sol_result = (a - b).unwrap();
            let a_f64 = sol_to_f64(a).unwrap();
            let b_f64 = sol_to_f64(b).unwrap();
            let expected = a_f64 - b_f64;
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "sub: {a_f64} - {b_f64} = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_mul(
            a in f64_compatible_float(),
            b in f64_compatible_float(),
        ) {
            let sol_result = (a * b).unwrap();
            let a_f64 = sol_to_f64(a).unwrap();
            let b_f64 = sol_to_f64(b).unwrap();
            let expected = a_f64 * b_f64;
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "mul: {a_f64} * {b_f64} = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_div(
            a in f64_compatible_float(),
            b in f64_compatible_float(),
        ) {
            let b_f64 = sol_to_f64(b).unwrap();
            // Skip division by zero.
            prop_assume!(b_f64.abs() > 1e-30);

            let sol_result = (a / b).unwrap();
            let a_f64 = sol_to_f64(a).unwrap();
            let expected = a_f64 / b_f64;
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "div: {a_f64} / {b_f64} = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_neg(a in f64_compatible_float()) {
            let sol_result = (-a).unwrap();
            let a_f64 = sol_to_f64(a).unwrap();
            let expected = -a_f64;
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "neg: -{a_f64} = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_abs(a in f64_compatible_float()) {
            let sol_result = a.abs().unwrap();
            let a_f64 = sol_to_f64(a).unwrap();
            let expected = a_f64.abs();
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "abs: |{a_f64}| = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_inv(a in f64_compatible_float()) {
            let a_f64 = sol_to_f64(a).unwrap();
            // Skip values too close to zero.
            prop_assume!(a_f64.abs() > 1e-10);

            let sol_result = a.inv().unwrap();
            let expected = 1.0 / a_f64;
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "inv: 1/{a_f64} = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_floor(a in f64_compatible_float()) {
            let a_f64 = sol_to_f64(a).unwrap();
            let sol_result = a.floor().unwrap();
            let expected = a_f64.floor();
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "floor: floor({a_f64}) = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_integer(a in f64_compatible_float()) {
            let a_f64 = sol_to_f64(a).unwrap();
            let sol_result = a.integer().unwrap();
            let expected = a_f64.trunc();
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "integer: trunc({a_f64}) = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_frac(
            coefficient in -10i64.pow(10)..10i64.pow(10),
            exponent in -5i32..0i32,
        ) {
            let a = Float::pack_lossless(
                I224::try_from(coefficient).unwrap(),
                exponent,
            ).unwrap();
            let a_f64 = sol_to_f64(a).unwrap();
            let sol_result = a.frac().unwrap();
            let expected = a_f64.fract();
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                (expected - actual).abs() < 1e-6,
                "frac: fract({a_f64}) = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_min(
            a in f64_compatible_float(),
            b in f64_compatible_float(),
        ) {
            let sol_result = a.min(b).unwrap();
            let a_f64 = sol_to_f64(a).unwrap();
            let b_f64 = sol_to_f64(b).unwrap();
            let expected = a_f64.min(b_f64);
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "min: min({a_f64}, {b_f64}) = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_max(
            a in f64_compatible_float(),
            b in f64_compatible_float(),
        ) {
            let sol_result = a.max(b).unwrap();
            let a_f64 = sol_to_f64(a).unwrap();
            let b_f64 = sol_to_f64(b).unwrap();
            let expected = a_f64.max(b_f64);
            let actual = sol_to_f64(sol_result).unwrap();
            prop_assert!(
                approx_eq(expected, actual),
                "max: max({a_f64}, {b_f64}) = {expected}, sol = {actual}",
            );
        }

        #[test]
        fn fuzz_is_zero(a in f64_compatible_float()) {
            let a_f64 = sol_to_f64(a).unwrap();
            let sol_result = a.is_zero().unwrap();
            let expected = a_f64 == 0.0;
            prop_assert!(
                sol_result == expected,
                "is_zero: is_zero({}) = {}, sol = {}",
                a_f64, expected, sol_result
            );
        }

        #[test]
        fn fuzz_fixed_decimal_round_trip(
            coefficient in 0i64..10i64.pow(15),
            decimals in 0u8..18u8,
        ) {
            use alloy::primitives::U256;
            let value = U256::from(coefficient as u64);
            // Convert to float and back.
            let float = Float::from_fixed_decimal(value, decimals);
            prop_assume!(float.is_ok());
            let float = float.unwrap();
            let (back, lossless) = float.to_fixed_decimal_lossy(decimals).unwrap();
            if lossless {
                prop_assert!(
                    back == value,
                    "round-trip failed: {} with {} decimals, got {}",
                    coefficient, decimals, back
                );
            }
        }

        #[test]
        fn fuzz_comparisons(
            a in f64_compatible_float(),
            b in f64_compatible_float(),
        ) {
            let a_f64 = sol_to_f64(a).unwrap();
            let b_f64 = sol_to_f64(b).unwrap();

            // Only test comparisons when values are far enough apart
            // that f64 precision issues don't cause false failures.
            let diff = (a_f64 - b_f64).abs();
            let max_abs = a_f64.abs().max(b_f64.abs());
            prop_assume!(diff > max_abs * 1e-10 || diff < 1e-30);

            let sol_lt = a.lt(b).unwrap();
            let sol_gt = a.gt(b).unwrap();
            let sol_eq = a.eq(b).unwrap();

            if diff < 1e-30 {
                // Both effectively zero.
                prop_assert!(sol_eq, "eq: {a_f64} == {b_f64} should be true");
            } else if a_f64 < b_f64 {
                prop_assert!(sol_lt, "lt: {a_f64} < {b_f64} should be true");
                prop_assert!(!sol_gt, "gt: {a_f64} > {b_f64} should be false");
            } else {
                prop_assert!(sol_gt, "gt: {a_f64} > {b_f64} should be true");
                prop_assert!(!sol_lt, "lt: {a_f64} < {b_f64} should be false");
            }
        }
    }
}
