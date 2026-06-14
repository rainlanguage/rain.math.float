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
    DecimalFloat(Box<DecimalFloat::DecimalFloatErrors>),
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
    ExponentUnderflow,
    FixedDecimalOverflow,
    Log10Negative,
    Log10Zero,
    LossyConversionFromFloat,
    NegativeFixedDecimalConversion,
    WithTargetExponentOverflow,
}

impl DecimalFloatErrorSelector {
    /// A detailed, human-readable description of the underlying Solidity
    /// `DecimalFloat` error that produced this selector.
    pub fn to_readable_msg(&self) -> &'static str {
        match self {
            Self::CoefficientOverflow => {
                "The number's coefficient is too large to fit in a Float (the signed coefficient exceeds the 224-bit range)."
            }
            Self::ExponentOverflow => {
                "The number is too large to represent as a Float (its exponent exceeds the maximum supported magnitude)."
            }
            Self::ExponentUnderflow => {
                "The number is too small to represent as a Float (its exponent is below the minimum supported magnitude, so it cannot be distinguished from zero)."
            }
            Self::FixedDecimalOverflow => {
                "The number is too large to convert to a fixed-decimal value at the requested number of decimals (the scaled value exceeds the unsigned 256-bit range)."
            }
            Self::Log10Negative => {
                "Cannot take the base-10 logarithm of a negative number."
            }
            Self::Log10Zero => "Cannot take the base-10 logarithm of zero.",
            Self::LossyConversionFromFloat => {
                "Converting this Float to the requested type would lose precision, and a lossless conversion was required."
            }
            Self::NegativeFixedDecimalConversion => {
                "Cannot convert a negative number to an unsigned fixed-decimal value."
            }
            Self::WithTargetExponentOverflow => {
                "The number cannot be rescaled to the requested target exponent without overflowing the Float coefficient."
            }
        }
    }
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
            <DecimalFloat::ExponentUnderflow as SolError>::SELECTOR => Ok(Self::ExponentUnderflow),
            <DecimalFloat::FixedDecimalOverflow as SolError>::SELECTOR => {
                Ok(Self::FixedDecimalOverflow)
            }
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

impl FloatError {
    /// A detailed, human-readable description of the error, suitable for
    /// surfacing to end users (e.g. via [WasmEncodedError::readable_msg]).
    pub fn to_readable_msg(&self) -> String {
        match self {
            Self::Evm(e) => {
                format!("An error occurred while executing the Float operation in the EVM: {e}")
            }
            Self::Revert(bytes) => {
                format!("The Float operation reverted with output: {bytes}")
            }
            Self::Halt(reason) => {
                format!("The Float operation halted unexpectedly with reason: {reason:?}")
            }
            Self::UnexpectedSuccess(reason, output) => {
                format!(
                    "The Float operation ended for an unexpected non-return reason: {reason:?}. Output: {output:?}"
                )
            }
            Self::AlloySolTypes(e) => {
                format!("Failed to encode or decode the Float operation's ABI data: {e}")
            }
            Self::DecimalFloat(e) => {
                format!("The Float operation failed with a decimal float error: {e:?}")
            }
            Self::DecimalFloatSelector(selector) => match selector {
                Ok(selector) => selector.to_readable_msg().to_string(),
                Err(unknown) => format!(
                    "The Float operation reverted with an unrecognised error selector: {unknown}"
                ),
            },
            Self::Access(e) => {
                format!("Failed to access the thread-local EVM used to run Float operations: {e}")
            }
            Self::InvalidHex(s) => {
                format!("The provided value is not a valid hex string: {s}")
            }
            Self::AlloyFromHexError(e) => {
                format!("Failed to decode the provided hex string: {e}")
            }
            Self::AlloyParseError(e) => {
                format!("Failed to parse the provided number: {e}")
            }
            Self::AlloyParseSignedError(e) => {
                format!("Failed to parse the provided signed number: {e}")
            }
            Self::JsSysError(s) => {
                format!("A JavaScript error occurred while running the Float operation: {s}")
            }
        }
    }
}

