use alloy::primitives::{Address, Bytes};
use alloy::sol_types::SolInterface;
use revm::context::result::{ExecutionResult, Output, SuccessReason};
use revm::context::{BlockEnv, CfgEnv, Evm, TxEnv};
use revm::database::InMemoryDB;
use revm::handler::EthPrecompiles;
use revm::handler::instructions::EthInstructions;
use revm::interpreter::interpreter::EthInterpreter;
use revm::primitives::address;
use revm::{Context, MainBuilder, MainContext, SystemCallEvm};
use std::cell::RefCell;

use crate::{DecimalFloat, FloatError};

/// Fixed address where the DecimalFloat contract is deployed in the in-memory EVM.
/// This arbitrary address is used consistently across all Calculator instances.
pub(crate) const FLOAT_ADDRESS: Address = address!("00000000000000000000000000000000000f10a2");

type EvmContext = Context<BlockEnv, TxEnv, CfgEnv, InMemoryDB>;
type LocalEvm = Evm<EvmContext, (), EthInstructions<EthInterpreter, EvmContext>, EthPrecompiles>;

thread_local! {
    pub(crate) static LOCAL_EVM: RefCell<LocalEvm> = {
        let mut db = InMemoryDB::default();
        let bytecode = revm::state::Bytecode::new_legacy(DecimalFloat::DEPLOYED_BYTECODE.clone());
        let account_info = revm::state::AccountInfo::default().with_code(bytecode);
        db.insert_account_info(FLOAT_ADDRESS, account_info);

        let evm = Context::mainnet().with_db(db).build_mainnet();
        RefCell::new(evm)
    };
}

pub(crate) fn execute_call<F, T>(calldata: Bytes, process_output: F) -> Result<T, FloatError>
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
