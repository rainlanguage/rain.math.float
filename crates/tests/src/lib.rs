//! Tests of `test/concrete/TestDecimalFloat.sol` and
//! `TestDecimalFloatHarness.sol` compiled from this source, by their ABI in
//! revm (`evm.rs`), and cross-references of the packed constants against
//! values derived here.

#[cfg(test)]
mod constants;
#[cfg(test)]
mod evm;
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
