//! Tests of the library through the `rain-math-float` bindings, run over
//! `test/concrete/TestDecimalFloat.sol` and `TestDecimalFloatHarness.sol`
//! compiled from this source, and cross-references of the packed constants
//! against values derived here.

#[cfg(test)]
mod constants;
#[cfg(test)]
mod exact;
#[cfg(test)]
mod float;
#[cfg(test)]
mod oracle;
#[cfg(test)]
mod precise;
#[cfg(test)]
mod reference;
#[cfg(test)]
mod tables;
#[cfg(test)]
mod transcendental;
