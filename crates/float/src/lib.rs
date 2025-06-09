use DecimalFloat::Float as SolFloat;
use alloy::primitives::{Address, Bytes, FixedBytes};
use alloy::sol_types::SolInterface;
use alloy::{sol, sol_types::SolCall};
use revm::context::result::{
    EVMError, ExecutionResult, HaltReason, Output, ResultAndState, SuccessReason,
};
use revm::context::{BlockEnv, CfgEnv, Evm, TxEnv};
use revm::database::InMemoryDB;
use revm::handler::EthPrecompiles;
use revm::handler::instructions::EthInstructions;
use revm::interpreter::interpreter::EthInterpreter;
use revm::primitives::{address, fixed_bytes};
use revm::{Context, MainBuilder, MainContext, SystemCallEvm};
use thiserror::Error;

sol!(
    #![sol(all_derives = true)]
    DecimalFloat,
    "../../out/DecimalFloat.sol/DecimalFloat.json"
);

const FLOAT_ADDRESS: Address = address!("00000000000000000000000000000000000f10a2");

#[derive(Debug, Error)]
pub enum CalculatorError {
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
    DecimalFloat(DecimalFloat::DecimalFloatErrors),
}

// type EvmContext = Context<BlockEnv, TxEnv, CfgEnv, InMemoryDB>;
// struct Calculator(Evm<EvmContext, (), EthInstructions<EthInterpreter, EvmContext>, EthPrecompiles>);

// impl Calculator {
//     fn new() -> Result<Self, CalculatorError> {}
// }

pub struct Float(FixedBytes<32>);

impl Float {
    fn as_sol(&self) -> SolFloat {
        let Float(bytes) = self;
        SolFloat::from_underlying(*bytes)
    }

    pub fn parse(str: String) -> Result<Self, CalculatorError> {
        let mut db = InMemoryDB::default();
        let bytecode = revm::state::Bytecode::new_legacy(DecimalFloat::DEPLOYED_BYTECODE.clone());
        let account_info = revm::state::AccountInfo::default().with_code(bytecode);
        db.insert_account_info(FLOAT_ADDRESS, account_info);

        let mut evm = Context::mainnet().with_db(db).build_mainnet();

        let calldata = DecimalFloat::parseCall { str }.abi_encode();

        let result_and_state =
            evm.transact_system_call_finalize(FLOAT_ADDRESS, Bytes::from(calldata))?;

        match result_and_state.result {
            ExecutionResult::Success {
                reason: SuccessReason::Return,
                output: Output::Call(output),
                ..
            } => {
                let decoded = DecimalFloat::parseCall::abi_decode_returns(output.as_ref())?;

                let error_selector = decoded._0;
                let parsed_float = decoded._1;

                if error_selector != fixed_bytes!("00000000") {
                    let decoded_err =
                        DecimalFloat::DecimalFloatErrors::abi_decode(error_selector.as_slice())?;
                    return Err(CalculatorError::DecimalFloat(decoded_err));
                }

                Ok(Float(parsed_float))
            }
            ExecutionResult::Success { reason, output, .. } => {
                Err(CalculatorError::UnexpectedSuccess(reason, output))
            }
            ExecutionResult::Revert { output, .. } => Err(CalculatorError::Revert(output)),
            ExecutionResult::Halt { reason, .. } => Err(CalculatorError::Halt(reason)),
        }
    }

    pub fn format(self) -> Result<String, CalculatorError> {
        let mut db = InMemoryDB::default();
        let bytecode = revm::state::Bytecode::new_legacy(DecimalFloat::DEPLOYED_BYTECODE.clone());
        let account_info = revm::state::AccountInfo::default().with_code(bytecode);
        db.insert_account_info(FLOAT_ADDRESS, account_info);

        let mut evm = Context::mainnet().with_db(db).build_mainnet();

        let Float(a) = self;
        let calldata = DecimalFloat::formatCall { a }.abi_encode();

        let result_and_state =
            evm.transact_system_call_finalize(FLOAT_ADDRESS, Bytes::from(calldata))?;

        match result_and_state.result {
            ExecutionResult::Success {
                reason: SuccessReason::Return,
                output: Output::Call(output),
                ..
            } => {
                let decoded = DecimalFloat::formatCall::abi_decode_returns(output.as_ref())?;

                Ok(decoded)
            }
            ExecutionResult::Success { reason, output, .. } => {
                Err(CalculatorError::UnexpectedSuccess(reason, output))
            }
            ExecutionResult::Revert { output, .. } => Err(CalculatorError::Revert(output)),
            ExecutionResult::Halt { reason, .. } => Err(CalculatorError::Halt(reason)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_and_float() {
        let float = Float::parse("1.23456789".to_string()).unwrap();
        let string = float.format().unwrap();
        assert_eq!(string, "1.23456789");
    }
}
