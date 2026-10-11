//! exp10Fixed and log10Ratio against astro-float.

use crate::evm::{self, TestDecimalFloatHarness as H};
use crate::precise;
use crate::reference::{Dec, pow10};
use alloy::primitives::U256;
use num_bigint::BigInt;
use num_traits::ToPrimitive;

fn exp10_fixed(x: &BigInt) -> BigInt {
    let r = evm::harness(H::exp10FixedCall {
        x: U256::from_str_radix(&x.to_string(), 10).unwrap(),
    })
    .unwrap();
    r.to_string().parse().unwrap()
}

/// `d` times 10^`scale`, floored.
fn scaled(d: &Dec, scale: i64) -> BigInt {
    let e = d.e + scale;
    if e >= 0 {
        &d.c * pow10(e as u64)
    } else {
        num_integer::Integer::div_floor(&d.c, &pow10((-e) as u64))
    }
}

#[test]
#[ignore]
fn explore_exp10_grid() {
    let step = BigInt::from(1_525_878_906_25u64) * pow10(34);
    let mut worst_rel = (0f64, 0u32);
    let mut worst_abs = (0f64, 0u32);
    for k in 0u32..65536 {
        let x = &step * k;
        let r = exp10_fixed(&x);
        let t = precise::pow10_true(&Dec::new(BigInt::from(k) * 152_587_890_625u64, -16));
        // error in micro units
        let e = scaled(&t.value, 56) - &r * pow10(6);
        let e = e.to_f64().unwrap() / 1e6;
        let rel = e / (r.to_f64().unwrap() / 1e50);
        if rel > worst_rel.0 {
            worst_rel = (rel, k);
        }
        if e > worst_abs.0 {
            worst_abs = (e, k);
        }
    }
    println!("worst rel {worst_rel:?} worst abs {worst_abs:?}");
}

fn ef(d: &Dec) -> f64 {
    // value as f64 via 60 significant digits
    let s = scaled(d, 0 - d.e.min(0).max(-1000)); // integer part trick not needed
    let _ = s;
    let digits = d.c.to_string().len() as i64;
    let keep = 30i64;
    let cut = (digits - keep).max(0);
    let c = &d.c / pow10(cut as u64);
    c.to_f64().unwrap() * 10f64.powi((d.e + cut) as i32)
}

#[test]
#[ignore]
fn explore_exp10_per_cell() {
    let step = BigInt::from(1_525_878_906_25u64) * pow10(34);
    let e0 = 1.07902f64;
    let up = 10f64.powf(1.0 / 65536.0);
    let mut best_abs = (0f64, 0u32);
    let mut best_rel = (0f64, 0u32);
    let mut best_pow = (0f64, 0u32);
    for k in 0u32..65536 {
        let r = exp10_fixed(&(&step * k));
        let t = precise::pow10_true(&Dec::new(BigInt::from(k) * 152_587_890_625u64, -16));
        let tv = ef(&t.value) * 1e50;
        let e = (scaled(&t.value, 56) - &r * pow10(6)).to_f64().unwrap() / 1e6;
        let rf = r.to_f64().unwrap();
        let abs = e * up + rf / 1e50 * e0 + 1.0;
        let rel = e / tv * 1e50 + e0 * rf / tv + 1e50 / tv;
        let pow = abs + 2.302585093 * tv / 1e50 * up * (1.0 + 1e-12);
        if abs > best_abs.0 { best_abs = (abs, k); }
        if rel > best_rel.0 { best_rel = (rel, k); }
        if pow > best_pow.0 { best_pow = (pow, k); }
    }
    println!("abs {best_abs:?} rel {best_rel:?} pow {best_pow:?}");
}

fn log10_ratio(a: &BigInt, b: &BigInt, relative: bool) -> (BigInt, i64) {
    let r: H::log10RatioReturn = evm::harness(H::log10RatioCall {
        a: U256::from_str_radix(&a.to_string(), 10).unwrap(),
        b: U256::from_str_radix(&b.to_string(), 10).unwrap(),
        relative,
    })
    .unwrap();
    (r._0.to_string().parse().unwrap(), r._1.to_string().parse::<i64>().unwrap())
}

