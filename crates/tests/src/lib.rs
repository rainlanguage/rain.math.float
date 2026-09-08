//! Tests of the library through the `rain-math-float` bindings, run over
//! `test/concrete/TestDecimalFloat.sol` and `TestDecimalFloatHarness.sol`
//! compiled from this source, and cross-references of the packed constants
//! against values derived here.

#[cfg(test)]
mod constants;
#[cfg(test)]
mod float;
#[cfg(test)]
mod fuzz_ops;
#[cfg(test)]
mod tables;
