use DecimalFloat::Float as SolFloat;
use alloy::{primitives::FixedBytes, sol};
use lazy_static::lazy_static;
use revm::{database::InMemoryDB, primitives::address};

sol!(
    #![sol(all_derives = true)]
    DecimalFloat,
    "../../out/DecimalFloat.sol/DecimalFloat.json"
);

lazy_static! {
    static ref DB: InMemoryDB = {
        let mut db = InMemoryDB::default();
        let bytecode = revm::state::Bytecode::new_legacy(DecimalFloat::BYTECODE.clone());
        let account_info = revm::state::AccountInfo::default().with_code(bytecode);
        db.insert_account_info(
            address!("00000000000000000000000000000000000f10a2"),
            account_info,
        );
        db
    };
}

pub struct Float(FixedBytes<32>);

// impl Float {
//     pub async fn new
// }
