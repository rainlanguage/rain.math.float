use alloy::primitives::{Bytes, FixedBytes};
use alloy::sol_types::SolError;
use revm::context::result::{EVMError, HaltReason, Output, SuccessReason};
use std::thread::AccessError;
use thiserror::Error;

use crate::DecimalFloat;

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
    DecimalFloat(DecimalFloat::DecimalFloatErrors),
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
