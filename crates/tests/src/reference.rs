//! An exact reference for the library's non-transcendental surface, in big
//! integers. A value is `c × 10^e` with an unbounded `c` and an `i64` `e`, so
//! no operation here rounds unless it says so.
//!
//! Every rounding below is the one the library documents: a result becomes
//! the Float closest to it that does not exceed its magnitude (`packLossy`).
//! A result no non-zero Float is within is `ExponentUnderflow`; a result
//! larger in magnitude than every Float is `ExponentOverflow`. Addition first
//! aligns its operands as `LibDecimalFloatImplementation.add` and
//! `LibDecimalFloat.agree` describe, discarding the smaller operand's digits
//! below the unit of the larger operand's maximized coefficient.

use alloy::primitives::{B256, U256};
use core::cmp::Ordering;
use num_bigint::{BigInt, Sign};
use num_traits::{Signed, Zero};

/// A Solidity error the reference expects, by signature.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RefError {
    ExponentOverflow,
    ExponentUnderflow,
    DivisionByZero,
    CoefficientOverflow,
    LossyConversionToFloat,
    LossyConversionFromFloat,
    NegativeFixedDecimalConversion,
    FixedDecimalOverflow,
    UnformatableExponent,
    ParseDecimalPrecisionLoss,
    ParseDecimalOverflow,
    Log10Zero,
    Log10Negative,
    ZeroNegativePower,
    PowNegativeBase,
    AgreeToleranceNegative,
    AgreeNoPositiveTolerance,
    ParseDecimalFloatExcessCharacters,
}

impl RefError {
    pub fn signature(self) -> &'static str {
        match self {
            Self::ExponentOverflow => "ExponentOverflow(int256,int256)",
            Self::ExponentUnderflow => "ExponentUnderflow(int256,int256)",
            Self::DivisionByZero => "DivisionByZero(int256,int256)",
            Self::CoefficientOverflow => "CoefficientOverflow(int256,int256)",
            Self::LossyConversionToFloat => "LossyConversionToFloat(int256,int256)",
            Self::LossyConversionFromFloat => "LossyConversionFromFloat(int256,int256)",
            Self::NegativeFixedDecimalConversion => "NegativeFixedDecimalConversion(int256,int256)",
            Self::FixedDecimalOverflow => "FixedDecimalOverflow(int256,int256,uint8)",
            Self::UnformatableExponent => "UnformatableExponent(int256)",
            Self::ParseDecimalPrecisionLoss => "ParseDecimalPrecisionLoss(uint256)",
            Self::ParseDecimalOverflow => "ParseDecimalOverflow(uint256)",
            Self::Log10Zero => "Log10Zero()",
            Self::Log10Negative => "Log10Negative(int256,int256)",
            Self::ZeroNegativePower => "ZeroNegativePower(bytes32)",
            Self::PowNegativeBase => "PowNegativeBase(int256,int256)",
            Self::AgreeToleranceNegative => "AgreeToleranceNegative(bytes32,bytes32)",
            Self::AgreeNoPositiveTolerance => "AgreeNoPositiveTolerance(bytes32,bytes32)",
            Self::ParseDecimalFloatExcessCharacters => "ParseDecimalFloatExcessCharacters()",
        }
    }

    pub fn name(self) -> &'static str {
        let s = self.signature();
        &s[..s.find('(').unwrap()]
    }

    pub fn selector(self) -> [u8; 4] {
        let hash = alloy::primitives::keccak256(self.signature());
        [hash[0], hash[1], hash[2], hash[3]]
    }
}

pub const I32_MIN: i64 = i32::MIN as i64;
pub const I32_MAX: i64 = i32::MAX as i64;

pub fn pow10(k: u64) -> BigInt {
    num_traits::pow(BigInt::from(10), k as usize)
}

pub fn int224_min() -> BigInt {
    -(BigInt::from(1) << 223usize)
}

pub fn int224_max() -> BigInt {
    (BigInt::from(1) << 223usize) - 1
}

pub fn int256_min() -> BigInt {
    -(BigInt::from(1) << 255usize)
}

pub fn int256_max() -> BigInt {
    (BigInt::from(1) << 255usize) - 1
}

pub fn fits_int224(c: &BigInt) -> bool {
    *c >= int224_min() && *c <= int224_max()
}

pub fn fits_int256(c: &BigInt) -> bool {
    *c >= int256_min() && *c <= int256_max()
}

/// Number of decimal digits in `|c|`, zero for zero.
pub fn digits(c: &BigInt) -> u64 {
    if c.is_zero() {
        0
    } else {
        c.abs().to_string().len() as u64
    }
}

