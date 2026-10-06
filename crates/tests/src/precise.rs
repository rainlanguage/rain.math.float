//! The true log10, 10^x and a^b, from astro-float: arbitrary precision with
//! every operation and function correctly rounded, so each value carries a
//! proven bound on its own error rather than a tolerance.
//!
//! A value is `m × 10^e` (an exact `Dec`) with `|true - value| <= 10^err`.
//! Every function asserts its `err` is at least 200 digits below the value,
//! which is far below any bound the library documents.

use crate::reference::{Dec, digits, pow10};
use astro_float::{BigFloat, Consts, Radix, RoundingMode, Sign as AfSign, WORD_BIT_SIZE};
use num_bigint::BigInt;
use num_traits::{Signed, Zero};
use std::cell::RefCell;

/// Working precision in bits. Each correctly rounded step is within
/// 2^-1088 < 10^-327 relative.
const P: usize = 1088;
const RM: RoundingMode = RoundingMode::ToEven;
/// 2^-P is below 10^-REL, for a bound on one rounding.
const REL: i64 = 327;
/// Significant digits kept when converting a binary value to decimal.
const KEEP: u64 = 260;

/// Past this |log10| of a result, it is past every Float on its side.
pub const RANGE: i64 = 3_000_000_000;

/// A true value within `10^err`, or exactly when `err` is `None`.
#[derive(Debug, Clone)]
pub struct Approx {
    pub value: Dec,
    pub err: Option<i64>,
}

impl Approx {
    pub fn exact(value: Dec) -> Self {
        Self { value, err: None }
    }

    /// The error bound as a value, zero when exact.
    pub fn err_dec(&self) -> Dec {
        match self.err {
            None => Dec::zero(),
            Some(e) => Dec::new(1, e),
        }
    }

    fn checked(self) -> Self {
        if let Some(err) = self.err {
            let order = self.value.e + digits(&self.value.c) as i64;
            assert!(
                err <= order - 200,
                "reference error 1e{err} is not 200 digits below {:?}",
                self.value
            );
        }
        self
    }
}

thread_local! {
    static CONSTS: RefCell<Consts> = RefCell::new(Consts::new().expect("astro-float constants"));
}

fn with_cc<T>(f: impl FnOnce(&mut Consts) -> T) -> T {
    CONSTS.with(|cc| f(&mut cc.borrow_mut()))
}

fn ok(x: BigFloat) -> BigFloat {
    assert!(!x.is_nan() && !x.is_inf(), "astro-float: {x:?}");
    x
}

/// A decimal into binary, correctly rounded (exact for an integer of at most
/// P bits).
pub fn to_bf(d: &Dec) -> BigFloat {
    with_cc(|cc| {
        ok(BigFloat::parse(
            &format!("{}e{}", d.c, d.e),
            Radix::Dec,
            P,
            RM,
            cc,
        ))
    })
}

fn from_i64(i: i64) -> BigFloat {
    BigFloat::from_i64(i, P)
}

/// A binary value exactly, as `M × 2^(exponent - mantissa bits)`.
pub fn to_dec_exact(x: &BigFloat) -> Dec {
    if x.is_zero() {
        return Dec::zero();
    }
    let (words, _, sign, exponent, _) = x.as_raw_parts().expect("a finite value");
    let mut m = BigInt::zero();
    for w in words.iter().rev() {
        m = (m << WORD_BIT_SIZE) + BigInt::from(*w);
    }
    if sign == AfSign::Neg {
        m = -m;
    }
    let shift = exponent as i64 - (words.len() * WORD_BIT_SIZE) as i64;
    if shift >= 0 {
        return Dec::new(m << shift as usize, 0);
    }
    // m / 2^s = m 5^s / 10^s, exactly.
    let s = (-shift) as u64;
    Dec::new(
        m * num_traits::pow(BigInt::from(5), s as usize),
        -(s as i64),
    )
    .normalized()
}

/// A decimal truncated towards zero to KEEP significant digits, and the
/// exponent of a bound on what that drops.
fn shorten(d: &Dec) -> (Dec, i64) {
    let n = digits(&d.c);
    if n <= KEEP {
        return (d.clone(), i64::MIN);
    }
    let shed = n - KEEP;
    let c = &d.c / pow10(shed);
    let e = d.e + shed as i64;
    (Dec::new(c, e), e)
}

