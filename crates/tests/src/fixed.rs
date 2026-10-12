//! `exp10Fixed` and `log10Ratio`, the fixed point cores of pow10 and log10,
//! against the bounds their NatSpec proves:
//! - the series coefficients and step constants are exact floors;
//! - every one of exp10Fixed's 2^16 step products is enumerated against
//!   astro-float, so the bound over every cell holds and is tight;
//! - the worst inputs found sit inside the bounds and near them;
//! - log10Ratio over its domain, both modes, against astro-float.

use crate::evm::{self, TestDecimalFloatHarness as H};
use crate::exact::config;
use crate::precise::{self, Approx};
use crate::reference::{Dec, pow10};
use alloy::primitives::U256;
use num_bigint::{BigInt, Sign};
use num_integer::Integer;
use num_traits::{Signed, Zero};
use proptest::prelude::*;
use proptest::test_runner::TestCaseError;

/// The bounds under test.
///
/// exp10Fixed is under 88.08 units of 1e-50 below 10^x 1e50.
const EXP10_FIXED_E52: u64 = 8_808;
/// exp10Fixed is under 1.408e-49 of 10^x below it.
const EXP10_FIXED_RELATIVE_E52: u64 = 1_408;
/// pow10's fixed point power is under 111.11 units of 1e-50 below 10^x 1e50.
const POW10_RAW_E52: u64 = 11_111;
/// The series is under 1.07902 units of 1e-50 below 10^r 1e50: its floored
/// coefficients and Horner steps, under 1 + 2r / (1 - r), and the terms past
/// the ninth, under (ln 10 2^-16)^10 / 10! 1e50 / (1 - r), 0.079.
const SERIES_LOSS_E5: u64 = 107_902;
/// For z = |a - b| / (a + b) at most 5.1e-4, as log10Unrounded passes,
/// log10Ratio relative is under C 8.03e-50 plus a unit below the true log.
const LOG10_RATIO_RELATIVE_E53: u64 = 8_030;
/// log10Ratio at the fixed point is under 1.0036 units below the true log.
const LOG10_RATIO_FIXED_E54: u64 = 10_036;
/// Up to `LOG10_RATIO_Z_MAX` those are C 8.082e-50 plus a unit and 1.0053
/// units.
const LOG10_RATIO_WIDE_RELATIVE_E53: u64 = 8_082;
const LOG10_RATIO_WIDE_FIXED_E54: u64 = 10_053;
/// log10Ratio is at most 1.3e-51 of the true log above it.
const LOG10_RATIO_ABOVE_E52: u64 = 13;

/// 2^-16 at 1e16.
const STEP: u64 = 152_587_890_625;

fn u256(x: &BigInt) -> U256 {
    U256::from_str_radix(&x.to_string(), 10).unwrap()
}

fn exp10_fixed(x: &BigInt) -> BigInt {
    let r = evm::harness(H::exp10FixedCall { x: u256(x) }).unwrap();
    r.to_string().parse().unwrap()
}

fn log10_ratio(a: &BigInt, b: &BigInt, relative: bool) -> Result<(BigInt, i64), TestCaseError> {
    let r = evm::harness(H::log10RatioCall {
        a: u256(a),
        b: u256(b),
        relative,
    })
    .map_err(|e| TestCaseError::fail(format!("log10Ratio({a}, {b}, {relative}) reverted {e}")))?;
    Ok((
        r._0.to_string().parse().unwrap(),
        r._1.to_string().parse().unwrap(),
    ))
}

fn step() -> BigInt {
    BigInt::from(STEP) * pow10(34)
}

/// Integers lo <= t 10^scale <= hi, for t's error under a unit there.
fn enclose(t: &Approx, scale: i64) -> (BigInt, BigInt) {
    let v = &t.value;
    let e = v.e + scale;
    let (q, exact) = if e >= 0 {
        (&v.c * pow10(e as u64), true)
    } else {
        let (q, r) = v.c.div_mod_floor(&pow10((-e) as u64));
        (q, r.is_zero())
    };
    match t.err {
        None if exact => (q.clone(), q),
        None => (q.clone(), q + 1),
        Some(err) => {
            assert!(err + scale < 0, "reference error 1e{err} at 1e-{scale}");
            (&q - 1, q + 2)
        }
    }
}