/// `c / 10^k`, truncated towards zero.
fn shed(c: &BigInt, k: u64) -> BigInt {
    if k > digits(c) {
        BigInt::zero()
    } else {
        c / pow10(k)
    }
}

/// An exact decimal `c × 10^e`.
#[derive(Debug, Clone)]
pub struct Dec {
    pub c: BigInt,
    pub e: i64,
}

impl Dec {
    pub fn new(c: impl Into<BigInt>, e: i64) -> Self {
        Self { c: c.into(), e }
    }

    pub fn zero() -> Self {
        Self::new(0, 0)
    }

    pub fn is_zero(&self) -> bool {
        self.c.is_zero()
    }

    pub fn is_negative(&self) -> bool {
        self.c.is_negative()
    }

    /// The unpacked fields of a packed Float, as `LibDecimalFloat.unpack`
    /// documents them: the low 224 bits sign extended, the high 32 bits
    /// arithmetic shifted.
    pub fn from_bytes(f: B256) -> Self {
        let bytes = f.0;
        let e = i32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as i64;
        let c = BigInt::from_signed_bytes_be(&bytes[4..]);
        Self { c, e }
    }

    /// The packed Float of an int224 coefficient and an int32 exponent.
    pub fn to_bytes(&self) -> B256 {
        assert!(fits_int224(&self.c), "coefficient {} is not int224", self.c);
        let e = i32::try_from(self.e).expect("exponent is not int32");
        let mut bytes = [0u8; 32];
        bytes[..4].copy_from_slice(&e.to_be_bytes());
        let c = self.c.to_signed_bytes_be();
        let fill = if self.c.is_negative() { 0xff } else { 0 };
        bytes[4..32 - c.len()].fill(fill);
        bytes[32 - c.len()..].copy_from_slice(&c);
        B256::from(bytes)
    }

    /// The same value with no trailing decimal zeros, zero as `0e0`.
    pub fn normalized(&self) -> Self {
        if self.c.is_zero() {
            return Self::zero();
        }
        let mut c = self.c.clone();
        let mut e = self.e;
        let ten = BigInt::from(10);
        while (&c % &ten).is_zero() {
            c /= &ten;
            e += 1;
        }
        Self { c, e }
    }

    pub fn neg(&self) -> Self {
        Self::new(-&self.c, self.e)
    }

    pub fn abs(&self) -> Self {
        Self::new(self.c.abs(), self.e)
    }

    /// `self × 10^k` written at exponent `self.e - k`, for `k >= 0`.
    fn at_exponent(&self, e: i64) -> BigInt {
        assert!(e <= self.e);
        &self.c * pow10((self.e - e) as u64)
    }

    /// Exact numeric comparison, for any exponents.
    pub fn cmp_value(&self, other: &Self) -> Ordering {
        let (sa, sb) = (self.c.sign(), other.c.sign());
        if sa != sb {
            return sign_rank(sa).cmp(&sign_rank(sb));
        }
        if sa == Sign::NoSign {
            return Ordering::Equal;
        }
        // Same non-zero sign. Compare magnitudes by order first, so that
        // exponents billions apart never align.
        let order_a = self.e + digits(&self.c) as i64;
        let order_b = other.e + digits(&other.c) as i64;
        let magnitude = if order_a != order_b {
            order_a.cmp(&order_b)
        } else {
            let e = self.e.min(other.e);
            self.at_exponent(e).abs().cmp(&other.at_exponent(e).abs())
        };
        if sa == Sign::Minus {
            magnitude.reverse()
        } else {
            magnitude
        }
    }

    pub fn eq_value(&self, other: &Self) -> bool {
        self.cmp_value(other) == Ordering::Equal
    }

    /// The exact sum, when the exponents are close enough to align in memory.
    /// Past that gap the sum spans more digits than any Float holds.
    pub fn add_exact(&self, other: &Self) -> Option<Self> {
        if self.is_zero() {
            return Some(other.clone());
        }
        if other.is_zero() {
            return Some(self.clone());
        }
        if (self.e - other.e).abs() > 400 {
            return None;
        }
        let e = self.e.min(other.e);
        Some(Self::new(self.at_exponent(e) + other.at_exponent(e), e))
    }

    pub fn mul_exact(&self, other: &Self) -> Self {
        Self::new(&self.c * &other.c, self.e + other.e)
    }