/// 2 atanh(d / s) / ln 10 at 10^-SC, s > d >= 0
const SC: u64 = 140;
fn ln10_scaled() -> BigInt {
    // log10(e) = 1/ln10; use precise log10 of e? use astro: ln10 = 1/log10(e).
    // log10(2) and ln2 avoided: compute ln10 by atanh series: ln10 = 2 atanh(9/11)
    // too slow; use ln(10) = 3 ln2 + ln(1.25); ln2 = 2 atanh(1/3), ln1.25 = 2 atanh(1/9).
    let one = pow10(SC + 20);
    let at = |n: u64| {
        let n = BigInt::from(n);
        let n2 = &n * &n;
        let mut p = &one / &n;
        let mut s = BigInt::from(0);
        let mut k = 1u64;
        while p > BigInt::from(0) {
            s += &p / k;
            p /= &n2;
            k += 2;
        }
        s
    };
    (at(3) * 6 + at(9) * 2) / pow10(20)
}

fn atanh_scaled(d: &BigInt, s: &BigInt) -> BigInt {
    let one = pow10(SC + 20);
    let mut p = &one * d / s;
    let z2n = d * d;
    let z2d = s * s;
    let mut sum = BigInt::from(0);
    let mut k = 1u64;
    while p > BigInt::from(0) {
        sum += &p / k;
        p = p * &z2n / &z2d;
        k += 2;
    }
    sum / pow10(20)
}

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn big(&mut self, digits: u32) -> BigInt {
        let mut v = BigInt::from(0);
        for _ in 0..(digits / 18 + 1) {
            v = v * BigInt::from(1_000_000_000_000_000_000u64) + BigInt::from(self.next() % 1_000_000_000_000_000_000u64);
        }
        v % pow10(digits as u64)
    }
}

#[test]
#[ignore]
fn explore_log10_ratio() {
    let ln10 = ln10_scaled();
    let mut rng = Rng(0x9e3779b97f4a7c15);
    let iters: usize = std::env::var("ITERS").ok().and_then(|s| s.parse().ok()).unwrap_or(10000);
    let lo: f64 = std::env::var("ZLO").ok().and_then(|s| s.parse().ok()).unwrap_or(2.7e-4);
    let mut best = vec![(0f64, String::new()); 8];
    for _ in 0..iters {
        let b = pow10(75) + rng.big(76) % (pow10(75) * 89 / 10);
        // d in [lo, 5.1e-4] * 2b approx
        let zf = lo + (5.09e-4 - lo) * ((rng.next() % 1_000_000) as f64 / 1e6);
        let d = &b * BigInt::from((zf * 2e12) as u64) / pow10(12) + rng.big(30);
        let below = rng.next() & 1 == 1;
        let a = if below { &b - &d } else { &b + &d };
        let sum = &a + &b;
        let (c, e) = log10_ratio(&a, &b, true);
        let c: BigInt = num_traits::Signed::abs(&c);
        // true at 10^-SC
        let t: BigInt = atanh_scaled(&d, &sum) * 2 * pow10(SC) / &ln10;
        // error in units of C's exponent, times 1e6
        let shift = (SC as i64 + e) as u64;
        let err: BigInt = (&t * pow10(6)) / pow10(shift) - &c * pow10(6);
        let rel = err.to_f64().unwrap() / 1e6 / c.to_f64().unwrap() * 1e50;
        // n terms
        let zz = (d.to_f64().unwrap() / sum.to_f64().unwrap()).powi(2);
        let mut n = 0usize;
        let mut p = zz;
        while p * 1e50 >= 1.0 { n += 1; p *= zz; }
        if rel > best[n].0 {
            best[n] = (rel, format!("a={a} b={b}"));
        }
    }
    for (n, b) in best.iter().enumerate() {
        println!("n={n} rel={} {}", b.0, b.1);
    }
}