impl From<FloatError> for WasmEncodedError {
    fn from(value: FloatError) -> Self {
        WasmEncodedError {
            msg: value.to_string(),
            readable_msg: value.to_readable_msg(),
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decimal_float_error_selector_readable_msgs() {
        assert_eq!(
            DecimalFloatErrorSelector::CoefficientOverflow.to_readable_msg(),
            "The number's coefficient is too large to fit in a Float (the signed coefficient exceeds the 224-bit range)."
        );
        assert_eq!(
            DecimalFloatErrorSelector::ExponentOverflow.to_readable_msg(),
            "The number is too large to represent as a Float (its exponent exceeds the maximum supported magnitude)."
        );
        assert_eq!(
            DecimalFloatErrorSelector::ExponentUnderflow.to_readable_msg(),
            "The number is too small to represent as a Float (its exponent is below the minimum supported magnitude, so it cannot be distinguished from zero)."
        );
        assert_eq!(
            DecimalFloatErrorSelector::FixedDecimalOverflow.to_readable_msg(),
            "The number is too large to convert to a fixed-decimal value at the requested number of decimals (the scaled value exceeds the unsigned 256-bit range)."
        );
        assert_eq!(
            DecimalFloatErrorSelector::Log10Negative.to_readable_msg(),
            "Cannot take the base-10 logarithm of a negative number."
        );
        assert_eq!(
            DecimalFloatErrorSelector::Log10Zero.to_readable_msg(),
            "Cannot take the base-10 logarithm of zero."
        );
        assert_eq!(
            DecimalFloatErrorSelector::LossyConversionFromFloat.to_readable_msg(),
            "Converting this Float to the requested type would lose precision, and a lossless conversion was required."
        );
        assert_eq!(
            DecimalFloatErrorSelector::NegativeFixedDecimalConversion.to_readable_msg(),
            "Cannot convert a negative number to an unsigned fixed-decimal value."
        );
        assert_eq!(
            DecimalFloatErrorSelector::WithTargetExponentOverflow.to_readable_msg(),
            "The number cannot be rescaled to the requested target exponent without overflowing the Float coefficient."
        );
    }

    #[test]
    fn test_float_error_readable_msg_invalid_hex() {
        let err = FloatError::InvalidHex("zz".to_string());
        assert_eq!(
            err.to_readable_msg(),
            "The provided value is not a valid hex string: zz"
        );
    }

    #[test]
    fn test_float_error_readable_msg_js_sys() {
        let err = FloatError::JsSysError("boom".to_string());
        assert_eq!(
            err.to_readable_msg(),
            "A JavaScript error occurred while running the Float operation: boom"
        );
    }

    #[test]
    fn test_float_error_readable_msg_decimal_float_selector_known() {
        let err = FloatError::DecimalFloatSelector(Ok(DecimalFloatErrorSelector::Log10Zero));
        assert_eq!(
            err.to_readable_msg(),
            "Cannot take the base-10 logarithm of zero."
        );
    }

    #[test]
    fn test_float_error_readable_msg_decimal_float_selector_unknown() {
        let unknown = FixedBytes::<4>::from([0xde, 0xad, 0xbe, 0xef]);
        let err = FloatError::DecimalFloatSelector(Err(unknown));
        assert_eq!(
            err.to_readable_msg(),
            "The Float operation reverted with an unrecognised error selector: 0xdeadbeef"
        );
    }

    #[test]
    fn test_wasm_encoded_error_uses_readable_msg() {
        let err = FloatError::InvalidHex("zz".to_string());
        let short = err.to_string();
        let readable = err.to_readable_msg();
        let encoded: WasmEncodedError = err.into();
        assert_eq!(encoded.msg, short);
        assert_eq!(encoded.readable_msg, readable);
        // The detailed readable message is distinct from the short message.
        assert_ne!(encoded.msg, encoded.readable_msg);
    }
}