    /// The quotient truncated towards zero to at least 92 significant digits,
    /// which is more than any Float holds, so truncating it again to fit a
    /// Float is the truncation of the exact quotient.
    fn div_truncated(&self, other: &Self) -> Self {
        const EXTRA: u64 = 160;
        Self::new(
            &self.c * pow10(EXTRA) / &other.c,
            self.e - other.e - EXTRA as i64,
        )
    }

    /// The integer part, truncated towards zero.
    pub fn trunc(&self) -> Self {
        if self.e >= 0 {
            self.clone()
        } else {
            Self::new(shed(&self.c, (-self.e) as u64), 0)
        }
    }

    /// Exactly representable as a Float: an int224 coefficient and an int32
    /// exponent, after removing trailing zeros or adding them.
    pub fn representable(&self) -> bool {
        matches!(pack(self), Packed::Value(_, true))
    }
}

fn sign_rank(s: Sign) -> i8 {
    match s {
        Sign::Minus => -1,
        Sign::NoSign => 0,
        Sign::Plus => 1,
    }
}

/// The result of fitting an exact value into a Float.
#[derive(Debug, Clone)]
pub enum Packed {
    /// The Float closest to the value that does not exceed its magnitude,
    /// and whether that is the value.
    Value(Dec, bool),
    /// No non-zero Float is within the value's magnitude.
    Underflow,
    /// Larger in magnitude than every Float, past rounding into one.
    Overflow,
}

/// The coefficient of `x` at exponent `f`, truncated towards zero, then
/// clamped to int224.
fn coefficient_at(x: &Dec, f: i64) -> BigInt {
    let c = if f >= x.e {
        shed(&x.c, (f - x.e) as u64)
    } else {
        // Past 80 digits up the clamp is reached anyway.
        &x.c * pow10(((x.e - f) as u64).min(80))
    };
    c.clamp(int224_min(), int224_max())
}

/// The largest in magnitude of `c × 10^f` not exceeding `|x|`, over int224
/// `c` and `f` in `[lo, hi]`. Every exponent below `x`'s 70th digit clamps to
/// a smaller bound, and every exponent above its 66th truncates further, so
/// the window between and the two ends hold the best.
fn nearest_within(x: &Dec, lo: i64, hi: i64) -> Dec {
    let top = x.e + digits(&x.c) as i64;
    let mut best = Dec::zero();
    for f in (top - 70..=top - 66).chain([lo, hi]) {
        let f = f.clamp(lo, hi);
        let candidate = Dec::new(coefficient_at(x, f), f);
        if candidate.abs().cmp_value(&best.abs()) == Ordering::Greater {
            best = candidate;
        }
    }
    best
}

/// Fit an exact value into a Float: the Float closest to it that does not
/// exceed its magnitude, written at the exponent nearest the value's own.
/// The value overflows when that Float, with the exponent unbounded, is past
/// every Float of its sign, and underflows when it is zero within int32.
pub fn pack(x: &Dec) -> Packed {
    if x.c.is_zero() {
        return Packed::Value(Dec::zero(), true);
    }
    let top = x.e + digits(&x.c) as i64;
    let unbounded = nearest_within(x, top - 70, top - 66);
    if unbounded.cmp_value(&Dec::new(int224_max(), I32_MAX)) == Ordering::Greater
        || unbounded.cmp_value(&Dec::new(int224_min(), I32_MAX)) == Ordering::Less
    {
        return Packed::Overflow;
    }
    let best = nearest_within(x, I32_MIN, I32_MAX);
    if best.is_zero() {
        return Packed::Underflow;
    }
    // Every exponent `best` is exact at, within int32.
    let (mut c, mut e) = (best.c.clone(), best.e);
    while e > I32_MIN && fits_int224(&(&c * 10)) {
        c *= 10;
        e -= 1;
    }
    let target = x.e.clamp(e, I32_MAX);
    while e < target && (&c % 10u32).is_zero() {
        c /= 10;
        e += 1;
    }
    let out = Dec::new(c, e);
    let lossless = out.eq_value(x);
    Packed::Value(out, lossless)
}

/// `packArithmeticResult`: truncation is tolerated, underflow and overflow
/// revert.
pub fn arithmetic(x: &Dec) -> Result<Dec, RefError> {
    match pack(x) {
        Packed::Value(v, _) => Ok(v),
        Packed::Underflow => Err(RefError::ExponentUnderflow),
        Packed::Overflow => Err(RefError::ExponentOverflow),
    }
}

/// `c × 10^k` for the largest `k` that keeps it in int256, as
/// `LibDecimalFloatImplementation.maximize` documents.
fn maximize(x: &Dec) -> Dec {
    let mut c = x.c.clone();
    let mut e = x.e;
    loop {
        let next = &c * 10;
        if !fits_int256(&next) {
            return Dec::new(c, e);
        }
        c = next;
        e -= 1;
    }
}

