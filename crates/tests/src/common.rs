//! Helpers more than one test module uses, each defined once here.

use crate::reference::Dec;
use alloy::primitives::{I256, U256, keccak256};
use num_bigint::BigInt;
use proptest::test_runner::TestCaseError;

/// The signature of the error `parse` returns by selector for a string with
/// no digits where a number starts. `RefError` has no variant for it.
pub(crate) const PARSE_EMPTY_DECIMAL_STRING: &str = "ParseEmptyDecimalString(uint256)";

/// A check as a plain test: its failure is the panic.
pub(crate) fn run(r: Result<(), TestCaseError>) {
    if let Err(e) = r {
        panic!("{e}");
    }
}

/// 1 as an unpacked Float.
pub(crate) fn one() -> Dec {
    Dec::new(1, 0)
}

/// 2 as an unpacked Float.
pub(crate) fn two() -> Dec {
    Dec::new(2, 0)
}

/// The four-byte selector of an error signature.
pub(crate) fn selector(signature: &str) -> [u8; 4] {
    keccak256(signature.as_bytes())[..4].try_into().unwrap()
}

/// A BigInt as an alloy int256, which it must fit.
pub(crate) fn i256(v: &BigInt) -> I256 {
    I256::from_dec_str(&v.to_string()).unwrap()
}

/// A BigInt as an alloy uint256, which it must fit.
pub(crate) fn u256(v: &BigInt) -> U256 {
    U256::from_str_radix(&v.to_string(), 10).unwrap()
}

/// A BigInt as its int256 ABI word, which it must fit.
pub(crate) fn word(v: &BigInt) -> [u8; 32] {
    i256(v).to_be_bytes::<32>()
}
