use crate::{Float, FloatError};
use alloy::primitives::aliases::I224;
use revm::primitives::{B256, U256};
use std::{
    ops::{Add, Div, Mul, Neg, Sub},
    str::FromStr,
};
use wasm_bindgen_utils::prelude::{js_sys::BigInt, *};

#[wasm_bindgen]
impl Float {
    /// Returns the 32-byte hexadecimal string representation of the float.
    ///
    /// # Returns
    ///
    /// * `String` - The 32-byte hex string.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const float = Float.fromHex("0x0000000000000000000000000000000000000000000000000000000000000005").value!;
    /// assert(float.asHex() === "0x0000000000000000000000000000000000000000000000000000000000000005");
    /// ```
    #[wasm_bindgen(js_name = "asHex", unchecked_return_type = "`0x${string}`")]
    pub fn as_hex_js(&self) -> String {
        self.as_hex()
    }

    /// Convert the float to a JS/TS bigint.
    ///
    /// # Throws
    /// if conversion fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const float = Float.fromHex("0x0000000000000000000000000000000000000000000000000000000000000005");
    /// const value = float.toBigInt();
    /// assert(value === 5n);
    /// ```
    #[wasm_bindgen(js_name = "toBigint", unchecked_return_type = "bigint")]
    pub fn to_bigint(&self) -> BigInt {
        self.try_to_bigint().unwrap_throw()
    }

    /// Constructs a `Float` from a bigint.
    ///
    /// # Throws
    /// if conversion fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const float = Float.fromBigint(5n);
    /// assert(float.asHex() === "0x0000000000000000000000000000000000000000000000000000000000000005");
    /// ```
    #[wasm_bindgen(js_name = "fromBigint")]
    pub fn from_bigint(value: BigInt) -> Float {
        Self::try_from_bigint(value).unwrap_throw()
    }
}

