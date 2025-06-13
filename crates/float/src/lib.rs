#[cfg(test)]
use alloy::primitives::aliases::I224;
use alloy::primitives::{Address, Bytes, FixedBytes};
use alloy::sol_types::{SolError, SolInterface};
use alloy::{sol, sol_types::SolCall};
use once_cell::unsync::Lazy;
use revm::context::result::{EVMError, ExecutionResult, HaltReason, Output, SuccessReason};
use revm::context::{BlockEnv, CfgEnv, Evm, TxEnv};
use revm::database::InMemoryDB;
use revm::handler::EthPrecompiles;
use revm::handler::instructions::EthInstructions;
use revm::interpreter::interpreter::EthInterpreter;
use revm::primitives::{address, fixed_bytes};
use revm::{Context, MainBuilder, MainContext, SystemCallEvm};
use std::cell::RefCell;
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
    static LOCAL_EVM: Lazy<RefCell<LocalEvm>> = Lazy::new(|| {
        let mut db = InMemoryDB::default();
        let bytecode = revm::state::Bytecode::new_legacy(DecimalFloat::DEPLOYED_BYTECODE.clone());
        let account_info = revm::state::AccountInfo::default().with_code(bytecode);
        db.insert_account_info(FLOAT_ADDRESS, account_info);

        let evm = Context::mainnet().with_db(db).build_mainnet();
        RefCell::new(evm)
    });
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
    #[allow(dead_code)] // will be used in future tests
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

    pub fn format(self) -> Result<String, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::formatCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::formatCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    pub fn add(self, b: Self) -> Result<Self, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::addCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::addCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    pub fn sub(self: Self, b: Self) -> Result<Self, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::subCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::subCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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
        // NOTE: LibFormatDecimalFloat.toDecimalString currently uses 18 decimal places
        // TODO: make this fail on a separate PR
        let err = float.format().unwrap_err();

        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::LossyConversionFromFloat(_))
        ));
    }

    #[test]
    fn test_parse_edge_cases() {
        let float = Float::parse("1.2.3".to_string()).unwrap();
        let string = float.format().unwrap();
        assert_eq!(string, "1.2");

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

    proptest! {
        #[test]
        fn test_add(a in reasonable_float(), b in reasonable_float()) {
            a.add(b).unwrap();
        }
    }

    proptest! {
        #[test]
        fn test_sub(a in reasonable_float(), b in reasonable_float()) {
            a.sub(b).unwrap();
        }
    }

    proptest! {
        #[test]
        fn test_add_sub(a in reasonable_float(), b in reasonable_float()) {
            let sum = a.add(b).unwrap();
            let diff = sum.sub(b).unwrap();
            prop_assert_eq!(
                a.format().unwrap(),
                diff.format().unwrap(),
                "a: {}, b: {}",
                a.format().unwrap(),
                b.format().unwrap(),
            );
        }
    }
}
