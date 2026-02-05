use alloy::hex::FromHex;
use alloy::primitives::{B256, Bytes};
use alloy::{sol, sol_types::SolCall};
use revm::primitives::{U256, fixed_bytes};
use serde::{Deserialize, Serialize};
use std::ops::{Add, Div, Mul, Neg, Sub};
use wasm_bindgen_utils::prelude::*;

#[cfg(test)]
use alloy::primitives::aliases::I224;

pub mod error;
mod evm;
pub mod js_api;

use error::DecimalFloatErrorSelector;
pub use error::FloatError;
use evm::execute_call;
#[cfg(test)]
use evm::execute_test_call;

sol!(
    #![sol(all_derives)]
    DecimalFloat,
    "../../out/DecimalFloat.sol/DecimalFloat.json"
);

#[cfg(test)]
sol!(
    #![sol(all_derives)]
    TestDecimalFloat,
    "../../out/TestDecimalFloat.sol/TestDecimalFloat.json"
);

#[derive(Debug, Copy, Clone, Default, Serialize, Deserialize, Hash)]
#[wasm_bindgen]
pub struct Float(B256);

impl Float {
    /// Creates a new `Float` from the given 32-byte value `B256`.
    pub const fn from_raw(value: B256) -> Self {
        Float(value)
    }

    /// Getter for inner 32-bytes value of this Float instance as `B256`.
    pub fn get_inner(&self) -> B256 {
        self.0
    }

    /// Sets the inner 32-byte value of this float from the given `B256`.
    pub fn set_inner(&mut self, value: B256) {
        self.0 = value;
    }