#[wasm_export]
impl Float {
    /// Tries to convert the float to a JS/TS bigint.
    ///
    /// # Returns
    ///
    /// * `Ok(bigint)` - The resulting `bigint` value.
    /// * `Err(FloatError)` - If the conversion fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const float = Float.fromHex("0x0000000000000000000000000000000000000000000000000000000000000005");
    /// const bigintResult = float.tryToBigInt();
    /// if (bigintResult.error) {
    ///     console.error(bigintResult.error);
    /// }
    /// assert(bigintResult.value === 5n);
    /// ```
    #[wasm_export(
        js_name = "tryToBigint",
        preserve_js_class,
        unchecked_return_type = "bigint"
    )]
    pub fn try_to_bigint(&self) -> Result<BigInt, FloatError> {
        Ok(BigInt::from_str(&self.as_hex())?)
    }

    /// Constructs a `Float` from a bigint.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The resulting `Float` value.
    /// * `Err(FloatError)` - If the conversion fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const floatResult = Float.tryFromBigint(5n);
    /// if (floatResult.error) {
    ///   console.error(floatResult.error);
    /// }
    /// const value = float.value;
    /// assert(value.asHex() === "0x0000000000000000000000000000000000000000000000000000000000000005");
    /// ```
    #[wasm_export(js_name = "tryFromBigint", preserve_js_class)]
    pub fn try_from_bigint(value: BigInt) -> Result<Float, FloatError> {
        // convert to 16 radix string and append 0 if length is odd
        let mut value: String = value.to_string(16)?.into();
        if value.len() % 2 == 1 {
            value = format!("0{}", value);
        }
        Ok(Float(B256::left_padding_from(&alloy::hex::decode(&value)?)))
    }

    /// Converts a fixed-point decimal value to a `Float` using the specified number of decimals.
    ///
    /// # Arguments
    ///
    /// * `value` - The fixed-point decimal value as a `string`.
    /// * `decimals` - The number of decimals in the fixed-point representation.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The resulting `Float` value.
    /// * `Err(FloatError)` - If the conversion fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const floatResult = Float.fromFixedDecimal("12345", 2);
    /// if (floatResult.error) {
    ///    console.error(floatResult.error);
    /// }
    /// const float = floatResult.value;
    /// assert(float.format() === "123.45");
    /// ```
    #[wasm_export(js_name = "fromFixedDecimal", preserve_js_class)]
    pub fn from_fixed_decimal_js(value: String, decimals: u8) -> Result<Float, FloatError> {
        let val = U256::from_str(&value)?;
        Self::from_fixed_decimal(val, decimals)
    }

    /// Packs a coefficient and exponent into a `Float` in a lossless manner.
    ///
    /// # Arguments
    ///
    /// * `coefficient` - The coefficient as an `string`.
    /// * `exponent` - The exponent as an `number`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The packed float.
    /// * `Err(FloatError)` - If the packing fails (e.g., overflow).
    ///
    /// # Example
    ///
    /// ```typescript
    /// const floatResult = Float.packLossless("314", -2);
    /// if (floatResult.error) {
    ///    console.error(floatResult.error);
    /// }
    /// const float = floatResult.value;
    /// assert(float.format() === "3.14");
    /// ```
    #[wasm_export(js_name = "packLossless", preserve_js_class)]
    pub fn pack_lossless_js(coefficient: String, exponent: i32) -> Result<Float, FloatError> {
        let val = I224::from_str(&coefficient)?;
        Self::pack_lossless(val, exponent)
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
    /// ```typescript
    /// const floatResult = Float.parse("3.1415");
    /// if (floatResult.error) {
    ///    console.error(floatResult.error);
    /// }
    /// const float = floatResult.value;
    /// assert(float.format() === "3.1415");
    /// ```
    #[wasm_export(js_name = "parse", preserve_js_class)]
    pub fn parse_js(str: String) -> Result<Float, FloatError> {
        Self::parse(str)
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
    /// ```typescript
    /// const floatResult = Float.fromHex("0x0000000000000000000000000000000000000000000000000000000000000005");
    /// if (floatResult.error) {
    ///    console.error(floatResult.error);
    /// }
    /// const float = floatResult.value;
    /// assert(float.asHex() === "0.0000000000000000000000000000000000000000000000000000000000000005");
    /// ```
    #[wasm_export(js_name = "fromHex", preserve_js_class)]
    pub fn from_hex_js(
        #[wasm_export(unchecked_param_type = "`0x${string}`")] hex: &str,
    ) -> Result<Float, FloatError> {
        Self::from_hex(hex)
    }

    /// Formats the float as a decimal string.
    ///
    /// NOTE: Uses 18 decimal places and fails if the float has more than
    /// that number of decimals.
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - The formatted string.
    /// * `Err(FloatError)` - If formatting fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const floatResult = Float.parse("2.5");
    /// if (floatResult.error) {
    ///    console.error(floatResult.error);
    /// }
    /// const float = floatResult.value;
    /// assert(float.format() === "2.5");
    /// ```
    #[wasm_export(js_name = "format")]
    pub fn format_js(&self) -> Result<String, FloatError> {
        self.format()
    }

    /// Formats the float as a decimal string. Gets truncated to 18 decimal
    /// places if it has more than that.
    ///
    /// # Returns
    ///
    /// * `Ok(String)` - The formatted string.
    /// * `Err(FloatError)` - If formatting fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const floatResult = Float.parse("2.5");
    /// if (floatResult.error) {
    ///    console.error(floatResult.error);
    /// }
    /// const float = floatResult.value;
    /// assert(float.format18() === "2.5");
    /// ```
    #[wasm_export(js_name = "format18")]
    pub fn format18_js(&self) -> Result<String, FloatError> {
        self.format18()
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
    /// ```typescript
    /// const a = Float.parse("1.0").value!;
    /// const b = Float.parse("2.0").value!;
    /// const result = a.lt(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value);
    /// ```
    #[wasm_export(js_name = "lt", unchecked_return_type = "boolean")]
    pub fn lt_js(&self, b: &Self) -> Result<bool, FloatError> {
        self.lt(*b)
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
    /// ```typescript
    /// const a = Float.parse("2.0").value!;
    /// const b = Float.parse("2.0").value!;
    /// const result = a.eq(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value);
    /// ```
    #[wasm_export(js_name = "eq", unchecked_return_type = "boolean")]
    pub fn eq_js(&self, b: &Self) -> Result<bool, FloatError> {
        self.eq(*b)
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
    /// ```typescript
    /// const a = Float.parse("1.0").value!;
    /// const b = Float.parse("2.0").value!;
    /// const result = a.lte(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value);
    /// ```
    #[wasm_export(js_name = "lte", unchecked_return_type = "boolean")]
    pub fn lte_js(&self, b: &Self) -> Result<bool, FloatError> {
        self.lte(*b)
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
    /// ```typescript
    /// const a = Float.parse("2.0").value!;
    /// const b = Float.parse("1.0").value!;
    /// const result = a.gte(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value);
    /// ```
    #[wasm_export(js_name = "gte", unchecked_return_type = "boolean")]
    pub fn gte_js(&self, b: &Self) -> Result<bool, FloatError> {
        self.gte(*b)
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
    /// ```typescript
    /// const a = Float.parse("2.0").value!;
    /// const b = Float.parse("1.0").value!;
    /// const result = a.gt(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value);
    /// ```
    #[wasm_export(js_name = "gt", unchecked_return_type = "boolean")]
    pub fn gt_js(&self, b: &Self) -> Result<bool, FloatError> {
        self.gt(*b)
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
    /// ```typescript
    /// const x = Float.parse("2.0").value!;
    /// const inv = x.inv();
    /// if (inv.error) {
    ///    console.error(inv.error);
    /// }
    /// assert(inv.value.format().startsWith("0.5"));
    /// ```
    #[wasm_export(js_name = "inv", preserve_js_class)]
    pub fn inv_js(&self) -> Result<Float, FloatError> {
        self.inv()
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
    /// ```typescript
    /// const x = Float.parse("-3.14").value!;
    /// const abs = x.abs();
    /// if (abs.error) {
    ///    console.error(abs.error);
    /// }
    /// assert(abs.value.format() === "3.14");
    /// ```
    #[wasm_export(js_name = "abs", preserve_js_class)]
    pub fn abs_js(&self) -> Result<Float, FloatError> {
        self.abs()
    }

    /// Adds two floats.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The sum.
    /// * `Err(FloatError)` - If addition fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const a = Float.parse("1.5").value!;
    /// const b = Float.parse("2.5").value!;
    /// const result = a.add(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value.format() === "4");
    /// ```
    #[wasm_export(js_name = "add", preserve_js_class)]
    pub fn add_js(&self, b: &Self) -> Result<Float, FloatError> {
        self.add(*b)
    }

    /// Subtracts `b` from `self`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The difference.
    /// * `Err(FloatError)` - If subtraction fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const a = Float.parse("5.0").value!;
    /// const b = Float.parse("2.0").value!;
    /// const result = a.sub(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value.format() === "3");
    /// ```
    #[wasm_export(js_name = "sub", preserve_js_class)]
    pub fn sub_js(&self, b: &Self) -> Result<Float, FloatError> {
        self.sub(*b)
    }

    /// Multiplies two floats.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The product.
    /// * `Err(FloatError)` - If multiplication fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const a = Float.parse("2.0").value!;
    /// const b = Float.parse("3.0").value!;
    /// const result = a.mul(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value.format() === "6");
    /// ```
    #[wasm_export(js_name = "mul", preserve_js_class)]
    pub fn mul_js(&self, b: &Self) -> Result<Float, FloatError> {
        self.mul(*b)
    }

    /// Divides `self` by `b`.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The quotient.
    /// * `Err(FloatError)` - If division fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const a = Float.parse("6.0").value!;
    /// const b = Float.parse("2.0").value!;
    /// const result = a.div(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value.format() === "3");
    /// ```
    #[wasm_export(js_name = "div", preserve_js_class)]
    pub fn div_js(&self, b: &Self) -> Result<Float, FloatError> {
        self.div(*b)
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
    /// ```typescript
    /// const x = Float.parse("3.75").value!;
    /// const result = x.frac();
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value.format() === "0.75");
    /// ```
    #[wasm_export(js_name = "frac", preserve_js_class)]
    pub fn frac_js(&self) -> Result<Float, FloatError> {
        self.frac()
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
    /// ```typescript
    /// const x = Float.parse("3.75").value!;
    /// const result = x.floor();
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value.format() === "3");
    /// ```
    #[wasm_export(js_name = "floor", preserve_js_class)]
    pub fn floor_js(&self) -> Result<Float, FloatError> {
        self.floor()
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
    /// ```typescript
    /// const a = Float.parse("1.0").value!;
    /// const b = Float.parse("2.0").value!;
    /// const result = a.min(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value.format() === "1");
    /// ```
    #[wasm_export(js_name = "min", preserve_js_class)]
    pub fn min_js(&self, b: &Self) -> Result<Float, FloatError> {
        self.min(*b)
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
    /// ```typescript
    /// const a = Float.parse("1.0").value!;
    /// const b = Float.parse("2.0").value!;
    /// const result = a.max(b);
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value.format() === "2");
    /// ```
    #[wasm_export(js_name = "max", preserve_js_class)]
    pub fn max_js(&self, b: &Self) -> Result<Float, FloatError> {
        self.max(*b)
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
    /// ```typescript
    /// const zero = Float.parse("0").value!;
    /// const result = zero.isZero();
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value);
    /// ```
    #[wasm_export(js_name = "isZero", unchecked_return_type = "boolean")]
    pub fn is_zero_js(&self) -> Result<bool, FloatError> {
        self.is_zero()
    }

    /// Returns the negation of the float.
    ///
    /// # Returns
    ///
    /// * `Ok(Float)` - The negated value.
    /// * `Err(FloatError)` - If the operation fails.
    ///
    /// # Example
    ///
    /// ```typescript
    /// const x = Float.parse("3.14").value!;
    /// const result = x.neg();
    /// if (result.error) {
    ///    console.error(result.error);
    /// }
    /// assert(result.value.format() === "-3.14");
    /// ```
    #[wasm_export(js_name = "neg", preserve_js_class)]
    pub fn neg_js(&self) -> Result<Float, FloatError> {
        self.neg()
    }
}