/// floor(t 10^scale), which must be determined by t's error.
fn floor_at(t: &Approx, scale: i64) -> BigInt {
    let (lo, hi) = enclose(t, scale + 40);
    let unit = pow10(40);
    let floor = lo.div_floor(&unit);
    assert_eq!(floor, hi.div_floor(&unit), "floor of {t:?} undetermined");
    floor
}

fn ceil_div(a: &BigInt, b: &BigInt) -> BigInt {
    a.div_ceil(b)
}

// ------------------------------------------------------------- constants

const IMPL: &str =
    include_str!("../../../src/lib/implementation/LibDecimalFloatImplementation.sol");

/// The decimal literal following `marker` in `text`.
fn literal_after(text: &str, marker: &str) -> BigInt {
    let at = text
        .find(marker)
        .unwrap_or_else(|| panic!("`{marker}` not in the source"));
    let digits: String = text[at + marker.len()..]
        .chars()
        .take_while(char::is_ascii_digit)
        .collect();
    digits.parse().unwrap()
}

/// exp10Fixed's series coefficients, highest power first: the
/// `EXP10_HORNER_j` constants, which the body takes in Horner order from
/// the ninth power down, then ln 10 and one.
fn series_coefficients() -> Vec<BigInt> {
    let start = IMPL.find("function exp10Fixed(").unwrap();
    let body = &IMPL[start..];
    let body = &body[..1 + body[1..].find("    function ").unwrap()];
    let mut steps = vec!["let series := EXP10_HORNER_9".to_string()];
    steps.extend(
        (2..=8)
            .rev()
            .map(|j| format!("series := add(EXP10_HORNER_{j}, series)")),
    );
    steps.push("series := add(POW_FIXED_LN10, series)".to_string());
    steps.push("series := add(POW_FIXED_ONE, series)".to_string());
    let mut from = 0;
    for step in &steps {
        let at = body[from..]
            .find(step.as_str())
            .unwrap_or_else(|| panic!("`{step}` not in order"));
        assert_eq!(body.matches(step.as_str()).count(), 1, "`{step}`");
        from += at + step.len();
    }
    (2..=9)
        .rev()
        .map(|j| literal_after(IMPL, &format!("uint256 constant EXP10_HORNER_{j} = ")))
        .collect()
}

/// ln 10 at 1e-LN10_SCALE: lo <= ln 10 10^LN10_SCALE < lo + 2.
const LN10_SCALE: u64 = 200;

/// ln 10 = 6 atanh(1/3) + 2 atanh(1/9), each series term floored at 20 guard
/// digits past the scale. Every floor is down: each power is under 1.125
/// below its exact value, each term so under 2.2, over about 220 terms,
/// with a tail under 2, so the sum is under 5000 guard units below ln 10,
/// well under the unit the guard digits are dropped to.
fn ln10_floor() -> BigInt {
    let one = pow10(LN10_SCALE + 20);
    let atanh_inv = |n: u64| {
        let n = BigInt::from(n);
        let n2 = &n * &n;
        let mut power = &one / &n;
        let mut sum = BigInt::zero();
        let mut k = 1u64;
        while !power.is_zero() {
            sum += &power / k;
            power /= &n2;
            k += 2;
        }
        sum
    };
    (atanh_inv(3) * 6 + atanh_inv(9) * 2) / pow10(20)
}

/// floor((ln 10)^j / j! 1e50), determined by the interval on ln 10.
fn ln10_power_floor(j: u32) -> BigInt {
    let lo = ln10_floor();
    let hi = &lo + 2;
    let factorial: BigInt = (1..=j).map(BigInt::from).product();
    let denominator = factorial * pow10(LN10_SCALE * j as u64 - 50);
    let floor = num_traits::pow(lo, j as usize) / &denominator;
    assert_eq!(
        floor,
        num_traits::pow(hi, j as usize) / &denominator,
        "(ln 10)^{j} / {j}! undetermined"
    );
    floor
}