/// `add` under its documented alignment: both operands maximized, the one
/// with the smaller exponent truncated towards zero to the other's unit, then
/// the sum packed.
pub fn add(a: &Dec, b: &Dec) -> Result<Dec, RefError> {
    if a.is_zero() {
        return arithmetic(b);
    }
    if b.is_zero() {
        return arithmetic(a);
    }
    let (mut big, mut small) = (maximize(a), maximize(b));
    if small.e > big.e {
        core::mem::swap(&mut big, &mut small);
    }
    let gap = (big.e - small.e) as u64;
    let aligned = shed(&small.c, gap);
    arithmetic(&Dec::new(&big.c + aligned, big.e))
}

pub fn sub(a: &Dec, b: &Dec) -> Result<Dec, RefError> {
    add(a, &b.neg())
}

pub fn mul(a: &Dec, b: &Dec) -> Result<Dec, RefError> {
    arithmetic(&a.mul_exact(b))
}

pub fn div(a: &Dec, b: &Dec) -> Result<Dec, RefError> {
    if b.is_zero() {
        return Err(RefError::DivisionByZero);
    }
    if a.is_zero() {
        return Ok(Dec::zero());
    }
    arithmetic(&a.div_truncated(b))
}

pub fn inv(a: &Dec) -> Result<Dec, RefError> {
    div(&Dec::new(1, 0), a)
}

pub fn minus(a: &Dec) -> Result<Dec, RefError> {
    arithmetic(&a.neg())
}

pub fn abs(a: &Dec) -> Result<Dec, RefError> {
    arithmetic(&a.abs())
}

pub fn integer(a: &Dec) -> Result<Dec, RefError> {
    arithmetic(&a.trunc())
}

pub fn frac(a: &Dec) -> Result<Dec, RefError> {
    if a.e >= 0 {
        return Ok(Dec::zero());
    }
    let t = a.trunc();
    if t.is_zero() {
        return arithmetic(a);
    }
    arithmetic(&Dec::new(&a.c - t.at_exponent(a.e), a.e))
}

pub fn floor(a: &Dec) -> Result<Dec, RefError> {
    let t = a.trunc();
    if a.is_negative() && !t.eq_value(a) {
        arithmetic(&Dec::new(t.c - 1, 0))
    } else {
        arithmetic(&t)
    }
}

pub fn ceil(a: &Dec) -> Result<Dec, RefError> {
    let t = a.trunc();
    if !a.is_negative() && !t.eq_value(a) {
        arithmetic(&Dec::new(t.c + 1, 0))
    } else {
        arithmetic(&t)
    }
}

/// The documented extremes: `type(int224).max`, `type(int32).max`; `1`,
/// `type(int32).min`; `-1`, `type(int32).min`; `type(int224).min`,
/// `type(int32).max`.
pub fn max_positive() -> Dec {
    Dec::new(int224_max(), I32_MAX)
}

pub fn min_positive() -> Dec {
    Dec::new(1, I32_MIN)
}

pub fn max_negative() -> Dec {
    Dec::new(-1, I32_MIN)
}

pub fn min_negative() -> Dec {
    Dec::new(int224_min(), I32_MAX)
}

/// `fromFixedDecimalLossy`: `value × 10^-decimals`, truncated to fit, and
/// whether that was exact.
pub fn from_fixed_decimal_lossy(value: U256, decimals: u8) -> (Dec, bool) {
    let x = Dec::new(u256_to_big(value), -(decimals as i64));
    match pack(&x) {
        Packed::Value(v, lossless) => (v, lossless),
        // decimals is at most 255 so the exponent never leaves int32.
        other => unreachable!("{other:?}"),
    }
}

/// `fromFixedDecimalLossless`: a value above int256.max is first divided by
/// ten (`LossyConversionToFloat` when that drops a non-zero digit), then the
/// result must pack losslessly (`CoefficientOverflow`).
pub fn from_fixed_decimal_lossless(value: U256, decimals: u8) -> Result<Dec, RefError> {
    let (v, lossless) = from_fixed_decimal_lossy(value, decimals);
    if lossless {
        return Ok(v);
    }
    let big = u256_to_big(value);
    if big > int256_max() && !(&big % 10u32).is_zero() {
        Err(RefError::LossyConversionToFloat)
    } else {
        Err(RefError::CoefficientOverflow)
    }
}