    /// Converts a fixed-point decimal value to a `Float` using the specified number of decimals.
    ///
    /// # Arguments
    ///
    /// * `value` - The fixed-point decimal value as a `U256`.
    /// * `decimals` - The number of decimals in the fixed-point representation.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The resulting `Float` value.
    /// * `Err(FloatError)` - If the conversion fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    /// use alloy::primitives::U256;
    ///
    /// // 123.45 with 2 decimals is represented as 12345
    /// let value = U256::from(12345u64);
    /// let decimals = 2u8;
    /// let float = Float::from_fixed_decimal(value, decimals)?;
    /// assert_eq!(float.format()?, "123.45");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn from_fixed_decimal(value: U256, decimals: u8) -> Result<Self, FloatError> {
        let calldata = DecimalFloat::fromFixedDecimalLosslessCall { value, decimals }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded =
                DecimalFloat::fromFixedDecimalLosslessCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Converts a `Float` to a fixed-point decimal value using the specified number of decimals.
    ///
    /// # Arguments
    ///
    /// * `decimals` - The number of decimals in the fixed-point representation.
    ///
    /// # Returns
    ///
    /// * `Ok(U256)` - The resulting fixed-point decimal value.
    /// * `Err(FloatError)` - If the conversion fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    /// use alloy::primitives::U256;
    ///
    /// // 123.45 with 2 decimals becomes 12345
    /// let float = Float::parse("123.45".to_string())?;
    /// let fixed = float.to_fixed_decimal(2)?;
    /// assert_eq!(fixed, U256::from(12345u64));
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn to_fixed_decimal(self, decimals: u8) -> Result<U256, FloatError> {
        let Float(float) = self;
        let calldata = DecimalFloat::toFixedDecimalLosslessCall { float, decimals }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded =
                DecimalFloat::toFixedDecimalLosslessCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    /// Converts a fixed-point decimal value to a `Float` using the specified number of decimals lossy.
    ///
    /// # Arguments
    ///
    /// * `value` - The fixed-point decimal value as a `U256`.
    /// * `decimals` - The number of decimals in the fixed-point representation.
    ///
    /// # Returns
    ///
    /// * `Ok((Float, bool))` - The resulting `Float` value and a boolean indicating if the conversion was lossless.
    /// * `Err(FloatError)` - If the conversion fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    /// use alloy::primitives::U256;
    ///
    /// // 123.45 with 2 decimals is represented as 12345
    /// let value = U256::from(12345u64);
    /// let decimals = 2u8;
    /// let (float, lossless) = Float::from_fixed_decimal_lossy(value, decimals)?;
    /// assert_eq!(float.format()?, "123.45");
    /// assert!(lossless);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn from_fixed_decimal_lossy(value: U256, decimals: u8) -> Result<(Self, bool), FloatError> {
        let calldata = DecimalFloat::fromFixedDecimalLossyCall { value, decimals }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded =
                DecimalFloat::fromFixedDecimalLossyCall::abi_decode_returns(output.as_ref())?;
            Ok((Float(decoded._0), decoded._1))
        })
    }

    /// Converts a `Float` to a fixed-point decimal value using the specified number of decimals lossy.
    ///
    /// # Arguments
    ///
    /// * `decimals` - The number of decimals in the fixed-point representation.
    ///
    /// # Returns
    ///
    /// * `Ok((U256, bool))` - The resulting fixed-point decimal value and a boolean indicating if the conversion was lossless.
    /// * `Err(FloatError)` - If the conversion fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    /// use alloy::primitives::U256;
    ///
    /// // 123.45 with 2 decimals becomes 12345
    /// let float = Float::from_fixed_decimal(U256::from(12345), 3)?;
    /// let (fixed, lossless) = float.to_fixed_decimal_lossy(2)?;
    /// assert_eq!(fixed, U256::from(1234u64));
    /// assert!(!lossless);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn to_fixed_decimal_lossy(self, decimals: u8) -> Result<(U256, bool), FloatError> {
        let Float(float) = self;
        let calldata = DecimalFloat::toFixedDecimalLossyCall { float, decimals }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded =
                DecimalFloat::toFixedDecimalLossyCall::abi_decode_returns(output.as_ref())?;
            Ok((decoded._0, decoded._1))
        })
    }

    /// Packs a coefficient and exponent into a `Float` in a lossless manner.
    ///
    /// # Arguments
    ///
    /// * `coefficient` - The coefficient as an `I224`.
    /// * `exponent` - The exponent as an `i32`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The packed float.
    /// * `Err(FloatError)` - If the packing fails (e.g., overflow).
    ///
    /// # Example
    ///
    /// ```
    /// use std::str::FromStr;
    /// use alloy::primitives::aliases::I224;
    /// use rain_math_float::{Float, FloatError};
    ///
    /// let coefficient = I224::from_str("314")?;
    /// let exponent = -2;
    /// let float = Float::pack_lossless(coefficient, exponent)?;
    /// assert_eq!(float.format()?, "3.14");
    ///
    /// anyhow::Ok(())
    /// ```
    #[cfg(test)]
    pub fn pack_lossless(coefficient: I224, exponent: i32) -> Result<Self, FloatError> {
        let calldata = TestDecimalFloat::packLosslessCall {
            coefficient,
            exponent,
        }
        .abi_encode();

        execute_test_call(Bytes::from(calldata), |output| {
            let decoded = TestDecimalFloat::packLosslessCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    #[cfg(test)]
    fn unpack(self) -> Result<(alloy::primitives::I256, alloy::primitives::I256), FloatError> {
        let Float(float) = self;
        let calldata = TestDecimalFloat::unpackCall { float }.abi_encode();

        execute_test_call(Bytes::from(calldata), |output| {
            let TestDecimalFloat::unpackReturn {
                _0: coefficient,
                _1: exponent,
            } = TestDecimalFloat::unpackCall::abi_decode_returns(output.as_ref())?;

            Ok((coefficient, exponent))
        })
    }

    #[cfg(test)]
    fn show_unpacked(self) -> Result<String, FloatError> {
        let (coefficient, exponent) = self.unpack()?;
        Ok(format!("{coefficient}e{exponent}"))
    }

    /// Parses a decimal string into a `Float`.
    ///
    /// # Arguments
    ///
    /// * `str` - The string to parse.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The parsed float.
    /// * `Err(FloatError)` - If parsing fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let float = Float::parse("3.1415".to_string())?;
    /// assert_eq!(float.format()?, "3.1415");
    ///
    /// anyhow::Ok(())
    /// ```
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

    /// Returns the 32-byte hexadecimal string representation of the float.
    ///
    /// # Returns
    ///
    /// * `String` - The 32-byte hex string.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    /// let float = Float::from_hex("0x0000000000000000000000000000000000000000000000000000000000000005").unwrap();
    /// assert_eq!(float.as_hex(), "0x0000000000000000000000000000000000000000000000000000000000000005");
    /// ```
    pub fn as_hex(self) -> String {
        alloy::hex::encode_prefixed(self.0)
    }

    /// Constructs a `Float` from a 32-byte hexadecimal string.
    ///
    /// # Arguments
    ///
    /// * `hex` - The 32-byte hex string to parse.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The float parsed from the hex string.
    /// * `Err(FloatError)` - If the hex string is not valid or not 32 bytes.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    /// let float = Float::from_hex("0x0000000000000000000000000000000000000000000000000000000000000005")?;
    /// assert_eq!(float.as_hex(), "0x0000000000000000000000000000000000000000000000000000000000000005");
    /// anyhow::Ok(())
    /// ```
    pub fn from_hex(hex: &str) -> Result<Self, FloatError> {
        let bytes = B256::from_hex(hex).map_err(|_| FloatError::InvalidHex(hex.to_string()))?;
        Ok(Float(bytes))
    }

    /// Returns the maximum positive value that can be represented as a `Float`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The maximum positive value.
    /// * `Err(FloatError)` - If the EVM call fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let max_pos = Float::max_positive_value()?;
    /// let zero = Float::parse("0".to_string())?;
    ///
    /// // Max positive is greater than zero
    /// assert!(max_pos.gt(zero)?);
    ///
    /// // Max positive is greater than any normal large number
    /// let big_number = Float::parse("999999999999999999999".to_string())?;
    /// assert!(max_pos.gt(big_number)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn max_positive_value() -> Result<Self, FloatError> {
        let calldata = DecimalFloat::maxPositiveValueCall {}.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::maxPositiveValueCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the minimum positive value that can be represented as a `Float`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The minimum positive value.
    /// * `Err(FloatError)` - If the EVM call fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let min_pos = Float::min_positive_value()?;
    /// let zero = Float::parse("0".to_string())?;
    ///
    /// // Min positive is greater than zero but smaller than any other positive number
    /// assert!(min_pos.gt(zero)?);
    ///
    /// let small_number = Float::parse("0.000000000000000001".to_string())?;
    /// assert!(min_pos.lt(small_number)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn min_positive_value() -> Result<Self, FloatError> {
        let calldata = DecimalFloat::minPositiveValueCall {}.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::minPositiveValueCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the maximum negative value that can be represented as a `Float`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The maximum negative value (closest to zero).
    /// * `Err(FloatError)` - If the EVM call fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let max_neg = Float::max_negative_value()?;
    /// let zero = Float::parse("0".to_string())?;
    ///
    /// // Max negative is less than zero but greater than any other negative number
    /// assert!(max_neg.lt(zero)?);
    ///
    /// let small_negative = Float::parse("-0.000000000000000001".to_string())?;
    /// assert!(max_neg.gt(small_negative)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn max_negative_value() -> Result<Self, FloatError> {
        let calldata = DecimalFloat::maxNegativeValueCall {}.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::maxNegativeValueCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the minimum negative value that can be represented as a `Float`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The minimum negative value (furthest from zero).
    /// * `Err(FloatError)` - If the EVM call fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let min_neg = Float::min_negative_value()?;
    /// let zero = Float::parse("0".to_string())?;
    ///
    /// // Min negative is less than zero
    /// assert!(min_neg.lt(zero)?);
    ///
    /// // Min negative is less than any normal negative number
    /// let big_negative = Float::parse("-999999999999999999999".to_string())?;
    /// assert!(min_neg.lt(big_negative)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn min_negative_value() -> Result<Self, FloatError> {
        let calldata = DecimalFloat::minNegativeValueCall {}.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::minNegativeValueCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the zero value of a `Float` in its maximized representation.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The zero value.
    /// * `Err(FloatError)` - If the EVM call fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let zero = Float::zero()?;
    /// assert!(zero.is_zero()?);
    /// assert_eq!(zero.format()?, "0");
    ///
    /// // Should be equal to parsed zero
    /// let parsed_zero = Float::parse("0".to_string())?;
    /// assert!(zero.eq(parsed_zero)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn zero() -> Result<Self, FloatError> {
        let calldata = DecimalFloat::zeroCall {}.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::zeroCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the default minimum value for scientific notation formatting (1e-4).
    ///
    /// Values smaller than this (in absolute value) will be formatted in scientific notation.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The default minimum (1e-4).
    /// * `Err(FloatError)` - If the EVM call fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let min = Float::format_default_scientific_min()?;
    /// assert_eq!(min.format()?, "0.0001");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn format_default_scientific_min() -> Result<Self, FloatError> {
        let calldata = DecimalFloat::FORMAT_DEFAULT_SCIENTIFIC_MINCall {}.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::FORMAT_DEFAULT_SCIENTIFIC_MINCall::abi_decode_returns(
                output.as_ref(),
            )?;
            Ok(Float(decoded))
        })
    }

    /// Returns the default maximum value for scientific notation formatting (1e9).
    ///
    /// Values larger than this (in absolute value) will be formatted in scientific notation.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The default maximum (1e9).
    /// * `Err(FloatError)` - If the EVM call fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let max = Float::format_default_scientific_max()?;
    /// assert_eq!(max.format()?, "1000000000");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn format_default_scientific_max() -> Result<Self, FloatError> {
        let calldata = DecimalFloat::FORMAT_DEFAULT_SCIENTIFIC_MAXCall {}.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::FORMAT_DEFAULT_SCIENTIFIC_MAXCall::abi_decode_returns(
                output.as_ref(),
            )?;
            Ok(Float(decoded))
        })
    }

    /// Formats the float as a decimal string using default scientific notation range (1e-4 to 1e9).
    ///
    /// Values within the range [1e-4, 1e9] will use decimal notation.
    /// Values outside this range will use scientific notation.
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - The formatted string.
    /// * `Err(FloatError)` - If formatting fails.
    ///
    /// # Examples
    ///
    /// Values within the default range use decimal notation:
    /// ```
    /// use rain_math_float::Float;
    ///
    /// // At the boundaries (inclusive)
    /// assert_eq!(Float::parse("0.0001".to_string())?.format()?, "0.0001");  // 1e-4
    /// assert_eq!(Float::parse("1000000000".to_string())?.format()?, "1000000000");  // 1e9
    ///
    /// // Within range
    /// assert_eq!(Float::parse("2.5".to_string())?.format()?, "2.5");
    /// assert_eq!(Float::parse("123.456".to_string())?.format()?, "123.456");
    /// assert_eq!(Float::parse("0.001".to_string())?.format()?, "0.001");
    /// assert_eq!(Float::parse("1000000".to_string())?.format()?, "1000000");
    ///
    /// anyhow::Ok(())
    /// ```
    ///
    /// Values outside the default range use scientific notation:
    /// ```
    /// use rain_math_float::Float;
    ///
    /// // Smaller than 1e-4
    /// assert_eq!(Float::parse("0.00001".to_string())?.format()?, "1e-5");
    /// assert_eq!(Float::parse("0.000001".to_string())?.format()?, "1e-6");
    ///
    /// // Larger than 1e9
    /// assert_eq!(Float::parse("10000000000".to_string())?.format()?, "1e10");
    /// assert_eq!(Float::parse("123000000000".to_string())?.format()?, "1.23e11");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn format(self) -> Result<String, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::format_1Call { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::format_1Call::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    /// Formats the float as a decimal string with explicit scientific notation control.
    ///
    /// # Arguments
    ///
    /// * `scientific` - If true, always use scientific notation. If false, use decimal notation.
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - The formatted string.
    /// * `Err(FloatError)` - If formatting fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let float = Float::parse("3.14".to_string())?;
    /// assert_eq!(float.format_with_scientific(false)?, "3.14");
    /// assert_eq!(float.format_with_scientific(true)?, "3.14");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn format_with_scientific(self, scientific: bool) -> Result<String, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::format_0Call { a, scientific }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::format_0Call::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    /// Formats the float as a decimal string with a custom scientific notation range.
    ///
    /// # Arguments
    ///
    /// * `scientific_min` - Values smaller than this (in absolute value) use scientific notation.
    /// * `scientific_max` - Values larger than this (in absolute value) use scientific notation.
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - The formatted string.
    /// * `Err(FloatError)` - If formatting fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let float = Float::parse("0.001".to_string())?;
    /// let min = Float::parse("0.01".to_string())?;
    /// let max = Float::parse("100".to_string())?;
    /// assert_eq!(float.format_with_range(min, max)?, "1e-3");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn format_with_range(
        self,
        scientific_min: Self,
        scientific_max: Self,
    ) -> Result<String, FloatError> {
        let Float(a) = self;
        let Float(scientific_min_inner) = scientific_min;
        let Float(scientific_max_inner) = scientific_max;
        let calldata = DecimalFloat::format_2Call {
            a,
            scientificMin: scientific_min_inner,
            scientificMax: scientific_max_inner,
        }
        .abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::format_2Call::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    /// Returns `true` if `self` is less than `b`.
    ///
    /// # Arguments
    ///
    /// * `b` - The `Float` value to compare with `self`.
    ///
    /// # Returns
    ///
    /// * `Ok(true)` if `self` is less than `b`.
    /// * `Ok(false)` if `self` is not less than `b`.
    /// * `Err(FloatError)` if the comparison fails due to an error in the underlying EVM call or decoding.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("1.0".to_string())?;
    /// let b = Float::parse("2.0".to_string())?;
    /// assert!(a.lt(b)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn lt(self, b: Self) -> Result<bool, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::ltCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::ltCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    /// Returns `true` if `self` is equal to `b`.
    ///
    /// # Arguments
    ///
    /// * `b` - The `Float` value to compare with `self`.
    ///
    /// # Returns
    ///
    /// * `Ok(true)` if `self` is equal to `b`.
    /// * `Ok(false)` if `self` is not equal to `b`.
    /// * `Err(FloatError)` if the comparison fails due to an error in the underlying EVM call or decoding.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("3.14".to_string())?;
    /// let b = Float::parse("3.14".to_string())?;
    /// assert!(a.eq(b)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn eq(self, b: Self) -> Result<bool, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::eqCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::eqCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    /// Returns `true` if `self` is greater than `b`.
    ///
    /// # Arguments
    ///
    /// * `b` - The `Float` value to compare with `self`.
    ///
    /// # Returns
    ///
    /// * `Ok(true)` if `self` is greater than `b`.
    /// * `Ok(false)` if `self` is not greater than `b`.
    /// * `Err(FloatError)` if the comparison fails due to an error in the underlying EVM call or decoding.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("5.0".to_string())?;
    /// let b = Float::parse("2.0".to_string())?;
    /// assert!(a.gt(b)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn gt(self, b: Self) -> Result<bool, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::gtCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::gtCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    /// Returns the multiplicative inverse of the float.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The inverse.
    /// * `Err(FloatError)` - If inversion fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let x = Float::parse("2.0".to_string())?;
    /// let inv = x.inv()?;
    /// assert!(inv.format()?.starts_with("0.5"));
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn inv(self) -> Result<Self, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::invCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::invCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the absolute value of the float.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The absolute value.
    /// * `Err(FloatError)` - If the operation fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let x = Float::parse("-3.14".to_string())?;
    /// let abs = x.abs()?;
    /// assert_eq!(abs.format()?, "3.14");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn abs(self) -> Result<Float, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::absCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::absCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns `true` if `self` is less than or equal to `b`.
    ///
    /// # Arguments
    ///
    /// * `b` - The `Float` value to compare with `self`.
    ///
    /// # Returns
    ///
    /// * `Ok(true)` if `self` is less than or equal to `b`.
    /// * `Ok(false)` if `self` is not less than or equal to `b`.
    /// * `Err(FloatError)` if the comparison fails due to an error in the underlying EVM call or decoding.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("1.0".to_string())?;
    /// let b = Float::parse("2.0".to_string())?;
    /// assert!(a.lte(b)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn lte(self, b: Self) -> Result<bool, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::lteCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::lteCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }

    /// Returns `true` if `self` is greater than or equal to `b`.
    ///
    /// # Arguments
    ///
    /// * `b` - The `Float` value to compare with `self`.
    ///
    /// # Returns
    ///
    /// * `Ok(true)` if `self` is greater than or equal to `b`.
    /// * `Ok(false)` if `self` is not greater than or equal to `b`.
    /// * `Err(FloatError)` if the comparison fails due to an error in the underlying EVM call or decoding.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("2.0".to_string())?;
    /// let b = Float::parse("1.0".to_string())?;
    /// assert!(a.gte(b)?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn gte(self, b: Self) -> Result<bool, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::gteCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::gteCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }
}

