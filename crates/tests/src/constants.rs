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

/// Extra digits carried through the series so truncation at `PLACES` is
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

/// `atan(1/x) * 10^scale` by the alternating series, stopped at the first
/// term that floors to zero, with the number of terms summed. Repeated floor
/// division is the floor of the full quotient, so each summed term is short
/// of its exact value by less than 1, and the dropped alternating tail is
/// below the exact value of the first dropped term, itself below 1: the
/// result is within `terms + 1` of the exact value.
fn atan_inv(x: u64, scale: u32) -> (U512, u64) {
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
    (sum, k)
}

/// `pi * 10^scale` by Machin's formula, with a bound the exact value is
/// strictly within.
fn pi_scaled(scale: u32) -> (U512, U512) {
    let (a5, n5) = atan_inv(5, scale);
    let (a239, n239) = atan_inv(239, scale);
    let error = 16 * (n5 + 1) + 4 * (n239 + 1);
    (
        U512::from(16u64) * a5 - U512::from(4u64) * a239,
        U512::from(error),
    )
}

/// `e * 10^scale` by the series sum of 1/k!, with a bound the exact value is
/// strictly within. Each summed term is `floor(10^scale / k!)`, short by less
/// than 1, and the dropped tail starts at a term below 1 whose successors
/// shrink by at least half each step, so it is below 2.
fn e_scaled(scale: u32) -> (U512, U512) {
    let mut term = ten_pow(scale);
    let mut sum = U512::ZERO;
    let mut k = 1u64;
    while !term.is_zero() {
        sum += term;
        term /= U512::from(k);
        k += 1;
    }
    (sum, U512::from(k + 2))
}

/// Drops `GUARD` digits toward zero. The exact value lies strictly within
/// `error` of `scaled`, so the floor is exact when the dropped digits are at
/// least `error` from both ends of their range.
fn truncate_to_places((scaled, error): (U512, U512)) -> I224 {
    let divisor = ten_pow(GUARD);
    let (q, r) = (scaled / divisor, scaled % divisor);
    assert!(
        r >= error && r + error <= divisor,
        "guard digits too close to a boundary"
    );
    I224::from_dec_str(&q.to_string()).unwrap()
}

/// The largest coefficient the packing fits, `type(int224).max`.
fn int224_max() -> U512 {
    (U512::from(1u8) << 223usize) - U512::from(1u8)
}

/// `name` is the closest Float not above the value `derived` brackets, at
/// exponent `-PLACES`, and the next finer exponent does not fit.
fn assert_closest_float_not_above(name: &str, derived: (U512, U512)) {
    let (coefficient, exponent) = unpack(packed_constant(name));
    assert_eq!(exponent, -(PLACES as i32));
    assert_eq!(coefficient, truncate_to_places(derived));
    let (scaled, error) = derived;
    assert!((scaled - error) / ten_pow(GUARD - 1) > int224_max());
}

#[test]
fn float_pi_is_the_closest_float_not_above_pi() {
    assert_closest_float_not_above("FLOAT_PI", pi_scaled(PLACES + GUARD));
}

#[test]
fn float_e_is_the_closest_float_not_above_e() {
    assert_closest_float_not_above("FLOAT_E", e_scaled(PLACES + GUARD));
}

/// The first 72 significant digits of pi (OEIS A000796,
/// https://oeis.org/A000796/b000796.txt) and of e (OEIS A001113,
/// https://oeis.org/A001113/b001113.txt).
const PI_72_DIGITS: &str =
    "314159265358979323846264338327950288419716939937510582097494459230781640";
const E_72_DIGITS: &str =
    "271828182845904523536028747135266249775724709369995957496696762772407663";

#[test]
fn derivations_start_with_the_published_digits() {
    assert!(
        pi_scaled(PLACES + GUARD)
            .0
            .to_string()
            .starts_with(PI_72_DIGITS)
    );
    assert!(
        e_scaled(PLACES + GUARD)
            .0
            .to_string()
            .starts_with(E_72_DIGITS)
    );
}

#[test]
fn constants_are_the_published_digits_truncated() {
    let (pi, _) = unpack(packed_constant("FLOAT_PI"));
    let (e, _) = unpack(packed_constant("FLOAT_E"));
    assert_eq!(pi.to_string(), PI_72_DIGITS[..67]);
    assert_eq!(e.to_string(), E_72_DIGITS[..67]);
}

/// The implementation library source, as committed.
const IMPLEMENTATION: &str =
    include_str!("../../../src/lib/implementation/LibDecimalFloatImplementation.sol");

/// The decimal literal `LibDecimalFloatImplementation.sol` assigns to the
/// constant `name`.
fn decimal_constant(name: &str) -> num_bigint::BigUint {
    let decl = format!("constant {name} =");
    let at = IMPLEMENTATION
        .find(&decl)
        .unwrap_or_else(|| panic!("{name} is not declared in LibDecimalFloatImplementation.sol"));
    let rest = IMPLEMENTATION[at + decl.len()..].trim_start();
    let end = rest.find(';').expect("no `;` after the declaration");
    rest[..end].parse().expect("a decimal literal")
}

/// `LOG10_RATIO_Z_MAX` is the largest z at 1e-50 whose 16th power is below
/// 1e-50: z^16 < 10^(16 * 50 - 50) <= (z + 1)^16.
#[test]
fn log10_ratio_z_max_is_the_largest_z_with_z16_below_1e_minus_50() {
    let z = decimal_constant("LOG10_RATIO_Z_MAX");
    let bound = num_bigint::BigUint::from(10u8).pow(750);
    assert!(z.pow(16) < bound);
    assert!((z + 1u8).pow(16) >= bound);
}

/// `LOG10_SKIP_BELOW` is the least c with 1001 c >= 10^79, so
/// `log10Unrounded` skips reduction exactly for c at least 1e76 / 1.001.
#[test]
fn log10_skip_below_is_the_least_c_with_1001c_at_least_1e79() {
    let c = decimal_constant("LOG10_SKIP_BELOW");
    let bound = num_bigint::BigUint::from(10u8).pow(79);
    assert!(&c * 1001u16 >= bound);
    assert!((c - 1u8) * 1001u16 < bound);
}

// ------------------------------------------------------------------ SPEC.md

/// The signed-off spec.
const SPEC: &str = include_str!("../../../SPEC.md");

/// Every `.sol` file under `dir`.
fn sol_files(dir: &std::path::Path) -> Vec<std::path::PathBuf> {
    let mut files = Vec::new();
    for entry in std::fs::read_dir(dir).unwrap_or_else(|e| panic!("{}: {e}", dir.display())) {
        let path = entry.unwrap().path();
        if path.is_dir() {
            files.extend(sol_files(&path));
        } else if path.extension().is_some_and(|x| x == "sol") {
            files.push(path);
        }
    }
    files
}

/// Every error `src` declares has a rule in SPEC.md, by name, so no revert
/// path ships unruled.
#[test]
fn spec_names_every_error() {
    let src = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../src");
    let mut declared = 0;
    for path in sol_files(&src) {
        let source = std::fs::read_to_string(&path).unwrap();
        for line in source.lines() {
            let Some(decl) = line.trim_start().strip_prefix("error ") else {
                continue;
            };
            let name = &decl[..decl
                .find('(')
                .unwrap_or_else(|| panic!("{}: `{line}`", path.display()))];
            assert!(
                SPEC.contains(&format!("`{name}")),
                "{name} ({}) has no rule in SPEC.md",
                path.display()
            );
            declared += 1;
        }
    }
    assert!(declared > 0, "no errors declared under {}", src.display());
}