/// `toFixedDecimalLossy`: `x × 10^decimals` truncated towards zero, and
/// whether that was exact.
pub fn to_fixed_decimal_lossy(x: &Dec, decimals: u8) -> Result<(U256, bool), RefError> {
    if x.is_negative() {
        return Err(RefError::NegativeFixedDecimalConversion);
    }
    if x.is_zero() {
        return Ok((U256::ZERO, true));
    }
    let scaled = Dec::new(x.c.clone(), x.e + decimals as i64);
    if scaled.e > 80 {
        return Err(RefError::FixedDecimalOverflow);
    }
    let t = scaled.trunc();
    let int = if t.e > 0 {
        t.at_exponent(0)
    } else {
        t.c.clone()
    };
    if int > u256_to_big(U256::MAX) {
        return Err(RefError::FixedDecimalOverflow);
    }
    let value = U256::from_str_radix(&int.to_string(), 10).unwrap();
    Ok((value, t.eq_value(&scaled)))
}

pub fn to_fixed_decimal_lossless(x: &Dec, decimals: u8) -> Result<U256, RefError> {
    match to_fixed_decimal_lossy(x, decimals)? {
        (v, true) => Ok(v),
        (_, false) => Err(RefError::LossyConversionFromFloat),
    }
}

pub fn u256_to_big(v: U256) -> BigInt {
    BigInt::from_bytes_be(Sign::Plus, &v.to_be_bytes::<32>())
}

/// `packLossy` over any int256 coefficient and exponent: the value as
/// `pack` fits it and whether that was exact, `FLOAT_ZERO` and lossy when
/// every digit is shed, `ExponentOverflow` past every Float.
pub fn pack_lossy(c: &BigInt, e: &BigInt) -> Result<(Dec, bool), RefError> {
    match pack(&Dec::new(c.clone(), pin(e))) {
        Packed::Value(v, lossless) => Ok((v, lossless)),
        Packed::Underflow => Ok((Dec::zero(), false)),
        Packed::Overflow => Err(RefError::ExponentOverflow),
    }
}

/// `packLossless`: `packLossy`, with any lost digit `CoefficientOverflow`.
pub fn pack_lossless(c: &BigInt, e: &BigInt) -> Result<Dec, RefError> {
    match pack_lossy(c, e)? {
        (v, true) => Ok(v),
        (_, false) => Err(RefError::CoefficientOverflow),
    }
}

/// `packArithmeticResult`: truncation tolerated, every digit shed is
/// `ExponentUnderflow`.
pub fn pack_arithmetic(c: &BigInt, e: &BigInt) -> Result<Dec, RefError> {
    arithmetic(&Dec::new(c.clone(), pin(e)))
}

/// `canonicalize`: zero as `FLOAT_ZERO`, otherwise the largest `|c|` that
/// fits int224 with the exponent at or above int32.min, the same value.
pub fn canonicalize(x: &Dec) -> Dec {
    if x.is_zero() {
        return Dec::zero();
    }
    let (mut c, mut e) = (x.c.clone(), x.e);
    while e > I32_MIN && fits_int224(&(&c * 10)) {
        c *= 10;
        e -= 1;
    }
    Dec::new(c, e)
}

/// `agree`, as its NatSpec states it: a negative tolerance is
/// `AgreeToleranceNegative`, neither positive `AgreeNoPositiveTolerance`;
/// otherwise `highest - lowest <= max(absolute, proportional * max(|lowest|,
/// |highest|))`, the spread aligned as `sub` aligns it and nothing packed.
pub fn agree(
    absolute: &Dec,
    proportional: &Dec,
    lowest: &Dec,
    highest: &Dec,
) -> Result<bool, RefError> {
    if absolute.is_negative() || proportional.is_negative() {
        return Err(RefError::AgreeToleranceNegative);
    }
    if absolute.is_zero() && proportional.is_zero() {
        return Err(RefError::AgreeNoPositiveTolerance);
    }
    let spread = aligned_sum(highest, &lowest.neg());
    let anchor = if lowest.abs().cmp_value(&highest.abs()) == Ordering::Greater {
        lowest.abs()
    } else {
        highest.abs()
    };
    let scaled = proportional.mul_exact(&anchor);
    let limit = if absolute.cmp_value(&scaled) == Ordering::Greater {
        absolute.clone()
    } else {
        scaled
    };
    Ok(spread.cmp_value(&limit) != Ordering::Greater)
}

/// The sum under `add`'s documented alignment, before packing.
fn aligned_sum(a: &Dec, b: &Dec) -> Dec {
    if a.is_zero() {
        return b.clone();
    }
    if b.is_zero() {
        return a.clone();
    }
    let (mut big, mut small) = (maximize(a), maximize(b));
    if small.e > big.e {
        core::mem::swap(&mut big, &mut small);
    }
    let gap = (big.e - small.e) as u64;
    Dec::new(&big.c + shed(&small.c, gap), big.e)
}