impl Add for Float {
    type Output = Result<Self, FloatError>;

    /// Adds two floats.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The sum.
    /// * `Err(FloatError)` - If addition fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("1.5".to_string())?;
    /// let b = Float::parse("2.5".to_string())?;
    /// let sum = (a + b)?;
    /// assert_eq!(sum.format()?, "4");
    ///
    /// anyhow::Ok(())
    /// ```
    fn add(self, b: Self) -> Self::Output {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::addCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::addCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

impl Sub for Float {
    type Output = Result<Self, FloatError>;

    /// Subtracts `b` from `self`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The difference.
    /// * `Err(FloatError)` - If subtraction fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("5.0".to_string())?;
    /// let b = Float::parse("2.0".to_string())?;
    /// let diff = (a - b)?;
    /// assert_eq!(diff.format()?, "3");
    ///
    /// anyhow::Ok(())
    /// ```
    fn sub(self, b: Self) -> Self::Output {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::subCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::subCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

impl Mul for Float {
    type Output = Result<Self, FloatError>;

    /// Multiplies two floats.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The product.
    /// * `Err(FloatError)` - If multiplication fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("2.0".to_string())?;
    /// let b = Float::parse("3.0".to_string())?;
    /// let product = (a * b)?;
    /// assert_eq!(product.format()?, "6");
    ///
    /// anyhow::Ok(())
    /// ```
    fn mul(self, b: Self) -> Self::Output {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::mulCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::mulCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

impl Div for Float {
    type Output = Result<Self, FloatError>;

    /// Divides `self` by `b`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The quotient.
    /// * `Err(FloatError)` - If division fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("6.0".to_string())?;
    /// let b = Float::parse("2.0".to_string())?;
    /// let quotient = (a / b)?;
    /// assert_eq!(quotient.format()?, "3");
    ///
    /// anyhow::Ok(())
    /// ```
    fn div(self, b: Self) -> Self::Output {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::divCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::divCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

impl Float {
    /// Returns the integer part of the float (truncation toward zero).
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The integer part.
    /// * `Err(FloatError)` - If the operation fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let x = Float::parse("3.75".to_string())?;
    /// let int = x.integer()?;
    /// assert_eq!(int.format()?, "3");
    ///
    /// let y = Float::parse("-3.75".to_string())?;
    /// let int_y = y.integer()?;
    /// assert_eq!(int_y.format()?, "-3");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn integer(self) -> Result<Float, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::integerCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::integerCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the fractional part of the float.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The fractional part.
    /// * `Err(FloatError)` - If the operation fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let x = Float::parse("3.75".to_string())?;
    /// let frac = x.frac()?;
    /// assert_eq!(frac.format()?, "0.75");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn frac(self) -> Result<Float, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::fracCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::fracCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the floor of the float.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The floored value.
    /// * `Err(FloatError)` - If the operation fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let x = Float::parse("3.75".to_string())?;
    /// let floor = x.floor()?;
    /// assert_eq!(floor.format()?, "3");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn floor(self) -> Result<Float, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::floorCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::floorCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the minimum of `self` and `b`.
    ///
    /// # Arguments
    ///
    /// * `b` - The other `Float` to compare with.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The minimum value.
    /// * `Err(FloatError)` - If the operation fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("1.0".to_string())?;
    /// let b = Float::parse("2.0".to_string())?;
    /// let min = a.min(b)?;
    /// assert_eq!(min.format()?, "1");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn min(self, b: Self) -> Result<Self, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::minCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::minCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Returns the maximum of `self` and `b`.
    ///
    /// # Arguments
    ///
    /// * `b` - The other `Float` to compare with.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The maximum value.
    /// * `Err(FloatError)` - If the operation fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let a = Float::parse("1.0".to_string())?;
    /// let b = Float::parse("2.0".to_string())?;
    /// let max = a.max(b)?;
    /// assert_eq!(max.format()?, "2");
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn max(self, b: Self) -> Result<Self, FloatError> {
        let Float(a) = self;
        let Float(b) = b;
        let calldata = DecimalFloat::maxCall { a, b }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::maxCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }

    /// Checks if the float is zero.
    ///
    /// # Returns
    ///
    /// * `Ok(true)` if the float is zero.
    /// * `Ok(false)` if the float is not zero.
    /// * `Err(FloatError)` if the operation fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let zero = Float::parse("0".to_string())?;
    /// assert!(zero.is_zero()?);
    /// let nonzero = Float::parse("1.23".to_string())?;
    /// assert!(!nonzero.is_zero()?);
    ///
    /// anyhow::Ok(())
    /// ```
    pub fn is_zero(self) -> Result<bool, FloatError> {
        let Float(a) = self;
        let calldata = DecimalFloat::isZeroCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::isZeroCall::abi_decode_returns(output.as_ref())?;
            Ok(decoded)
        })
    }
}

impl Neg for Float {
    type Output = Result<Self, FloatError>;

    /// Returns the negation of the float.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The negated value.
    /// * `Err(FloatError)` - If the operation fails.
    ///
    /// # Example
    ///
    /// ```
    /// use rain_math_float::Float;
    ///
    /// let x = Float::parse("3.14".to_string())?;
    /// let neg = (-x)?;
    /// assert_eq!(neg.format()?, "-3.14");
    ///
    /// anyhow::Ok(())
    /// ```
    fn neg(self) -> Self::Output {
        let Float(a) = self;
        let calldata = DecimalFloat::minusCall { a }.abi_encode();

        execute_call(Bytes::from(calldata), |output| {
            let decoded = DecimalFloat::minusCall::abi_decode_returns(output.as_ref())?;
            Ok(Float(decoded))
        })
    }
}

impl From<B256> for Float {
    fn from(value: B256) -> Self {
        Float(value)
    }
}

impl From<Float> for B256 {
    fn from(value: Float) -> Self {
        value.0
    }
}

#[cfg(test)]
mod tests {
    use crate::DecimalFloat::DecimalFloatErrors;

    use super::*;
    use core::str::FromStr;
    use proptest::prelude::*;
    use serde_json::json;

    #[test]
    fn test_default() {
        let zero = Float::parse("0".to_string()).unwrap();
        assert!(zero.eq(Float::default()).unwrap());
    }

    #[test]
    fn test_zero() {
        let zero = Float::zero().unwrap();
        assert!(zero.is_zero().unwrap());
        assert_eq!(zero.format().unwrap(), "0");

        // Test that zero equals parsed zero
        let parsed_zero = Float::parse("0".to_string()).unwrap();
        assert!(zero.eq(parsed_zero).unwrap());

        // Test that zero equals default
        assert!(zero.eq(Float::default()).unwrap());
    }

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
    fn test_serde() {
        let float = Float::parse("1.1341234234625468391".to_string()).unwrap();
        let serialized = serde_json::to_string(&float).unwrap();
        assert_eq!(
            serialized,
            json!("0xffffffed00000000000000000000000000000000000000009d642872ad59a7e7").to_string()
        );
        let deserialized: Float = serde_json::from_str(&serialized).unwrap();
        assert!(float.eq(deserialized).unwrap());
    }

    proptest! {
        #[test]
        fn proptest_serde(float in arb_float()) {
            let serialized = serde_json::to_string(&float).unwrap();
            let deserialized: Float = serde_json::from_str(&serialized).unwrap();
            prop_assert!(float.eq(deserialized).unwrap());
            let re_serialized = serde_json::to_string(&deserialized).unwrap();
            prop_assert_eq!(serialized, re_serialized);
        }
    }

    #[test]
    fn test_parse_empty_string_error() {
        let err = Float::parse("".to_string()).unwrap_err();
        // We don't know the exact selector here, just ensure the error path is hit.
        assert!(matches!(err, FloatError::DecimalFloatSelector(_)));
    }

    #[test]
    fn test_parse_exponent_overflow_error() {
        // Extremely large exponent expected to overflow (exponent >> i32::MAX).
        let err = Float::parse("1e3000000000".to_string()).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    #[test]
    fn test_parse_edge_cases() {
        let err = Float::parse("1.2.3".to_string()).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloatSelector(Err(selector))
            if selector == fixed_bytes!("ad384e87")
        ));

        let err = Float::parse("abc".to_string()).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloatSelector(Err(selector))
            if selector == fixed_bytes!("34bd2069")
        ));
    }

    #[test]
    fn test_float_constants() {
        // Test that all constant methods return valid floats
        let max_pos = Float::max_positive_value().unwrap();
        let min_pos = Float::min_positive_value().unwrap();
        let max_neg = Float::max_negative_value().unwrap();
        let min_neg = Float::min_negative_value().unwrap();

        let zero = Float::parse("0".to_string()).unwrap();

        // Test mathematical properties without exposing binary representation

        // All constants should be distinct
        assert!(!max_pos.eq(min_pos).unwrap());
        assert!(!max_neg.eq(min_neg).unwrap());
        assert!(!max_pos.eq(max_neg).unwrap());
        assert!(!min_pos.eq(min_neg).unwrap());

        // Test sign properties
        assert!(min_pos.gt(zero).unwrap()); // min positive should be > 0
        assert!(max_pos.gt(zero).unwrap()); // max positive should be > 0
        assert!(max_neg.lt(zero).unwrap()); // max negative should be < 0
        assert!(min_neg.lt(zero).unwrap()); // min negative should be < 0

        // Test ordering relationships
        assert!(min_pos.lt(max_pos).unwrap()); // min positive < max positive
        assert!(min_neg.lt(max_neg).unwrap()); // min negative < max negative

        // Test boundary properties
        let one = Float::parse("1".to_string()).unwrap();
        let neg_one = Float::parse("-1".to_string()).unwrap();

        // Positive constants should be greater than normal values
        assert!(max_pos.gt(one).unwrap());
        assert!(min_pos.lt(one).unwrap());

        // Negative constants should be more extreme than normal negative values
        assert!(max_neg.gt(neg_one).unwrap());
        assert!(min_neg.lt(neg_one).unwrap());
    }

    proptest! {
        #[test]
        fn test_format_parse(float in reasonable_float()) {
            let formatted = float.format().unwrap();
            let parsed = Float::parse(formatted.clone()).unwrap();
            prop_assert!(float.eq(parsed).unwrap());
        }
    }

    proptest! {
        #[test]
        fn test_as_from_hex(float in arb_float()) {
            let hex = float.as_hex();
            let parsed = Float::from_hex(&hex).unwrap();
            prop_assert_eq!(parsed.as_hex(), hex);
        }
    }

    #[test]
    fn test_add_exponent_overflow_error() {
        let max_coeff_str = "13479973333575319897333507543509815336818572211270286240551805124607";
        let large_coeff_i224 = I224::from_str(max_coeff_str).unwrap();
        let exponent_max = i32::MAX;

        let a = Float::pack_lossless(large_coeff_i224, exponent_max).unwrap();

        let err = (a + a).unwrap_err();

        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    #[test]
    fn test_sub_exponent_overflow_error() {
        let max_coeff_str = "13479973333575319897333507543509815336818572211270286240551805124607";
        let large_coeff_i224 = I224::from_str(max_coeff_str).unwrap();
        let exponent_max = i32::MAX;

        let a = Float::pack_lossless(large_coeff_i224, exponent_max).unwrap();
        let b = Float::pack_lossless(-large_coeff_i224, exponent_max).unwrap();

        let err = (b - a).unwrap_err();

        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    proptest! {
        #[test]
        fn test_add(a in reasonable_float(), b in reasonable_float()) {
            (a + b).unwrap();
        }
    }

    proptest! {
        #[test]
        fn test_sub(a in reasonable_float(), b in reasonable_float()) {
            (a - b).unwrap();
        }
    }

    proptest! {
        #[test]
        fn test_add_sub(a in reasonable_float(), b in reasonable_float()) {
            let sum = (a + b).unwrap();
            let diff = (sum - b).unwrap();
            prop_assert_eq!(
                a.format().unwrap(),
                diff.format().unwrap(),
                "a: {}, b: {}",
                a.format().unwrap(),
                b.format().unwrap(),
            );
        }
    }

    #[test]
    fn test_lt_eq_gt() {
        let negone = Float::parse("-1".to_string()).unwrap();
        let zero = Float::parse("0".to_string()).unwrap();
        let three = Float::parse("3".to_string()).unwrap();

        assert!(negone.lt(zero).unwrap());
        assert!(!negone.eq(zero).unwrap());
        assert!(!negone.gt(zero).unwrap());

        assert!(!three.lt(zero).unwrap());
        assert!(!three.eq(zero).unwrap());
        assert!(three.gt(zero).unwrap());

        assert!(zero.lt(three).unwrap());
        assert!(!zero.eq(three).unwrap());
        assert!(!zero.gt(three).unwrap());
    }

    proptest! {
        #[test]
        fn test_lt_eq_gt_with_add(a in reasonable_float()) {
            let b = a;
            let eq = a.eq(b).unwrap();
            prop_assert!(eq);

            let one = Float::parse("1".to_string()).unwrap();

            let a = (a - one).unwrap();
            let lt = a.lt(b).unwrap();
            prop_assert!(lt);

            let a = (a + one).unwrap();
            let eq = a.eq(b).unwrap();
            prop_assert!(eq);

            let a = (a + one).unwrap();
            let gt = a.gt(b).unwrap();
            prop_assert!(gt);
        }

        #[test]
        fn test_exactly_one_lt_eq_gt(a in arb_float(), b in arb_float()) {
            let eq = a.eq(b).unwrap();
            let lt = a.lt(b).unwrap();
            let gt = a.gt(b).unwrap();

            let a_str = a.show_unpacked().unwrap();
            let b_str = b.show_unpacked().unwrap();

            prop_assert!(lt || eq || gt, "a: {a_str}, b: {b_str}");
            prop_assert!(!(lt && eq), "both less than and equal: a: {a_str}, b: {b_str}");
            prop_assert!(!(eq && gt), "both equal and greater than: a: {a_str}, b: {b_str}");
            prop_assert!(!(lt && gt), "both less than and greater than: a: {a_str}, b: {b_str}");
        }
    }

    #[test]
    fn test_abs() {
        let float = Float::parse("-3613.1324123".to_string()).unwrap();
        let abs = float.abs().unwrap();
        let formatted = abs.format().unwrap();
        assert_eq!(formatted, "3613.1324123");

        let float = Float::parse("3613.1324123".to_string()).unwrap();
        let abs = float.abs().unwrap();
        let formatted = abs.format().unwrap();
        assert_eq!(formatted, "3613.1324123");

        let float = Float::parse("0".to_string()).unwrap();
        let abs = float.abs().unwrap();
        let formatted = abs.format().unwrap();
        assert_eq!(formatted, "0");
    }

    proptest! {
        #[test]
        fn test_mul(a in reasonable_float(), b in reasonable_float()) {
            (a * b).unwrap();
        }
    }

    #[test]
    fn test_minus_format() {
        let float = Float::parse("-123.1234234625468391".to_string()).unwrap();
        let negated = float.neg().unwrap();

        let formatted_decimal = negated.format_with_scientific(false).unwrap();
        assert_eq!(formatted_decimal, "123.1234234625468391");

        let float = Float::parse("0".to_string()).unwrap();
        let negated = float.neg().unwrap();
        let formatted = negated.format().unwrap();
        assert_eq!(formatted, "0");
    }

    proptest! {
        #[test]
        fn test_minus_minus(float in arb_float()) {
            let negated = float.neg().unwrap();
            let renegated = negated.neg().unwrap();
            prop_assert!(float.eq(renegated).unwrap());
        }
    }

    proptest! {
        #[test]
        fn test_inv_prod(float in reasonable_float()) {
            let zero = Float::parse("0".to_string()).unwrap();
            prop_assume!(!float.eq(zero).unwrap());

            let inv = float.inv().unwrap();
            let product = (float * inv).unwrap();
            let one = Float::parse("1".to_string()).unwrap();

            // Allow for minor rounding errors introduced by the lossy
            // `inv` implementation. We consider the property to
            // hold if the product is within `±1e-37` of 1.

            let eps = Float::parse("1e-37".to_string()).unwrap();
            let one_plus_eps = (one + eps).unwrap();
            let one_minus_eps = (one - eps).unwrap();

            let within_upper = !product.gt(one_plus_eps).unwrap();
            let within_lower = !product.lt(one_minus_eps).unwrap();

            prop_assert!(
                within_upper && within_lower,
                "float: {}, inv: {}, product: {} (not within ±ε)",
                float.show_unpacked().unwrap(),
                inv.show_unpacked().unwrap(),
                product.show_unpacked().unwrap(),
            );
        }
    }

    proptest! {
        #[test]
        fn test_abs_no_minus_sign(float in reasonable_float()) {
            let abs = float.abs().unwrap();
            let formatted = abs.format().unwrap();
            prop_assert!(!formatted.starts_with("-"));
        }

        #[test]
        fn test_abs_abs(float in arb_float()) {
            let abs = float.abs().unwrap();
            let abs_abs = abs.abs().unwrap();
            prop_assert!(abs.eq(abs_abs).unwrap());
        }
    }

    proptest! {
        #[test]
        fn test_div(a in reasonable_float(), b in reasonable_float()) {
            let zero = Float::parse("0".to_string()).unwrap();
            prop_assume!(!b.eq(zero).unwrap());

            (a / b).unwrap();
        }
    }

    prop_compose! {
        fn small_int_float()(int_part in -1_000_000_000_000i128..1_000_000_000_000i128) -> Float {
            Float::parse(int_part.to_string()).unwrap()
        }
    }

    proptest! {
        #[test]
        fn test_mul_div_int(a in small_int_float(), b in small_int_float()) {
            let zero = Float::parse("0".to_string()).unwrap();
            prop_assume!(!b.eq(zero).unwrap());

            let product = (a * b).unwrap();
            let quotient = (product / b).unwrap();

            prop_assert!(
                a.eq(quotient).unwrap(),
                "a: {}, quotient: {}, b: {}",
                a.show_unpacked().unwrap(),
                quotient.show_unpacked().unwrap(),
                b.show_unpacked().unwrap()
            );
        }
    }

    #[test]
    fn test_mul_div_manual() {
        let two = Float::parse("2".to_string()).unwrap();
        let three = Float::parse("3".to_string()).unwrap();
        let six = Float::parse("6".to_string()).unwrap();

        assert!(two.eq((six / three).unwrap()).unwrap());
        assert!(six.eq((two * three).unwrap()).unwrap());
    }

    #[test]
    fn test_divide_by_zero_error() {
        let one = Float::parse("1".to_string()).unwrap();
        let zero = Float::parse("0".to_string()).unwrap();
        let err = (one / zero).unwrap_err();

        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::DivisionByZero(_))
        ));
    }

    #[test]
    fn test_mul_exponent_overflow_error() {
        let near_max_exp = Float::parse("1e2147483646".to_string()).unwrap();
        let one_e_two = Float::parse("1e2".to_string()).unwrap();

        let err = (near_max_exp * one_e_two).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    #[test]
    fn test_div_exponent_overflow_error() {
        let near_max_exp = Float::parse("1e2147483646".to_string()).unwrap();
        let one_e_neg_hundred = Float::parse("1e-100".to_string()).unwrap();

        let err = (near_max_exp / one_e_neg_hundred).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::ExponentOverflow(_))
        ));
    }