/// 10^err covering both `a` and `b`: 10^max + 1.
fn add_err(a: i64, b: i64) -> i64 {
    a.max(b) + 1
}

/// The exponent of `x`'s leading digit, `floor(log10 |x|)`.
pub fn order(x: &Dec) -> i64 {
    x.e + digits(&x.c) as i64 - 1
}

/// log10(a) for a > 0, as binary, with the exponent of a bound on its error.
fn log10_bf(a: &Dec) -> (BigFloat, i64) {
    assert!(a.c.is_positive());
    // log10(c) for c of at most 68 digits is within 70 of zero, and rounds
    // once; adding e rounds once more on a sum under |e| + 70.
    let c = to_bf(&Dec::new(a.c.clone(), 0));
    let lc = with_cc(|cc| ok(c.log10(P, RM, cc)));
    let l = ok(lc.add(&from_i64(a.e), P, RM));
    let scale = (a.e.unsigned_abs() + 140) as u128;
    let err = scale.to_string().len() as i64 - REL;
    (l, err)
}

/// log10(a) for a > 0. log10(c 10^e) is exactly e + log10(c), exact when c
/// is a power of ten.
pub fn log10(a: &Dec) -> Approx {
    let n = a.normalized();
    if n.c == BigInt::from(1) {
        return Approx::exact(Dec::new(n.e, 0));
    }
    let (l, err) = log10_bf(a);
    let (value, cut) = shorten(&to_dec_exact(&l));
    Approx {
        value,
        err: Some(add_err(err, cut)),
    }
    .checked()
}

/// `floor(x)` and `x - floor(x)`, exactly.
fn split(x: &Dec) -> (i64, Dec) {
    if x.e >= 0 {
        let k = &x.c * pow10(x.e as u64);
        return (i64::try_from(&k).expect("|x| <= RANGE"), Dec::zero());
    }
    let unit = pow10((-x.e) as u64);
    let mut k = &x.c / &unit;
    let mut f = &x.c % &unit;
    if f.is_negative() {
        k -= 1;
        f += &unit;
    }
    (
        i64::try_from(&k).expect("|x| <= RANGE"),
        Dec::new(f, x.e).normalized(),
    )
}

/// 10^f for f in [0, 1) given exactly, as a decimal in [1, 10) at
/// 10^shift, with the exponent of its error bound.
fn pow10_fraction(f: &Dec, shift: i64) -> Approx {
    if f.is_zero() {
        return Approx::exact(Dec::new(1, shift));
    }
    // 10^f - 1 < 2.31 f 1.01 < 1e-328 for f this small.
    if order(f) < -330 {
        return Approx {
            value: Dec::new(1, shift),
            err: Some(shift - 328),
        }
        .checked();
    }
    // f parses within 2^-P of f < 1, which moves 10^f < 10 by under
    // 10 · 2.31 · 2^-P; the power rounds once more, under 10 · 2^-P. Together
    // under 10^(3 - REL).
    let f = to_bf(f);
    let m = with_cc(|cc| ok(from_i64(10).pow(&f, P, RM, cc)));
    let (value, cut) = shorten(&to_dec_exact(&m));
    Approx {
        value: Dec::new(value.c, value.e + shift),
        err: Some(add_err(shift + 3 - REL, cut.saturating_add(shift))),
    }
    .checked()
}

/// 10^x for |x| <= RANGE, x nonzero. Exact for an integer x.
pub fn pow10_true(x: &Dec) -> Approx {
    // |10^x - 1| < 2.31 |x| 1.01 < 1e-328, and an exact split of x would
    // need |x.e| digits.
    if order(x) < -330 {
        return Approx {
            value: Dec::new(1, 0),
            err: Some(-328),
        }
        .checked();
    }
    let (k, f) = split(x);
    pow10_fraction(&f, k)
}

