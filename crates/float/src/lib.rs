#[cfg(test)]
use alloy::primitives::aliases::I224;
use alloy::primitives::{Address, Bytes, FixedBytes};
use alloy::sol_types::{SolError, SolInterface};
use alloy::{sol, sol_types::SolCall};
use revm::context::result::{EVMError, ExecutionResult, HaltReason, Output, SuccessReason};
use revm::context::{BlockEnv, CfgEnv, Evm, TxEnv};
use revm::database::InMemoryDB;
use revm::handler::EthPrecompiles;
use revm::handler::instructions::EthInstructions;
use revm::interpreter::interpreter::EthInterpreter;
use revm::primitives::{address, fixed_bytes};
use revm::{Context, MainBuilder, MainContext, SystemCallEvm};
use std::cell::RefCell;
use std::ops::{Add, Div, Mul, Sub};
use std::thread::AccessError;
use thiserror::Error;

sol!(
    #![sol(all_derives)]
    DecimalFloat,
    "../../out/DecimalFloat.sol/DecimalFloat.json"
);

type EvmContext = Context<BlockEnv, TxEnv, CfgEnv, InMemoryDB>;
type LocalEvm = Evm<EvmContext, (), EthInstructions<EthInterpreter, EvmContext>, EthPrecompiles>;

thread_local! {
    static LOCAL_EVM: RefCell<LocalEvm> = {
        let mut db = InMemoryDB::default();
        let bytecode = revm::state::Bytecode::new_legacy(DecimalFloat::DEPLOYED_BYTECODE.clone());
        let account_info = revm::state::AccountInfo::default().with_code(bytecode);
        db.insert_account_info(FLOAT_ADDRESS, account_info);

        let evm = Context::mainnet().with_db(db).build_mainnet();
        RefCell::new(evm)
    };
}

use DecimalFloat::DecimalFloatErrors;

/// Fixed address where the DecimalFloat contract is deployed in the in-memory EVM.
/// This arbitrary address is used consistently across all Calculator instances.
const FLOAT_ADDRESS: Address = address!("00000000000000000000000000000000000f10a2");