    #[test]
    fn test_mul_exponent_underflow_error() {
        let near_min_exp = Float::parse("1e-2147483646".to_string()).unwrap();
        let one_e_neg_three = Float::parse("1e-3".to_string()).unwrap();

        let float = (near_min_exp * one_e_neg_three).unwrap();
        assert!(float.is_zero().unwrap());
    }

    #[test]
    fn test_from_fixed_decimal() {
        let cases = vec![
            (U256::from(0u128), 0u8, "0"),
            (U256::from(0u128), 18u8, "0"),
            (U256::from(1u128), 18u8, "1e-18"),
            (U256::from(123456789u128), 0u8, "123456789"),
            (U256::from(123456789u128), 2u8, "123456789e-2"),
            (U256::from(1000000000000000000u128), 18u8, "1"),
        ];

        for (amount, decimals, expected) in cases {
            let float = Float::from_fixed_decimal(amount, decimals).expect("should convert");
            let expected = Float::parse(expected.to_string()).unwrap();
            assert!(float.eq(expected).unwrap());
        }
    }

    #[test]
    fn test_from_fixed_decimal_err() {
        let err = Float::from_fixed_decimal(U256::MAX, 1).unwrap_err();
        assert!(matches!(
            err,
            FloatError::DecimalFloat(DecimalFloatErrors::LossyConversionToFloat(_))
        ));
    }

