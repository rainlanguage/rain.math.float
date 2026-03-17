//! WASM cdylib wrapper for `rain-math-float`.
//!
//! This crate exists solely to produce the cdylib artifact for WASM targets.
//! The core library (`rain-math-float`) is rlib-only to avoid output filename
//! collisions that cause duplicate dependency compilation in downstream
//! consumers.

pub use rain_math_float::*;
