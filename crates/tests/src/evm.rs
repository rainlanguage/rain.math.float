//! `TestDecimalFloat` and `TestDecimalFloatHarness` compiled from this source
//! (`build.rs`), run in revm through their constructors, called by their own
//! ABI.

use crate::reference::Dec;
use alloy::primitives::{Address, B256, Bytes, address};
use alloy::sol_types::SolCall;
use revm::context::result::{ExecutionResult, Output, SuccessReason};
use revm::context::{BlockEnv, CfgEnv, TxEnv};
use revm::database::InMemoryDB;
use revm::state::{AccountInfo, Bytecode};
use revm::{Context, DatabaseCommit, MainBuilder, MainContext, MainnetEvm, SystemCallEvm};
use std::cell::RefCell;

alloy::sol!(
    #![sol(all_derives)]
    TestDecimalFloat,
    "../../out/TestDecimalFloat.sol/TestDecimalFloat.json"
);

alloy::sol!(
    #![sol(all_derives)]
    TestDecimalFloatHarness,
    "../../out/TestDecimalFloatHarness.sol/TestDecimalFloatHarness.json"
);

pub const CONCRETE: Address = address!("00000000000000000000000000000000000f10a4");
pub const HARNESS: Address = address!("00000000000000000000000000000000000f10a5");

type Evm = MainnetEvm<Context<BlockEnv, TxEnv, CfgEnv, InMemoryDB>>;

fn put(db: &mut InMemoryDB, at: Address, code: Bytes) {
    db.insert_account_info(
        at,
        AccountInfo::default().with_code(Bytecode::new_legacy(code)),
    );
}

/// Runs `creation` as `at` and keeps the runtime code it returns.
fn create(db: &mut InMemoryDB, at: Address, creation: &Bytes) {
    put(db, at, creation.clone());
    let mut evm = Context::mainnet().with_db(db.clone()).build_mainnet();
    let created = evm.system_call(at, Bytes::new()).unwrap();
    let ExecutionResult::Success {
        output: Output::Call(runtime),
        ..
    } = created.result
    else {
        panic!("constructor at {at}: {:?}", created.result);
    };
    db.commit(created.state);
    put(db, at, runtime);
}

fn build() -> Evm {
    let mut db = InMemoryDB::default();
    create(&mut db, CONCRETE, &TestDecimalFloat::BYTECODE);
    create(&mut db, HARNESS, &TestDecimalFloatHarness::BYTECODE);
    Context::mainnet().with_db(db).build_mainnet()
}

thread_local! {
    static EVM: RefCell<Evm> = RefCell::new(build());
}

/// The decoded return, or the revert data. Anything else (a halt, a stop, a
/// revert without data) fails the test where it happens.
pub fn call<C: SolCall>(at: Address, c: C) -> Result<C::Return, Bytes> {
    let result = EVM.with(|evm| {
        evm.borrow_mut()
            .system_call(at, c.abi_encode().into())
            .unwrap()
            .result
    });
    match result {
        ExecutionResult::Success {
            reason: SuccessReason::Return,
            output: Output::Call(out),
            ..
        } => Ok(C::abi_decode_returns(&out).unwrap()),
        ExecutionResult::Revert { output, .. } if output.len() >= 4 => Err(output),
        other => panic!("{other:?}"),
    }
}

pub fn concrete<C: SolCall>(c: C) -> Result<C::Return, Bytes> {
    call(CONCRETE, c)
}

pub fn harness<C: SolCall>(c: C) -> Result<C::Return, Bytes> {
    call(HARNESS, c)
}

/// A float-valued call on the concrete.
pub fn float<C: SolCall<Return = B256>>(c: C) -> Result<Dec, Bytes> {
    concrete(c).map(Dec::from_bytes)
}