#[test]
fn series_coefficients_are_exact_floors() {
    let coefficients = series_coefficients();
    assert_eq!(coefficients.len(), 8, "c9 down to c2");
    for (i, c) in coefficients.iter().enumerate() {
        let j = 9 - i as u32;
        assert_eq!(*c, ln10_power_floor(j), "coefficient of x^{j}");
    }
    assert_eq!(
        literal_after(IMPL, "uint256 constant POW_FIXED_LN10 = "),
        ln10_power_floor(1)
    );
    assert!(IMPL.contains("uint256 constant POW_FIXED_ONE = 1e50;"));
}

/// POW_FIXED_LN10 is 0.2976 below ln 10 1e50, to four places, which is
/// what log10Ratio's 1.2925e-51 relative above rests on.
#[test]
fn ln10_constant_shortfall() {
    let constant = literal_after(IMPL, "uint256 constant POW_FIXED_LN10 = ");
    let lo = ln10_floor();
    let shift = pow10(LN10_SCALE - 50);
    let below_lo = &lo - &constant * &shift;
    let below_hi = &below_lo + 2;
    assert!(below_lo >= BigInt::from(29_755) * pow10(LN10_SCALE - 55));
    assert!(below_hi < BigInt::from(29_765) * pow10(LN10_SCALE - 55));
}

/// At x = 2^-i only step i is taken, so the result is its constant:
/// 10^(2^-i) 1e50 floored.
#[test]
fn step_constants_are_exact_floors() {
    for i in 1..=16u32 {
        let x = pow10(50) >> i;
        let t = precise::pow10_true(&Dec::new(x.clone(), -50));
        assert_eq!(exp10_fixed(&x), floor_at(&t, 50), "10^(2^-{i})");
    }
}

// ----------------------------------------------------------- enumeration

/// Units of 1e-80, 1e-30 of a unit of the result.
const FINE: i64 = 80;

fn fine_units(e52: u64) -> BigInt {
    BigInt::from(e52) * pow10(28)
}

/// What every cell of exp10Fixed reaches, in units of 1e-80. For x in the
/// cell k 2^-16 + r, r in [0, 2^-16), P is the steps' product, which is the
/// result at r = 0, and E = 10^(k 2^-16) 1e50 - P. The result is under
/// E 10^r + 1.07902 P / 1e50 + 1 below 10^x 1e50, and pow10 adds its
/// truncation of x to 1e-50, under ln 10 10^x units.
struct Cell {
    /// 10^(k 2^-16) 1e80, at least.
    power: BigInt,
    exp10: BigInt,
    pow10: BigInt,
}

fn cell(k: u32, up: &BigInt) -> Cell {
    let product = exp10_fixed(&(step() * k));
    let t = if k == 0 {
        Approx::exact(Dec::new(1, 0))
    } else {
        precise::pow10_true(&Dec::new(BigInt::from(k) * STEP, -16))
    };
    let (lo, hi) = enclose(&t, FINE);
    let product_fine = &product * pow10(30);
    assert!(product_fine <= lo, "step product above 10^x at k = {k}");
    let shortfall = &hi - &product_fine;
    let exp10 = ceil_div(&(shortfall * up), &pow10(30))
        + ceil_div(&(&product * SERIES_LOSS_E5), &pow10(25))
        + pow10(30);
    // ln 10 is under 2.302585093, and 10^x under 10^((k + 1) 2^-16).
    let truncation = ceil_div(&(&hi * up * 2_302_585_093u64), &pow10(30 + 50 + 9));
    Cell {
        pow10: &exp10 + truncation,
        power: lo,
        exp10,
    }
}

/// 10^(2^-16) 1e30, at least.
fn cell_ratio() -> BigInt {
    let t = precise::pow10_true(&Dec::new(STEP, -16));
    enclose(&t, 30).1
}