#[derive(Debug, Error)]
pub enum FloatError {
    #[error("EVM error: {0}")]
    Evm(#[from] EVMError<std::convert::Infallible>),
    #[error("Float execution reverted with output: {0}")]
    Revert(Bytes),
    #[error("Float execution halted with reason: {0:?}")]
    Halt(HaltReason),
    #[error("Execution ended for non-return reason. Reason: {0:?}. Output: {1:?}")]
    UnexpectedSuccess(SuccessReason, Output),
    #[error(transparent)]
    AlloySolTypes(#[from] alloy::sol_types::Error),
    #[error("Decimal Float error: {0:?}")]
    DecimalFloat(DecimalFloatErrors),
    #[error("Decimal Float error selector: {0:?}")]
    DecimalFloatSelector(Result<DecimalFloatErrorSelector, FixedBytes<4>>),
    #[error(transparent)]
    Access(#[from] AccessError),
}

#[derive(Debug)]
pub enum DecimalFloatErrorSelector {
    CoefficientOverflow,
    ExponentOverflow,
    Log10Negative,
    Log10Zero,
    LossyConversionFromFloat,
    NegativeFixedDecimalConversion,
    WithTargetExponentOverflow,
}

impl TryFrom<FixedBytes<4>> for DecimalFloatErrorSelector {
    type Error = FixedBytes<4>;

    fn try_from(error_selector: FixedBytes<4>) -> Result<Self, Self::Error> {
        let FixedBytes(bytes) = error_selector;
        match bytes {
            <DecimalFloat::CoefficientOverflow as SolError>::SELECTOR => {
                Ok(Self::CoefficientOverflow)
            }
            <DecimalFloat::ExponentOverflow as SolError>::SELECTOR => Ok(Self::ExponentOverflow),
            <DecimalFloat::Log10Negative as SolError>::SELECTOR => Ok(Self::Log10Negative),
            <DecimalFloat::Log10Zero as SolError>::SELECTOR => Ok(Self::Log10Zero),
            <DecimalFloat::LossyConversionFromFloat as SolError>::SELECTOR => {
                Ok(Self::LossyConversionFromFloat)
            }
            <DecimalFloat::NegativeFixedDecimalConversion as SolError>::SELECTOR => {
                Ok(Self::NegativeFixedDecimalConversion)
            }
            <DecimalFloat::WithTargetExponentOverflow as SolError>::SELECTOR => {
                Ok(Self::WithTargetExponentOverflow)
            }
            _ => Err(error_selector),
        }
    }
}

fn execute_call<F, T>(calldata: Bytes, process_output: F) -> Result<T, FloatError>
where
    F: FnOnce(Bytes) -> Result<T, FloatError>,
{
    let result = LOCAL_EVM.try_with(|evm| {
        let evm = &mut *evm.borrow_mut();
        let result_and_state = evm.transact_system_call_finalize(FLOAT_ADDRESS, calldata)?;

        Ok::<_, FloatError>(result_and_state.result)
    })??;

    match result {
        ExecutionResult::Success {
            reason: SuccessReason::Return,
            output: Output::Call(output),
            ..
        } => process_output(output),
        ExecutionResult::Success { reason, output, .. } => {
            Err(FloatError::UnexpectedSuccess(reason, output))
        }
        ExecutionResult::Revert { output, .. } => {
            if let Ok(error) = DecimalFloat::DecimalFloatErrors::abi_decode(output.as_ref()) {
                return Err(FloatError::DecimalFloat(error));
            }

            Err(FloatError::Revert(output))
        }
        ExecutionResult::Halt { reason, .. } => Err(FloatError::Halt(reason)),
    }
}

#[derive(Debug, Copy, Clone, PartialEq)]
pub struct Float(FixedBytes<32>);

impl Float {
    #[cfg(test)]
    fn pack_lossless(coefficient: I224, exponent: i32) -> Result<Self, FloatError> {
        let calldata = DecimalFloat::packLosslessCall {
            coefficient,
            exponent,
        }
        .abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::packLosslessCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    #[cfg(test)]
    fn unpack(self) -> Result<(I224, i32), FloatError> {
        let Float(float) = self;
        let calldata = DecimalFloat::unpackCall { float }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let DecimalFloat::unpackReturn {
                _0: coefficient,
                _1: exponent,
            } = DecimalFloat::unpackCall::abi_decode_returns(output.as_ref())?;

            Ok((coefficient, exponent))
        })
    }

    #[cfg(test)]
    fn show_unpacked(self) -> Result<String, FloatError> {
        let (coefficient, exponent) = self.unpack()?;
        Ok(format!("{coefficient}e{exponent}"))
    }

    pub fn parse(str: String) -> Result<Self, FloatError> {
        let calldata = DecimalFloat::parseCall { str }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let DecimalFloat::parseReturn {
                _0: error_selector,
                _1: parsed_float,
            } = DecimalFloat::parseCall::abi_decode_returns(output.as_ref())?;

            if error_selector != fixed_bytes!("00000000") {
                let selector = DecimalFloatErrorSelector::try_from(error_selector);
                return Err(FloatError::DecimalFloatSelector(selector));
            }

            Ok(Float(parsed_float))
        })
    }

    // NOTE: LibFormatDecimalFloat.toDecimalString currently uses 18 decimal places
    pub fn format(self) -> Result<String, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::formatCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::formatCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    pub fn lt(self, b: Self) -> Result<bool, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::ltCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::ltCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    pub fn eq(self, b: Self) -> Result<bool, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::eqCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::eqCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    pub fn gt(self, b: Self) -> Result<bool, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::gtCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::gtCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    pub fn minus(self) -> Result<Self, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::minusCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::minusCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    pub fn inv(self) -> Result<Self, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::invCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::invCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

impl Add for Float {
    type Output = Result<Self, FloatError>;