/// `isOdd`: an odd whole number.
pub fn is_odd(x: &Dec) -> bool {
    let t = x.trunc();
    let n = t.normalized();
    t.eq_value(x) && n.e == 0 && !(&n.c % 2u32).is_zero()
}

/// `fromFixedDecimalLossy` unpacked: `value × 10^-decimals` as an int256
/// coefficient, shedding the one digit a value past int256.max has too many,
/// and whether that was exact.
pub fn from_fixed_decimal_lossy_unpacked(value: U256, decimals: u8) -> (Dec, bool) {
    let v = u256_to_big(value);
    let e = -(decimals as i64);
    if fits_int256(&v) {
        (Dec::new(v, e), true)
    } else {
        let lossless = (&v % 10u32).is_zero();
        (Dec::new(v / 10u32, e + 1), lossless)
    }
}

pub fn from_fixed_decimal_lossless_unpacked(value: U256, decimals: u8) -> Result<Dec, RefError> {
    match from_fixed_decimal_lossy_unpacked(value, decimals) {
        (v, true) => Ok(v),
        (_, false) => Err(RefError::LossyConversionToFloat),
    }
}

/// `toFixedDecimalLossy` over any int256 coefficient and exponent:
/// `exponent + decimals` past int256.max is `ExponentOverflow`, otherwise as
/// `to_fixed_decimal_lossy`.
pub fn to_fixed_decimal_lossy_unpacked(
    c: &BigInt,
    e: &BigInt,
    decimals: u8,
) -> Result<(U256, bool), RefError> {
    if c.is_negative() {
        return Err(RefError::NegativeFixedDecimalConversion);
    }
    if !c.is_zero() && !fits_int256(&(e + decimals)) {
        return Err(RefError::ExponentOverflow);
    }
    to_fixed_decimal_lossy(&Dec::new(c.clone(), pin(e)), decimals)
}

pub fn to_fixed_decimal_lossless_unpacked(
    c: &BigInt,
    e: &BigInt,
    decimals: u8,
) -> Result<U256, RefError> {
    match to_fixed_decimal_lossy_unpacked(c, e, decimals)? {
        (v, true) => Ok(v),
        (_, false) => Err(RefError::LossyConversionFromFloat),
    }
}

/// The documented string of `toDecimalString(x, true)`: one integral digit,
/// the remaining significant digits after a point, and the exponent unless
/// it is zero.
pub fn format_scientific(x: &Dec) -> Result<String, RefError> {
    if x.is_zero() {
        return Ok("0".to_string());
    }
    let n = x.normalized();
    let digits_str = n.c.abs().to_string();
    let display = n.e + digits_str.len() as i64 - 1;
    if !(I32_MIN..=I32_MAX).contains(&display) {
        return Err(RefError::UnformatableExponent);
    }
    let mut out = String::new();
    if n.is_negative() {
        out.push('-');
    }
    out.push_str(&digits_str[..1]);
    if digits_str.len() > 1 {
        out.push('.');
        out.push_str(&digits_str[1..]);
    }
    if display != 0 {
        out.push_str(&format!("e{display}"));
    }
    Ok(out)
}

/// The documented string of `toDecimalString(x, false)`: plain decimal for
/// `|exponent| <= 1000`, and for a positive exponent only while the integer
/// it writes fits int224.
pub fn format_plain(x: &Dec) -> Result<String, RefError> {
    if x.is_zero() {
        return Ok("0".to_string());
    }
    if x.e.abs() > 1000 {
        return Err(RefError::UnformatableExponent);
    }
    if x.e > 0 && (x.e >= 68 || x.c.abs() > int224_max() / pow10(x.e as u64)) {
        return Err(RefError::UnformatableExponent);
    }
    let n = x.normalized();
    let d = n.c.abs().to_string();
    let mut out = String::new();
    if n.is_negative() {
        out.push('-');
    }
    if n.e >= 0 {
        out.push_str(&d);
        out.push_str(&"0".repeat(n.e as usize));
    } else {
        let point = (-n.e) as usize;
        if d.len() > point {
            out.push_str(&d[..d.len() - point]);
            out.push('.');
            out.push_str(&d[d.len() - point..]);
        } else {
            out.push_str("0.");
            out.push_str(&"0".repeat(point - d.len()));
            out.push_str(&d);
        }
    }
    Ok(out)
}