/// Each bound holds over every k and is at least 99.9% attained.
#[test]
fn exp10_fixed_every_cell() {
    let up = cell_ratio();
    let (mut exp10, mut pow10_raw) = (BigInt::zero(), BigInt::zero());
    // The largest bound relative to 10^x, as a fraction.
    let (mut rel_num, mut rel_den) = (BigInt::zero(), BigInt::from(1));
    for k in 0..1u32 << 16 {
        let c = cell(k, &up);
        if &c.exp10 * &rel_den > &rel_num * &c.power {
            (rel_num, rel_den) = (c.exp10.clone(), c.power.clone());
        }
        exp10 = exp10.max(c.exp10);
        pow10_raw = pow10_raw.max(c.pow10);
    }
    let check = |name: &str, reached: &BigInt, bound: &BigInt| {
        assert!(reached <= bound, "{name}: {reached} past {bound}");
        assert!(
            reached * 1000 >= bound * 999,
            "{name}: {reached} under 99.9% of {bound}"
        );
    };
    check("exp10Fixed", &exp10, &fine_units(EXP10_FIXED_E52));
    check("pow10 raw", &pow10_raw, &fine_units(POW10_RAW_E52));
    // rel_num / rel_den against 1.408e-49 of a power at 1e80 units.
    check(
        "exp10Fixed relative",
        &(&rel_num * pow10(52)),
        &(&rel_den * EXP10_FIXED_RELATIVE_E52),
    );
}

// ------------------------------------------------------------ worst inputs

/// The largest exp10Fixed shortfall found, in the cell k = 2^16 - 1.
const EXP10_WORST: &str = "99999997009289934356557650968483398591830890493987";

/// 10^x 1e80 less exp10Fixed(m) 1e30, both ends.
fn shortfall(m: &BigInt, x: &Dec) -> (BigInt, BigInt) {
    let result = exp10_fixed(m) * pow10(30);
    let (lo, hi) = enclose(&precise::pow10_true(x), FINE);
    (lo - &result, hi - result)
}

#[test]
fn exp10_fixed_worst_input() {
    let m: BigInt = EXP10_WORST.parse().unwrap();
    let (lo, hi) = shortfall(&m, &Dec::new(m.clone(), -50));
    let bound = fine_units(EXP10_FIXED_E52);
    assert!(hi <= bound, "{hi} past {bound}");
    assert!(lo * 1000 >= bound * 999, "under 99.9% of the bound");
}

/// pow10 truncates x to the same m: its worst is just below m + 1e-50.
#[test]
fn pow10_raw_worst_input() {
    let m: BigInt = EXP10_WORST.parse().unwrap();
    let x = Dec::new(&m * pow10(16) + pow10(16) - 1, -66);
    let (lo, hi) = shortfall(&m, &x);
    let bound = fine_units(POW10_RAW_E52);
    assert!(hi <= bound, "{hi} past {bound}");
    assert!(lo * 1000 >= bound * 999, "under 99.9% of the bound");
}

// ------------------------------------------------------------- log10Ratio

/// Units of 1e-240: fine against the least nonzero log, log10(1 + 1e-76),
/// and coarse against the reference's error.
const RATIO_SCALE: i64 = 240;

/// log10Ratio(a, b) against |log10(a / b)|, in units of 1e-240: |C 10^e|,
/// 10^e, and how far the result is below and above the true log at most.
struct Ratio {
    actual: BigInt,
    unit: BigInt,
    below: BigInt,
    above: BigInt,
}

fn ratio_error(a: &BigInt, b: &BigInt, relative: bool) -> Result<Ratio, TestCaseError> {
    let (c, e) = log10_ratio(a, b, relative)?;
    let negative = a < b;
    prop_assert!(
        if negative {
            !c.is_positive()
        } else {
            !c.is_negative()
        },
        "sign of {c}"
    );
    let log = |x: &BigInt| enclose(&precise::log10(&Dec::new(x.clone(), 0)), RATIO_SCALE);
    let (true_lo, true_hi) = if a == b {
        (BigInt::zero(), BigInt::zero())
    } else {
        let ((a_lo, a_hi), (b_lo, b_hi)) = (log(a), log(b));
        if negative {
            (b_lo - a_hi, b_hi - a_lo)
        } else {
            (a_lo - b_hi, a_hi - b_lo)
        }
    };
    let unit = pow10((e + RATIO_SCALE) as u64);
    let actual = c.abs() * &unit;
    Ok(Ratio {
        below: true_hi - &actual,
        above: &actual - true_lo,
        actual,
        unit,
    })
}