    #[test]
    fn test_to_fixed_decimal() {
        let cases = vec![
            ("0", 0u8, 0u128),
            ("0", 18u8, 0u128),
            ("1e-18", 18u8, 1u128),
            ("123456789", 0u8, 123456789u128),
            ("123456789e-2", 2u8, 123456789u128),
            ("1", 18u8, 1000000000000000000u128),
        ];

        for (input, decimals, expected) in cases {
            let float = Float::parse(input.to_string()).unwrap();
            let fixed = float.to_fixed_decimal(decimals).unwrap();
            assert_eq!(fixed, U256::from(expected));
        }
    }

    #[test]
    fn test_frac_and_floor_integers() {
        let int_float = Float::parse("12345".to_string()).unwrap();
        let floor = int_float.floor().unwrap();
        let frac = int_float.frac().unwrap();
        let zero = Float::parse("0".to_string()).unwrap();

        assert!(int_float.eq(floor).unwrap());
        assert!(frac.eq(zero).unwrap());

        let int_float = Float::parse("-98765".to_string()).unwrap();
        let floor = int_float.floor().unwrap();
        let frac = int_float.frac().unwrap();
        let zero = Float::parse("0".to_string()).unwrap();

        assert!(int_float.eq(floor).unwrap());
        assert!(frac.eq(zero).unwrap());

        let recombined = (floor + frac).unwrap();
        assert!(int_float.eq(recombined).unwrap());
    }