/// The exact value of a well formed decimal literal
/// `-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?`, without the library's limits.
pub fn literal_value(s: &str) -> Dec {
    let (mantissa, exp) = match s.find(['e', 'E']) {
        Some(i) => (
            &s[..i],
            s[i + 1..]
                .trim_start_matches('+')
                .parse::<BigInt>()
                .unwrap(),
        ),
        None => (s, BigInt::zero()),
    };
    let (int, frac) = match mantissa.find('.') {
        Some(i) => (&mantissa[..i], &mantissa[i + 1..]),
        None => (mantissa, ""),
    };
    let negative = int.starts_with('-');
    let mut c: BigInt = format!("{}{}", int.trim_start_matches('-'), frac)
        .parse()
        .unwrap();
    if negative {
        c = -c;
    }
    let e = exp - frac.len();
    match i64::try_from(&e) {
        Ok(e) => Dec::new(c, e),
        // An exponent past i64 is far past int32 either way; keep its sign.
        Err(_) => Dec::new(
            c,
            if e.is_negative() {
                i64::MIN / 2
            } else {
                i64::MAX / 2
            },
        ),
    }
}

/// `LibParseDecimalFloat.parseDecimalFloat` over a well formed literal: the
/// integer part, fraction digits (trailing zeros dropped) and exponent are
/// each read as int256 (`ParseDecimalOverflow`); a non-zero integer part
/// takes at most 67 fraction digits and the combined coefficient must fit
/// int224 (`ParseDecimalPrecisionLoss`); the exponent sum must fit int256
/// (`ExponentOverflow`); then the value packs, where any lost digit is
/// `ParseDecimalPrecisionLoss` and a value past every Float is
/// `ExponentOverflow`.
pub fn parse(s: &str) -> Result<Dec, RefError> {
    parse_packed(&parse_unpacked(s)?)
}

/// The value packs, where any lost digit is `ParseDecimalPrecisionLoss` and
/// a value past every Float is `ExponentOverflow`.
pub fn parse_packed(x: &Dec) -> Result<Dec, RefError> {
    match pack(x) {
        Packed::Value(v, true) => Ok(v),
        Packed::Value(_, false) | Packed::Underflow => Err(RefError::ParseDecimalPrecisionLoss),
        Packed::Overflow => Err(RefError::ExponentOverflow),
    }
}

/// The parser's limits before packing; the value it hands to packing.
pub fn parse_unpacked(s: &str) -> Result<Dec, RefError> {
    let (c, e) = parse_inline(s)?;
    Ok(Dec::new(c, pin(&e)))
}

/// An int256 exponent past a quarter of i64 is past int32 by billions of
/// digits, so pinning it there leaves what packing and conversion decide
/// unchanged, with room for their exponent arithmetic.
pub fn pin(e: &BigInt) -> i64 {
    i64::try_from(e)
        .ok()
        .filter(|v| v.abs() < i64::MAX / 4)
        .unwrap_or(if e.is_negative() {
            i64::MIN / 4
        } else {
            i64::MAX / 4
        })
}

