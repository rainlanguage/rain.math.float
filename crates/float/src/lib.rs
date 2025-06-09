use alloy::{primitives::FixedBytes, sol};

sol!(
    #![sol(all_derives = true)]
    DecimalFloat,
    "../../out/DecimalFloat.sol/DecimalFloat.json"
);

use DecimalFloat::Float as SolFloat;

pub struct Float(FixedBytes<32>);

// impl Float {
//     pub async fn new
// }