    #[test]
    fn test_frac_and_floor_floats() {
        let float = Float::parse("12345.6789".to_string()).unwrap();
        let floor = float.floor().unwrap();
        let frac = float.frac().unwrap();

        let expected_floor = Float::parse("12345".to_string()).unwrap();
        let expected_frac = Float::parse("0.6789".to_string()).unwrap();

        assert!(floor.eq(expected_floor).unwrap());
        assert!(frac.eq(expected_frac).unwrap());
    }

    #[test]
    fn test_integer_positive() {
        let float = Float::parse("12345.6789".to_string()).unwrap();
        let int = float.integer().unwrap();
        let expected = Float::parse("12345".to_string()).unwrap();
        assert!(int.eq(expected).unwrap());

        let frac = float.frac().unwrap();
        let recombined = (int + frac).unwrap();
        assert!(float.eq(recombined).unwrap());
    }

    #[test]
    fn test_integer_negative() {
        let float = Float::parse("-12345.6789".to_string()).unwrap();
        let int = float.integer().unwrap();
        let frac = float.frac().unwrap();

        // integer truncates toward zero, so -12345.6789 -> -12345
        let expected_int = Float::parse("-12345".to_string()).unwrap();
        let expected_frac = Float::parse("-0.6789".to_string()).unwrap();

        assert!(int.eq(expected_int).unwrap());
        assert!(frac.eq(expected_frac).unwrap());

        // integer + frac == original
        let recombined = (int + frac).unwrap();
        assert!(float.eq(recombined).unwrap());
    }

