use crate::DecimalFloat;
use alloy::hex::FromHexError;
use alloy::primitives::{Bytes, FixedBytes};
use alloy::sol_types::SolError;
use revm::context::result::{EVMError, HaltReason, Output, SuccessReason};
use std::thread::AccessError;
use thiserror::Error;
use wasm_bindgen_utils::prelude::js_sys::{Error as JsError, RangeError};
use wasm_bindgen_utils::result::WasmEncodedError;

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
    #[error("Invalid hex string: {0}")]
    InvalidHex(String),
    #[error(transparent)]
    AlloyFromHexError(#[from] FromHexError),
    #[error(transparent)]
    AlloyParseError(#[from] alloy::primitives::ruint::ParseError),
    #[error(transparent)]
    AlloyParseSignedError(#[from] alloy::primitives::ParseSignedError),
    #[error("Wasm bindgen js_sys threw error: {0}")]
    JsSysError(String),
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

impl From<FloatError> for WasmEncodedError {
    fn from(value: FloatError) -> Self {
        WasmEncodedError {
            msg: value.to_string(),
            readable_msg: value.to_string(), // todo: add detailed readable msg for errors
        }
    }
}

impl From<JsError> for FloatError {
    fn from(value: JsError) -> Self {
        FloatError::JsSysError(value.to_string().into())
    }
}

impl From<RangeError> for FloatError {
    fn from(value: RangeError) -> Self {
        FloatError::JsSysError(value.to_string().into())
    }
}
