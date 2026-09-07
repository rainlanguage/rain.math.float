//! Cross-references the constants `LibDecimalFloat.sol` packs against values
//! derived here in integer arithmetic. The Solidity source is bound at compile
//! time and the packed words are read out of it, so a change to a constant in
//! the library is a change to what these tests check.

use alloy_primitives::aliases::{I224, U224};
use alloy_primitives::{U256, U512};

/// The library source, as committed.
const LIB: &str = include_str!("../../../src/lib/LibDecimalFloat.sol");

/// Decimal places the library packs the constants at.
const PLACES: u32 = 66;

/// Extra digits carried through the series so rounding at `PLACES` is
/// exact.
const GUARD: u32 = 12;

/// The packed word `LibDecimalFloat.sol` assigns to the constant `name`:
/// the 64 hex digits following its `=`.
fn packed_constant(name: &str) -> U256 {
    let decl = format!("constant {name} =");
    let at = LIB
        .find(&decl)
        .unwrap_or_else(|| panic!("{name} is not declared in LibDecimalFloat.sol"));
    let rest = &LIB[at + decl.len()..];
    let hex_at = rest
        .find("0x")
        .expect("no hex literal after the declaration");
    let hex = &rest[hex_at + 2..hex_at + 2 + 64];
    U256::from_str_radix(hex, 16).expect("64 hex digits")
}

/// Splits a packed `Float` into its signed 224-bit coefficient and signed
/// 32-bit exponent: the exponent is the high 32 bits, the coefficient the
/// low 224.
fn unpack(word: U256) -> (I224, i32) {
    let exponent = (word >> 224usize).to::<u32>() as i32;
    let mask = (U256::from(1u8) << 224usize) - U256::from(1u8);
    let coefficient = I224::from_raw((word & mask).to::<U224>());
    (coefficient, exponent)
}

fn ten_pow(n: u32) -> U512 {
    U512::from(10u64).pow(U512::from(n))
}

/// `atan(1/x) * 10^scale` by the alternating series, truncated once a term
/// underflows the scale. Every intermediate is an integer.
fn atan_inv(x: u64, scale: u32) -> U512 {
    let x = U512::from(x);
    let x2 = x * x;
    let mut power = ten_pow(scale) / x;
    let mut sum = U512::ZERO;
    let mut k = 0u64;
    loop {
        let term = power / U512::from(2 * k + 1);
        if term.is_zero() {
            break;
        }
        if k.is_multiple_of(2) {
            sum += term;
        } else {
            sum -= term;
        }
        power /= x2;
        k += 1;
    }
    sum
}

/// `pi * 10^scale` by Machin's formula.
fn pi_scaled(scale: u32) -> U512 {
    U512::from(16u64) * atan_inv(5, scale) - U512::from(4u64) * atan_inv(239, scale)
}

/// `e * 10^scale` by the series sum of 1/k!.
fn e_scaled(scale: u32) -> U512 {
    let mut term = ten_pow(scale);
    let mut sum = U512::ZERO;
    let mut k = 1u64;
    while !term.is_zero() {
        sum += term;
        term /= U512::from(k);
        k += 1;
    }
    sum
}

/// Drops `GUARD` digits, rounding to nearest.
fn round_to_places(scaled: U512) -> I224 {
    let divisor = ten_pow(GUARD);
    let (q, r) = (scaled / divisor, scaled % divisor);
    let rounded = if r * U512::from(2u64) >= divisor {
        q + U512::from(1u64)
    } else {
        q
    };
    I224::from_dec_str(&rounded.to_string()).unwrap()
}

#[test]
fn float_pi_is_pi_rounded_to_nearest() {
    let (coefficient, exponent) = unpack(packed_constant("FLOAT_PI"));
    assert_eq!(exponent, -(PLACES as i32));
    assert_eq!(coefficient, round_to_places(pi_scaled(PLACES + GUARD)));
}

#[test]
fn float_e_is_e_rounded_to_nearest() {
    let (coefficient, exponent) = unpack(packed_constant("FLOAT_E"));
    assert_eq!(exponent, -(PLACES as i32));
    assert_eq!(coefficient, round_to_places(e_scaled(PLACES + GUARD)));
}

#[test]
fn derivations_start_with_the_known_digits() {
    assert!(
        pi_scaled(PLACES + GUARD)
            .to_string()
            .starts_with("314159265358979323846264338327950288")
    );
    assert!(
        e_scaled(PLACES + GUARD)
            .to_string()
            .starts_with("271828182845904523536028747135266249")
    );
}