    #[test]
    fn test_integer_whole_numbers() {
        let pos = Float::parse("42".to_string()).unwrap();
        assert!(pos.integer().unwrap().eq(pos).unwrap());
        let zero = Float::parse("0".to_string()).unwrap();
        assert!(pos.frac().unwrap().eq(zero).unwrap());

        let neg = Float::parse("-42".to_string()).unwrap();
        assert!(neg.integer().unwrap().eq(neg).unwrap());
        assert!(neg.frac().unwrap().eq(zero).unwrap());
    }

    proptest! {
        #[test]
        fn test_from_to_fixed_decimal_valid_range(coeff in any::<I224>(), decimals in 0u8..=66u8) {
            prop_assume!(coeff >= I224::ZERO);

            let exponent = -(decimals as i32);
            let value = U256::from(coeff);

            let float = Float::from_fixed_decimal(value, decimals).unwrap();
            let expected = Float::pack_lossless(coeff, exponent).unwrap();
            prop_assert!(float.eq(expected).unwrap());

            let fixed = float.to_fixed_decimal(decimals).unwrap();
            assert_eq!(fixed, value);
        }
    }

    proptest! {
        #[test]
        fn test_int_frac_properties(float in arb_float()) {
            let int = float.integer().unwrap();
            let frac = float.frac().unwrap();

            let zero = Float::parse("0".to_string()).unwrap();

            prop_assert!(
                int.frac().unwrap().eq(zero).unwrap(),
                "int.frac() is not zero: {}",
                int.show_unpacked().unwrap()
            );

            prop_assert!(
                frac.integer().unwrap().eq(zero).unwrap(),
                "frac.integer() is not zero: {}",
                frac.show_unpacked().unwrap()
            );

            let recombined = (int + frac).unwrap();
            prop_assert!(
                float.eq(recombined).unwrap(),
                "original: {}, int: {}, frac: {}, recombined: {}",
                float.show_unpacked().unwrap(),
                int.show_unpacked().unwrap(),
                frac.show_unpacked().unwrap(),
                recombined.show_unpacked().unwrap()
            );

            let one = Float::parse("1".to_string()).unwrap();
            let neg_one = one.neg().unwrap();
            prop_assert!(
                frac.lt(one).unwrap(),
                "frac not < 1: {}",
                frac.show_unpacked().unwrap()
            );
            prop_assert!(
                frac.gt(neg_one).unwrap(),
                "frac not > -1: {}",
                frac.show_unpacked().unwrap()
            );
        }
    }

    #[test]
    fn test_min_max_manual() {
        let negone = Float::parse("-1".to_string()).unwrap();
        let zero = Float::parse("0".to_string()).unwrap();
        let three = Float::parse("3".to_string()).unwrap();
        let seven = Float::parse("7".to_string()).unwrap();

        // --- min ---
        assert!(negone.eq(negone.min(zero).unwrap()).unwrap());
        assert!(negone.eq(negone.min(three).unwrap()).unwrap());
        assert!(zero.eq(zero.min(three).unwrap()).unwrap());
        // min with identical arguments should return that argument
        assert!(seven.eq(seven.min(seven).unwrap()).unwrap());

        // --- max ---
        assert!(zero.eq(negone.max(zero).unwrap()).unwrap());
        assert!(three.eq(negone.max(three).unwrap()).unwrap());
        assert!(three.eq(zero.max(three).unwrap()).unwrap());
        // max with identical arguments should return that argument
        assert!(seven.eq(seven.max(seven).unwrap()).unwrap());
    }

    #[test]
    fn test_is_zero_manual() {
        let zero = Float::parse("0".to_string()).unwrap();
        assert!(zero.is_zero().unwrap());

        // Alternative zero representations that should also be considered zero.
        let neg_zero = Float::parse("-0".to_string()).unwrap();
        assert!(neg_zero.is_zero().unwrap());
        let zero_point = Float::parse("0.0".to_string()).unwrap();
        assert!(zero_point.is_zero().unwrap());

        let one = Float::parse("1".to_string()).unwrap();
        assert!(!one.is_zero().unwrap());
    }

    proptest! {
        #[test]
        fn test_min_max_properties(a in reasonable_float(), b in reasonable_float()) {
            let min = a.min(b).unwrap();
            let max = a.max(b).unwrap();

            prop_assert!(
                !min.gt(a).unwrap(),
                "min > a: min={}, a={}",
                min.show_unpacked().unwrap(),
                a.show_unpacked().unwrap()
            );
            prop_assert!(
                !min.gt(b).unwrap(),
                "min > b: min={}, b={}",
                min.show_unpacked().unwrap(),
                b.show_unpacked().unwrap()
            );

            prop_assert!(
                !max.lt(a).unwrap(),
                "max < a: max={}, a={}",
                max.show_unpacked().unwrap(),
                a.show_unpacked().unwrap()
            );
            prop_assert!(
                !max.lt(b).unwrap(),
                "max < b: max={}, b={}",
                max.show_unpacked().unwrap(),
                b.show_unpacked().unwrap()
            );

            let min_is_a = min.eq(a).unwrap();
            let min_is_b = min.eq(b).unwrap();
            prop_assert!(
                min_is_a || min_is_b,
                "min is not equal to either operand: a={}, b={}, min={}",
                a.show_unpacked().unwrap(),
                b.show_unpacked().unwrap(),
                min.show_unpacked().unwrap()
            );

            let max_is_a = max.eq(a).unwrap();
            let max_is_b = max.eq(b).unwrap();
            prop_assert!(
                max_is_a || max_is_b,
                "max is not equal to either operand: a={}, b={}, max={}",
                a.show_unpacked().unwrap(),
                b.show_unpacked().unwrap(),
                max.show_unpacked().unwrap()
            );

            prop_assert!(
                !min.gt(max).unwrap(),
                "min > max: min={}, max={}",
                min.show_unpacked().unwrap(),
                max.show_unpacked().unwrap()
            );
        }
    }

    #[test]
    fn test_lte_gte() {
        let negone = Float::parse("-1".to_string()).unwrap();
        let zero = Float::parse("0".to_string()).unwrap();
        let three = Float::parse("3".to_string()).unwrap();

        assert!(negone.lte(zero).unwrap());
        assert!(zero.lte(three).unwrap());
        assert!(negone.lte(three).unwrap());

        assert!(zero.gte(negone).unwrap());
        assert!(three.gte(zero).unwrap());
        assert!(three.gte(negone).unwrap());
    }