/// log10Ratio(a, b) within its bounds, the narrower ones for z at most
/// 5.1e-4.
fn check_ratio(a: &BigInt, b: &BigInt, relative: bool) -> Result<Ratio, TestCaseError> {
    let r = ratio_error(a, b, relative)?;
    let difference = if a < b { b - a } else { a - b };
    let (relative_e53, fixed_e54) = if difference * 100_000u32 <= (a + b) * 51u32 {
        (LOG10_RATIO_RELATIVE_E53, LOG10_RATIO_FIXED_E54)
    } else {
        (LOG10_RATIO_WIDE_RELATIVE_E53, LOG10_RATIO_WIDE_FIXED_E54)
    };
    let limit = if relative {
        &r.actual * relative_e53 / pow10(53) + &r.unit
    } else {
        BigInt::from(fixed_e54) * pow10((RATIO_SCALE - 54) as u64)
    };
    prop_assert!(
        r.below <= limit,
        "{a} {b} {relative}: {} below, past {limit}",
        r.below
    );
    // 1.3e-51 of the true log, which is at least actual - above.
    prop_assert!(
        &r.above * pow10(52) <= (&r.actual - &r.above) * LOG10_RATIO_ABOVE_E52,
        "{a} {b} {relative}: {} above",
        r.above
    );
    Ok(r)
}

/// The largest relative shortfall found, 7.556e-50 of C, in a + b = 4.7e50.
#[test]
fn log10_ratio_worst_input() {
    let a: BigInt = "233589395330683330993119953099800888842671881715980"
        .parse()
        .unwrap();
    let b: BigInt = "233376197779936277454916859050523443841026703458223"
        .parse()
        .unwrap();
    let r = check_ratio(&a, &b, true).unwrap();
    // The true log is at least |C| less `above`: at least 94% of C 8.03e-50.
    assert!(-r.above * pow10(53) * 100 >= r.actual * LOG10_RATIO_RELATIVE_E53 * 94);
}

/// b with a uniformly random digit count up to 76, then a = b ± d for z =
/// d / (a + b) at most 5.1e-4, or when `wide` at most 7.4956e-4, inside
/// `LOG10_RATIO_Z_MAX`, weighted to the ends of d.
fn ratio_inputs() -> BoxedStrategy<(BigInt, BigInt)> {
    (
        1u64..=76,
        any::<[u8; 32]>(),
        any::<[u8; 32]>(),
        0u8..4,
        any::<bool>(),
        any::<bool>(),
    )
        .prop_map(|(n, rb, rd, shape, wide, below)| {
            let lo = pow10(n - 1);
            let hi = if n == 76 {
                BigInt::from(998) * pow10(73)
            } else {
                pow10(n)
            };
            let b = &lo + BigInt::from_bytes_be(Sign::Plus, &rb) % (hi - &lo);
            let max =
                &b * match (wide, below) {
                    (false, true) => 1019,
                    (false, false) => 1020,
                    (true, true) => 1498,
                    (true, false) => 1500,
                } / 1_000_000;
            let r = BigInt::from_bytes_be(Sign::Plus, &rd);
            let d = match shape {
                0 => r % (&max + 1),
                1 => &max - r % (&max / 1000 + 1),
                2 => r % BigInt::from(1000).min(&max + 1),
                _ => r % (&max / 1000 + 1),
            };
            let a = if below { &b - &d } else { &b + &d };
            (a, b)
        })
        .boxed()
}

proptest! {
    #![proptest_config(config())]

    #[test]
    fn log10_ratio_bounds((a, b) in ratio_inputs()) {
        check_ratio(&a, &b, false)?;
        if &a + &b >= pow10(50) {
            check_ratio(&a, &b, true)?;
        }
    }
}