/// `parseDecimalFloatInline` over a whole well formed literal: the
/// coefficient and int256 exponent `parse_unpacked` describes, zero at
/// exponent zero.
pub fn parse_inline(s: &str) -> Result<(BigInt, BigInt), RefError> {
    let (mantissa, exp_str) = match s.find(['e', 'E']) {
        Some(i) => (&s[..i], Some(&s[i + 1..])),
        None => (s, None),
    };
    let (int_str, frac_str) = match mantissa.find('.') {
        Some(i) => (&mantissa[..i], Some(&mantissa[i + 1..])),
        None => (mantissa, None),
    };
    let negative = int_str.starts_with('-');
    let int: BigInt = int_str.parse().unwrap();
    let int_limit = if negative {
        -int256_min()
    } else {
        int256_max()
    };
    if int.abs() > int_limit {
        return Err(RefError::ParseDecimalOverflow);
    }
    let mut c = int.clone();
    let mut e: BigInt = BigInt::zero();
    if let Some(frac_str) = frac_str {
        let trimmed = frac_str.trim_end_matches('0');
        if !trimmed.is_empty() {
            let f: BigInt = trimmed.parse().unwrap();
            if f > int256_max() {
                return Err(RefError::ParseDecimalOverflow);
            }
            let f = if negative { -f } else { f };
            let scale = trimmed.len() as u64;
            e = -BigInt::from(scale);
            if int.is_zero() {
                c = f;
            } else {
                if scale > 67 {
                    return Err(RefError::ParseDecimalPrecisionLoss);
                }
                let rescaled = &int * pow10(scale);
                if !fits_int224(&rescaled) {
                    return Err(RefError::ParseDecimalPrecisionLoss);
                }
                c = rescaled + f;
            }
        }
    }
    if let Some(exp_str) = exp_str {
        let x: BigInt = exp_str.trim_start_matches('+').parse().unwrap();
        let limit = if x.is_negative() {
            -int256_min()
        } else {
            int256_max()
        };
        if x.abs() > limit {
            return Err(RefError::ParseDecimalOverflow);
        }
        e += x;
        if !fits_int256(&e) {
            return Err(RefError::ExponentOverflow);
        }
    }
    if c.is_zero() {
        return Ok((BigInt::zero(), BigInt::zero()));
    }
    Ok((c, e))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pack_grows_into_the_exponent_ceiling() {
        let Packed::Value(v, true) = pack(&Dec::new(1, I32_MAX + 1)) else {
            panic!()
        };
        assert_eq!((v.c, v.e), (BigInt::from(10), I32_MAX));
        assert!(matches!(
            pack(&Dec::new(int224_max(), I32_MAX + 1)),
            Packed::Overflow
        ));
    }

    #[test]
    fn pack_sheds_to_the_exponent_floor() {
        let Packed::Value(v, true) = pack(&Dec::new(100, I32_MIN - 2)) else {
            panic!()
        };
        assert_eq!((v.c, v.e), (BigInt::from(1), I32_MIN));
        assert!(matches!(
            pack(&Dec::new(99, I32_MIN - 2)),
            Packed::Underflow
        ));
        let Packed::Value(v, false) = pack(&Dec::new(-199, I32_MIN - 2)) else {
            panic!()
        };
        assert_eq!((v.c, v.e), (BigInt::from(-1), I32_MIN));
    }

    #[test]
    fn pack_truncates_towards_zero() {
        let Packed::Value(v, false) = pack(&Dec::new(-(int224_max() * 10u32 + 9u32), 0)) else {
            panic!()
        };
        assert_eq!((v.c, v.e), (-int224_max(), 1));
        // int224.min fits for a negative coefficient only.
        let Packed::Value(v, true) = pack(&Dec::new(int224_min(), 0)) else {
            panic!()
        };
        assert_eq!(v.c, int224_min());
        let Packed::Value(v, false) = pack(&Dec::new(-int224_min(), 0)) else {
            panic!()
        };
        assert_eq!((v.c, v.e), (int224_max(), 0));
    }

    #[test]
    fn float_bytes_round_trip() {
        for (c, e) in [
            (int224_min(), I32_MIN),
            (int224_max(), I32_MAX),
            (BigInt::from(-1), 0),
        ] {
            let d = Dec::new(c.clone(), e);
            let back = Dec::from_bytes(d.to_bytes());
            assert_eq!((back.c, back.e), (c, e));
        }
    }

    #[test]
    fn add_drops_digits_below_the_aligned_unit() {
        // agree's NatSpec: 1 - (-1e-100) is exactly 1 to sub.
        let one = Dec::new(1, 0);
        let r = sub(&one, &Dec::new(-1, -100)).unwrap();
        assert!(r.eq_value(&one));
        // 1e100 + -1 keeps 1e100: the -1 is below the aligned unit.
        let r = add(&Dec::new(1, 100), &Dec::new(-1, 0)).unwrap();
        assert!(r.eq_value(&Dec::new(1, 100)));
    }

    #[test]
    fn literal_and_parse() {
        assert!(literal_value("-1.50e+2").eq_value(&Dec::new(-150, 0)));
        assert!(parse("-0.5").unwrap().eq_value(&Dec::new(-5, -1)));
        assert!(matches!(
            parse("1.00000000000000000000000000000000000000000000000000000000000000000001"),
            Err(RefError::ParseDecimalPrecisionLoss)
        ));
        assert!(
            parse("1e2147483648")
                .unwrap()
                .eq_value(&Dec::new(10, I32_MAX))
        );
    }

    #[test]
    fn format_strings() {
        assert_eq!(format_scientific(&Dec::new(-12300, -2)).unwrap(), "-1.23e2");
        assert_eq!(format_scientific(&Dec::new(1, 0)).unwrap(), "1");
        assert_eq!(format_plain(&Dec::new(-12300, -5)).unwrap(), "-0.123");
        assert_eq!(format_plain(&Dec::new(12, 2)).unwrap(), "1200");
        assert_eq!(format_plain(&Dec::new(15, -1)).unwrap(), "1.5");
    }
}