#[test]
#[ignore]
fn debug_log10_ratio_case() {
    let a: BigInt = "8029374191804342429571675682666447141722672535929198325393759232729157392194".parse().unwrap();
    let b: BigInt = "8035347757619758118482858045226913029822362853134437596291346841201887492154".parse().unwrap();
    let (c, e) = log10_ratio(&a, &b, true);
    println!("C={c} e={e}");
    let d: BigInt = &b - &a;
    let sum = &a + &b;
    let one = pow10(50);
    let z = &d * &one / &sum;
    let zsq = &z * &z / &one;
    let mut series = one.clone();
    let mut term = one.clone();
    let mut k = 3u64;
    loop {
        term = &term * &zsq / &one;
        series += &term / k;
        if term == BigInt::from(0) { break; }
        println!("k={k} term={term} frac={}", (&term % k).to_f64().unwrap() / k as f64);
        k += 2;
    }
    let l: BigInt = "230258509299404568401799145468436420760110148862877".parse().unwrap();
    let q = &series * BigInt::from(2) * &one / &l;
    println!("series={series} q={q}");
    let exact_series = atanh_scaled(&d, &sum) * pow10(50) * &sum / &d; // atanh/Z at 1e140*1e50? 
    println!("atanh/z at 10^190 = {exact_series}");
    let ln10 = ln10_scaled();
    let t: BigInt = atanh_scaled(&d, &sum) * 2 * pow10(SC) / &ln10;
    println!("t={t}");
    let pa = precise::log10(&Dec::new(a.clone(), 0));
    let pb = precise::log10(&Dec::new(b.clone(), 0));
    println!("pa={:?}\npb={:?}", pa.value, pb.value);
}

#[test]
#[ignore]
fn search_log10_ratio_large_c() {
    let ln10 = ln10_scaled();
    let seed: u64 = std::env::var("SEED").ok().and_then(|s| s.parse().ok()).unwrap_or(0x9e3779b97f4a7c15);
    let mut rng = Rng(seed);
    let iters: usize = std::env::var("ITERS").ok().and_then(|s| s.parse().ok()).unwrap_or(10000);
    let mut best = (0f64, String::new());
    for _ in 0..iters {
        let b = BigInt::from(50026u64) * pow10(45) + rng.big(51) % (pow10(50) * 4);
        let zf = 2.7e-4 + (5.09e-4 - 2.7e-4) * ((rng.next() % 1_000_000) as f64 / 1e6);
        let d = &b * BigInt::from((zf * 2e12) as u64) / pow10(12) + rng.big(20);
        let below = rng.next() & 1 == 1;
        let a = if below { &b - &d } else { &b + &d };
        let sum = &a + &b;
        let (c, e) = log10_ratio(&a, &b, true);
        let c: BigInt = num_traits::Signed::abs(&c);
        let t: BigInt = atanh_scaled(&d, &sum) * 2 * pow10(SC) / &ln10;
        let shift = (SC as i64 + e) as u64;
        let err: BigInt = (&t * pow10(6)) / pow10(shift) - &c * pow10(6);
        let rel = err.to_f64().unwrap() / 1e6 / c.to_f64().unwrap() * 1e50;
        if rel > best.0 {
            best = (rel, format!("a={a} b={b} C={c} e={e}"));
            println!("{} {}", best.0, best.1);
        }
    }
}

#[test]
#[ignore]
fn search_exp10_top() {
    let seed: u64 = std::env::var("SEED").ok().and_then(|s| s.parse().ok()).unwrap_or(0x9e3779b97f4a7c15);
    let mut rng = Rng(seed);
    let iters: usize = std::env::var("ITERS").ok().and_then(|s| s.parse().ok()).unwrap_or(1000);
    let step = BigInt::from(1_525_878_906_25u64) * pow10(34);
    let base = &step * 65535u32;
    let mut best = (0f64, String::new());
    let mut best_pow = (0f64, String::new());
    for _ in 0..iters {
        // r in the top 2% of the cell
        let r = &step - BigInt::from(1) - rng.big(44) % (&step / 50);
        let m = &base + &r;
        let res = exp10_fixed(&m);
        let t = precise::pow10_true(&Dec::new(m.clone(), -50));
        let a = (scaled(&t.value, 56) - &res * pow10(6)).to_f64().unwrap() / 1e6;
        if a > best.0 {
            best = (a, format!("m={m}"));
            println!("exp10 {} {}", best.0, best.1);
        }
        let xp = Dec::new(&m * pow10(16) + (pow10(16) - 1), -66);
        let tp = precise::pow10_true(&xp);
        let ap = (scaled(&tp.value, 56) - &res * pow10(6)).to_f64().unwrap() / 1e6;
        if ap > best_pow.0 {
            best_pow = (ap, format!("x={}e-66", xp.c));
            println!("pow10 {} {}", best_pow.0, best_pow.1);
        }
    }
}