// ------------------------------------------- log10Ratio in-place multiplies

/// What log10Ratio's z^4 and z^6 multiplies take as zSquared: floor(z^2 /
/// 1e50), at most this for z at most `LOG10_RATIO_Z_MAX`, and every integer
/// up to it.
fn z_squared_max() -> BigInt {
    let z = literal_after(IMPL, "uint256 constant LOG10_RATIO_Z_MAX = ");
    &z * &z / pow10(50)
}

/// The z^6 product: floor(x^2 / 1e50), the z^4 term, times x.
fn sixth(x: &BigInt) -> BigInt {
    x * x / pow10(50) * x
}

/// `lt(mm, prod0)` over words of `w` bits for the product p: mm is p mod
/// (2^w - 1) and prod0 is p mod 2^w.
fn wraps(p: &BigInt, w: u32) -> bool {
    let word = BigInt::from(1) << w;
    p.mod_floor(&(&word - 1)) < p.mod_floor(&word)
}

/// A product of x, non-decreasing in x.
type Product = dyn Fn(&BigInt) -> BigInt;

/// The largest x in [0, max] with p(x) below `bound`, for p non-decreasing
/// with p(0) below it.
fn largest_below(p: &Product, bound: &BigInt, max: &BigInt) -> BigInt {
    if p(max) < *bound {
        return max.clone();
    }
    let (mut lo, mut hi) = (BigInt::zero(), max.clone());
    while &hi - &lo > BigInt::from(1) {
        let mid = (&lo + &hi) >> 1;
        if p(&mid) < *bound {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    lo
}

/// Every k for which some x in [0, max] has p(x) in the high word k - 1 and
/// `wraps`, for p non-decreasing. mm = hi + lo mod (2^w - 1), so `wraps` is
/// hi + lo of at least 2^w - 1: lo of at least 2^w - k. Within one high word
/// lo grows with x, so if any x there wraps the largest does, and that is
/// the largest x with p(x) below k 2^w. That x is in an earlier word when p
/// steps over word k - 1, so the word it wraps in is the one returned.
fn wrapping_words(p: &Product, max: &BigInt, w: u32) -> Vec<BigInt> {
    let word = BigInt::from(1) << w;
    let top = p(max) >> w;
    let mut found = vec![];
    let mut k = BigInt::from(1);
    while k <= &top + 1 {
        let product = p(&largest_below(p, &(&k * &word), max));
        if wraps(&product, w) {
            found.push((product >> w) + 1);
        }
        k += 1;
    }
    found.dedup();
    found
}

/// `wrapping_words` is every high word some x wraps in, against every x,
/// for z^4 and z^6 shaped products over small words where some do.
#[test]
fn wrapping_words_finds_every_wrap() {
    let shapes: [(&Product, u32, u64); 4] = [
        (&|x| x * x, 16, 1 << 14),
        (&|x| x * x, 20, 1 << 15),
        (&|x| x * x / 256 * x, 16, 3_000),
        (&|x| x * x / 1_000 * x, 20, 20_000),
    ];
    for (p, w, max) in shapes {
        let mut every: Vec<BigInt> = (0..=max)
            .map(BigInt::from)
            .map(|x| p(&x))
            .filter(|q| wraps(q, w))
            .map(|q| (q >> w) + 1)
            .collect();
        every.dedup();
        assert!(!every.is_empty(), "no wrap at w = {w}");
        assert_eq!(wrapping_words(p, &BigInt::from(max), w), every, "w = {w}");
    }
}

/// log10Ratio's z^6 multiply never wraps, for every zSquared, so its high
/// word takes no `lt(mm, prod0)` borrow.
#[test]
fn log10_ratio_z6_never_wraps() {
    let max = z_squared_max();
    assert_eq!(sixth(&max) >> 256u32, BigInt::from(15_357));
    assert_eq!(wrapping_words(&sixth, &max, 256), Vec::<BigInt>::new());
}