    proptest! {
        #[test]
        fn test_lte_gte_fuzz(a in reasonable_float()) {
            let b = a;
            let one = Float::parse("1".to_string()).unwrap();

            let a = (a - one).unwrap();
            let lte = a.lte(b).unwrap();
            prop_assert!(lte); // lt

            let a = (a + one).unwrap();
            let gte = a.gte(b).unwrap();
            let lte = a.lte(b).unwrap();
            prop_assert!(gte); // eq
            prop_assert!(lte); // eq

            let a = (a + one).unwrap();
            let gte = a.gte(b).unwrap();
            prop_assert!(gte); // gt
        }
    }

    #[test]
    fn test_from_fixed_decimal_lossy() {
        // Test lossless conversions (values that fit in Float's precision)
        let lossless_cases = vec![
            (U256::from(0u128), 0u8, "0"),
            (U256::from(0u128), 18u8, "0"),
            (U256::from(1u128), 18u8, "1e-18"),
            (U256::from(123456789u128), 0u8, "123456789"),
            (U256::from(123456789u128), 2u8, "123456789e-2"),
            (U256::from(1000000000000000000u128), 18u8, "1"),
        ];

        for (amount, decimals, expected) in lossless_cases {
            let (float, lossless) =
                Float::from_fixed_decimal_lossy(amount, decimals).expect("should convert");
            let expected = Float::parse(expected.to_string()).unwrap();
            assert!(float.eq(expected).unwrap());
            assert!(
                lossless,
                "conversion should be lossless for amount={}, decimals={}",
                amount, decimals
            );
        }

        // Test lossy conversion with U256::MAX (too large to fit in Float's 224-bit coefficient)
        let (float, lossless) = Float::from_fixed_decimal_lossy(U256::MAX, 1).unwrap();
        assert!(!lossless, "U256::MAX conversion should be lossy");
        assert!(!float.is_zero().unwrap(), "result should not be zero");
    }

    #[test]
    fn test_to_fixed_decimal_lossy() {
        // Test lossy conversions (loss of precision)
        let lossy_cases = vec![
            (U256::from(1), 18u8, 0u128),
            (U256::from(123456789), 0u8, 12345678u128),
            (U256::from(123456789), 2u8, 12345678u128),
        ];

        for (input, decimals, expected) in lossy_cases {
            let float = Float::from_fixed_decimal(input, decimals + 1).unwrap();
            let (fixed, lossless) = float.to_fixed_decimal_lossy(decimals).unwrap();
            assert_eq!(
                fixed,
                U256::from(expected),
                "wrong value for input={}, decimals={}",
                input,
                decimals
            );
            assert!(
                !lossless,
                "should be lossy for input={}, decimals={}",
                input, decimals
            );
        }

        // Test lossless conversions (no loss of precision)
        let lossless_cases = vec![
            // Zero is always lossless
            (U256::from(0), 0u8, 0u128),
            (U256::from(0), 18u8, 0u128),
            // Converting 12340 with 3 decimals (12.340) to 2 decimals (12.34) is lossless
            (U256::from(12340), 3u8, 1234u128),
        ];

        for (input, decimals, expected) in lossless_cases {
            let float = Float::from_fixed_decimal(input, decimals + 1).unwrap();
            let (fixed, lossless) = float.to_fixed_decimal_lossy(decimals).unwrap();
            assert_eq!(
                fixed,
                U256::from(expected),
                "wrong value for input={}, decimals={}",
                input,
                decimals
            );
            assert!(
                lossless,
                "should be lossless for input={}, decimals={}",
                input, decimals
            );
        }
    }

    proptest! {
        #[test]
        fn test_from_to_fixed_decimal_lossy_valid_range(coeff in any::<I224>(), decimals in 0u8..=66u8) {
            prop_assume!(coeff >= I224::ZERO);

            let exponent = -(decimals as i32 + 1);
            let value = U256::from(coeff);

            let (float, from_lossless) = Float::from_fixed_decimal_lossy(value, decimals + 1).unwrap();
            let expected = Float::pack_lossless(coeff, exponent).unwrap();
            prop_assert!(float.eq(expected).unwrap());

            // from_fixed_decimal_lossy should be lossless for values that fit in Float's precision
            prop_assert!(from_lossless, "from_fixed_decimal_lossy should be lossless for coeff={coeff}");

            let (fixed, to_lossless) = float.to_fixed_decimal_lossy(decimals).unwrap();
            assert_eq!(fixed, value / U256::from(10));

            // Converting from decimals+1 to decimals should be lossy unless the value is zero or
            // the last digit is zero (divisible by 10)
            if value == U256::ZERO || value % U256::from(10) == U256::ZERO {
                prop_assert!(to_lossless, "to_fixed_decimal_lossy should be lossless when last digit is 0: value={}", value);
            } else {
                prop_assert!(!to_lossless, "to_fixed_decimal_lossy should be lossy when losing precision: value={}", value);
            }
        }
    }

    proptest! {
        #[test]
        fn test_constants_relationships(float in reasonable_float()) {
            let max_pos = Float::max_positive_value().unwrap();
            let min_pos = Float::min_positive_value().unwrap();
            let max_neg = Float::max_negative_value().unwrap();
            let min_neg = Float::min_negative_value().unwrap();
            let zero = Float::parse("0".to_string()).unwrap();

            // Test that constants are the extremes
            // Any reasonable positive float should be <= max_positive and >= min_positive
            if float.gt(zero).unwrap() {
                prop_assert!(float.lte(max_pos).unwrap());
                prop_assert!(float.gte(min_pos).unwrap());
            }

            // Any reasonable negative float should be <= max_negative and >= min_negative
            // (max_negative is closest to zero, min_negative is furthest from zero)
            if float.lt(zero).unwrap() {
                prop_assert!(float.lte(max_neg).unwrap());
                prop_assert!(float.gte(min_neg).unwrap());
            }

            // Constants should be consistent regardless of arbitrary float
            prop_assert!(max_pos.gt(zero).unwrap());
            prop_assert!(min_pos.gt(zero).unwrap());
            prop_assert!(max_neg.lt(zero).unwrap());
            prop_assert!(min_neg.lt(zero).unwrap());

            // Verify constants maintain their ordering
            prop_assert!(min_pos.lt(max_pos).unwrap());
            prop_assert!(min_neg.lt(max_neg).unwrap());
            prop_assert!(max_neg.lt(zero).unwrap());
            prop_assert!(min_pos.gt(zero).unwrap());
        }
    }

    proptest! {
        #[test]
        fn test_constants_edge_cases(float in arb_float()) {
            let max_pos = Float::max_positive_value().unwrap();
            let min_pos = Float::min_positive_value().unwrap();
            let max_neg = Float::max_negative_value().unwrap();
            let min_neg = Float::min_negative_value().unwrap();

            // Constants should always be distinct
            prop_assert!(!max_pos.eq(min_pos).unwrap());
            prop_assert!(!max_neg.eq(min_neg).unwrap());
            prop_assert!(!max_pos.eq(max_neg).unwrap());
            prop_assert!(!min_pos.eq(min_neg).unwrap());

            // Test that constants are at the boundaries
            // (Note: We can't test arithmetic operations that would overflow/underflow
            // since those would fail, but we can test comparisons)

            // No arbitrary float should be greater than max_pos or less than min_neg
            if !float.eq(max_pos).unwrap() {
                prop_assert!(!float.gt(max_pos).unwrap());
            }
            if !float.eq(min_neg).unwrap() {
                prop_assert!(!float.lt(min_neg).unwrap());
            }
        }
    }
}