/// a^b for a > 0, a != 1 and b != 0, or `Err(true)` when it is past every
/// Float above, `Err(false)` below.
pub fn pow_true(a: &Dec, b: &Dec) -> Result<Approx, bool> {
    let above_one = a.cmp_value(&Dec::new(1, 0)).is_gt();
    let rising = above_one == b.c.is_positive();
    let b_order = order(b);
    // |log10 a| is at least 4.3e-68 for a != 1 with an int224 coefficient,
    // so |b| above 1e90 puts |b log10 a| past RANGE.
    if b_order >= 90 {
        return Err(rising);
    }
    // |b log10 a| is under 1e-400 3e9, so a^b is 1 within 1e-389.
    if b_order < -400 {
        return Ok(Approx {
            value: Dec::new(1, 0),
            err: Some(-389),
        }
        .checked());
    }
    let (l, l_err) = log10_bf(a);
    let y = ok(to_bf(b).mul(&l, P, RM));
    let y_dec = to_dec_exact(&y);
    if y_dec.abs().cmp_value(&Dec::new(RANGE, 0)).is_gt() {
        return Err(rising);
    }
    // y's error: |b| times log10's, plus b's parse and the product's
    // rounding, each under 2^-P of |y| <= 3e9.
    let y_err = add_err(b_order + 1 + l_err, 10 - REL + 1);
    let (k, f) = split(&y_dec);
    // 10^y moves by under 2.31 · 1.01 y_err relative, below 10^(k + 1).
    let t = pow10_fraction(&f, k);
    let err = add_err(t.err.unwrap_or(i64::MIN), k + 2 + y_err);
    Ok(Approx {
        value: t.value,
        err: Some(err),
    }
    .checked())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binary_round_trips_exactly() {
        for (s, want) in [
            ("1", Dec::new(1, 0)),
            ("3", Dec::new(3, 0)),
            ("0.5", Dec::new(5, -1)),
            ("-2.25", Dec::new(-225, -2)),
            ("1024", Dec::new(1024, 0)),
        ] {
            let x = with_cc(|cc| BigFloat::parse(s, Radix::Dec, P, RM, cc));
            let d = to_dec_exact(&x);
            assert!(d.eq_value(&want), "{s}: {d:?}");
        }
        let c: BigInt = "13479973333575319897333507543509815336818572211270286240551805124607"
            .parse()
            .unwrap();
        assert!(to_dec_exact(&to_bf(&Dec::new(c.clone(), 0))).eq_value(&Dec::new(c, 0)));
    }

    /// Spot values from `bc -l` at scale 70, checked to 60 digits.
    #[test]
    fn known_values() {
        let near = |a: &Approx, want: &str| {
            let w = crate::reference::literal_value(want);
            let d = a.value.add_exact(&w.neg()).unwrap().abs();
            assert!(
                d.cmp_value(&Dec::new(1, order(&w) - 59)).is_lt(),
                "{a:?} is not {want}"
            );
        };
        near(
            &log10(&Dec::new(2, 0)),
            "0.3010299956639811952137388947244930267681898814621085413104274611271081",
        );
        near(
            &pow10_true(&Dec::new(5, -1)),
            "3.1622776601683793319988935444327185337195551393252168268575048527925944",
        );
        near(
            &pow_true(&Dec::new(2, 0), &Dec::new(5, -1)).unwrap(),
            "1.4142135623730950488016887242096980785696718753769480731766797379907324",
        );
        near(
            &pow_true(&Dec::new(10, 0), &Dec::new(-25, -1)).unwrap(),
            "0.0031622776601683793319988935444327185337195551393252168268575048527925",
        );
        assert!(log10(&Dec::new(1000, -5)).value.eq_value(&Dec::new(-2, 0)));
        assert!(log10(&Dec::new(1000, -5)).err.is_none());
        assert!(
            pow10_true(&Dec::new(-70, -1))
                .value
                .eq_value(&Dec::new(1, -7))
        );
        assert!(matches!(
            pow_true(&Dec::new(2, 0), &Dec::new(1, 100)),
            Err(true)
        ));
        assert!(matches!(
            pow_true(&Dec::new(2, 0), &Dec::new(-1, 100)),
            Err(false)
        ));
        assert!(matches!(
            pow_true(&Dec::new(5, -1), &Dec::new(1, 100)),
            Err(false)
        ));
    }
}