    fn add(self, b: Self) -> Self::Output {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::addCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::addCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

impl Sub for Float {
    type Output = Result<Self, FloatError>;

    fn sub(self, b: Self) -> Self::Output {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::subCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::subCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

impl Mul for Float {
    type Output = Result<Self, FloatError>;

    fn mul(self, b: Self) -> Self::Output {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::mulCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::mulCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

impl Div for Float {
    type Output = Result<Self, FloatError>;

    fn div(self, b: Self) -> Self::Output {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::divCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::divCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::str::FromStr;
    use proptest::prelude::*;

    prop_compose! {
        fn arb_float()(
            coefficient in any::<I224>(),
            exponent in any::<i32>(),
        ) -> Float {
            Float::pack_lossless(coefficient, exponent).unwrap()
        }
    }

    prop_compose! {
        fn reasonable_float()(
            int_part in -10i128.pow(18)..10i128.pow(18),
            decimal_part in 0u128..10u128.pow(18u32)
        ) -> Float {
            let num_str = if decimal_part == 0 {
                format!("{int_part}")
            } else {
                format!("{int_part}.{decimal_part}")
            };

            Float::parse(num_str).unwrap()
        }
    }

    #[test]
    fn test_parse_and_format() {
        let float = Float::parse("1.1341234234625468391".to_string()).unwrap();
        let err = float.format().unwrap_err();

        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::LossyConversionFromFloat(_))
        ));
    }

    #[test]
    fn test_parse_empty_string_error() {
        let err = Float::parse("".to_string()).unwrap_err();
        // We don't know the exact selector here, just ensure the error path is hit.
        assert!(matches!(err, FloatError::DecimalFloatSelector(_)));
    }

    #[test]
    fn test_parse_exponent_overflow_error() {
        // Extremely large exponent expected to overflow (exponent >> i32::MAX).
        let err = Float::parse("1e3000000000".to_string()).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    #[test]
    fn test_parse_edge_cases() {
        let err = Float::parse("1.2.3".to_string()).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloatSelector(Err(selector))
            if selector == fixed_bytes!("ad384e87")
        ));

        let err = Float::parse("abc".to_string()).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloatSelector(Err(selector))
            if selector == fixed_bytes!("34bd2069")
        ));
    }

    proptest! {
        #[test]
        fn test_parse_format(float in reasonable_float()) {
            let formatted = float.format().unwrap();
            let parsed = Float::parse(formatted.clone()).unwrap();
            prop_assert_eq!(float.0, parsed.0);
        }
    }

    #[test]
    fn test_add_exponent_overflow_error() {
        let max_coeff_str = "13479973333575319897333507543509815336818572211270286240551805124607";
        let large_coeff_i224 = I224::from_str(max_coeff_str).unwrap();
        let exponent_max = i32::MAX;

        let a = Float::pack_lossless(large_coeff_i224, exponent_max).unwrap();

        let err = (a + a).unwrap_err();

        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    #[test]
    fn test_sub_exponent_overflow_error() {
        let max_coeff_str = "13479973333575319897333507543509815336818572211270286240551805124607";
        let large_coeff_i224 = I224::from_str(max_coeff_str).unwrap();
        let exponent_max = i32::MAX;

        let a = Float::pack_lossless(large_coeff_i224, exponent_max).unwrap();
        let b = Float::pack_lossless(-large_coeff_i224, exponent_max).unwrap();

        let err = (b - a).unwrap_err();

        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    proptest! {
        #[test]
        fn test_add(a in reasonable_float(), b in reasonable_float()) {
            (a + b).unwrap();
        }
    }

    proptest! {
        #[test]
        fn test_sub(a in reasonable_float(), b in reasonable_float()) {
            (a - b).unwrap();
        }
    }

    proptest! {
        #[test]
        fn test_add_sub(a in reasonable_float(), b in reasonable_float()) {
            let sum = (a + b).unwrap();
            let diff = (sum - b).unwrap();
            prop_assert_eq!(
                a.format().unwrap(),
                diff.format().unwrap(),
                "a: {}, b: {}",
                a.format().unwrap(),
                b.format().unwrap(),
            );
        }
    }

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
        fn test_lt_eq_gt_with_add(a in reasonable_float()) {
            let b = a;
            let eq = a.eq(b).unwrap();
            prop_assert!(eq);

            let one = Float::parse("1".to_string()).unwrap();

            let a = (a - one).unwrap();
            let lt = a.lt(b).unwrap();
            prop_assert!(lt);

            let a = (a + one).unwrap();
            let eq = a.eq(b).unwrap();
            prop_assert!(eq);

            let a = (a + one).unwrap();
            let gt = a.gt(b).unwrap();
            prop_assert!(gt);
        }

        #[test]
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

    proptest! {
        #[test]
        fn test_mul(a in reasonable_float(), b in reasonable_float()) {
            (a * b).unwrap();
        }
    }

    #[test]
    fn test_minus_format() {
        let float = Float::parse("-123.1234234625468391".to_string()).unwrap();
        let negated = float.minus().unwrap();
        let formatted = negated.format().unwrap();
        assert_eq!(formatted, "123.1234234625468391");

        let float = Float::parse(formatted).unwrap();
        let negated = float.minus().unwrap();
        let formatted = negated.format().unwrap();
        assert_eq!(formatted, "-123.1234234625468391");

        let float = Float::parse("0".to_string()).unwrap();
        let negated = float.minus().unwrap();
        let formatted = negated.format().unwrap();
        assert_eq!(formatted, "0");
    }

    proptest! {
        #[test]
        fn test_minus_minus(float in arb_float()) {
            let negated = float.minus().unwrap();
            let renegated = negated.minus().unwrap();
            prop_assert!(float.eq(renegated).unwrap());
        }
    }

    proptest! {
        #[test]
        fn test_inv_prod(float in reasonable_float()) {
            let inv = float.inv().unwrap();
            let product = (float * inv).unwrap();
            let one = Float::parse("1".to_string()).unwrap();

            // Allow for minor rounding errors introduced by the lossy
            // `inv` implementation. We consider the property to
            // hold if the product is within `±1e-37` of 1.

            let eps = Float::parse("1e-37".to_string()).unwrap();
            let one_plus_eps = (one + eps).unwrap();
            let one_minus_eps = (one - eps).unwrap();

            let within_upper = !product.gt(one_plus_eps).unwrap();
            let within_lower = !product.lt(one_minus_eps).unwrap();

            prop_assert!(
                within_upper && within_lower,
                "float: {}, inv: {}, product: {} (not within ±ε)",
                float.show_unpacked().unwrap(),
                inv.show_unpacked().unwrap(),
                product.show_unpacked().unwrap(),
            );
        }
    }

    proptest! {
        #[test]
        fn test_div(a in reasonable_float(), b in reasonable_float()) {
            let zero = Float::parse("0".to_string()).unwrap();
            prop_assume!(!b.eq(zero).unwrap());

            (a / b).unwrap();
        }
    }

    prop_compose! {
        fn small_int_float()(int_part in -1_000_000_000_000i128..1_000_000_000_000i128) -> Float {
            Float::parse(int_part.to_string()).unwrap()
        }
    }

    proptest! {
        #[test]
        fn test_mul_div_int(a in small_int_float(), b in small_int_float()) {
            let zero = Float::parse("0".to_string()).unwrap();
            prop_assume!(!b.eq(zero).unwrap());

            let product = (a * b).unwrap();
            let quotient = (product / b).unwrap();

            prop_assert!(
                a.eq(quotient).unwrap(),
                "a: {}, quotient: {}, b: {}",
                a.show_unpacked().unwrap(),
                quotient.show_unpacked().unwrap(),
                b.show_unpacked().unwrap()
            );
        }
    }

    #[test]
    fn test_mul_div_manual() {
        let two = Float::parse("2".to_string()).unwrap();
        let three = Float::parse("3".to_string()).unwrap();
        let six = Float::parse("6".to_string()).unwrap();

        assert!(two.eq((six / three).unwrap()).unwrap());
        assert!(six.eq((two * three).unwrap()).unwrap());
    }

    #[test]
    fn test_divide_by_zero_error() {
        let one = Float::parse("1".to_string()).unwrap();
        let zero = Float::parse("0".to_string()).unwrap();
        let err = (one / zero).unwrap_err();

        assert!(matches!(err, FloatError::Revert(_)));
    }

    #[test]
    fn test_mul_exponent_overflow_error() {
        let near_max_exp = Float::parse("1e2147483646".to_string()).unwrap();
        let one_e_two = Float::parse("1e2".to_string()).unwrap();

        let err = (near_max_exp * one_e_two).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    #[test]
    fn test_div_exponent_overflow_error() {
        let near_max_exp = Float::parse("1e2147483646".to_string()).unwrap();
        let one_e_neg_hundred = Float::parse("1e-100".to_string()).unwrap();

        let err = (near_max_exp / one_e_neg_hundred).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    #[test]
    fn test_mul_exponent_underflow_error() {
        let near_min_exp = Float::parse("1e-2147483646".to_string()).unwrap();
        let one_e_neg_three = Float::parse("1e-3".to_string()).unwrap();

        let err = (near_min_exp * one_e_neg_three).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }
}
