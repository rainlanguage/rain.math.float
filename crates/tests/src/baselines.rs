//! Test-support sources that must not call the library under test.
//!
//! The equivalence baselines in `test/lib` are frozen copies of the library at
//! the commits their NatSpec cites. A baseline that called a helper on the
//! live library would change with that helper, and the equivalence tests would
//! compare the live helper with itself (#645).
//!
//! `LibTestErrorBound` gives the error bounds `LibTestPowRange` classifies
//! with, so a bound packed or unpacked by `LibDecimalFloat` would rest on the
//! code it tests (#672).
//!
//! The sources are bound at compile time, so a source that calls the library
//! fails here.

/// Each frozen baseline, by name, as committed.
const BASELINES: [(&str, &str); 6] = [
    (
        "LibDecimalFloatImplementationPreShortfall",
        include_str!("../../../test/lib/LibDecimalFloatImplementationPreShortfall.sol"),
    ),
    (
        "LibDecimalFloatPre310Mul",
        include_str!("../../../test/lib/LibDecimalFloatPre310Mul.sol"),
    ),
    (
        "LibDecimalFloatImplementationMulPr307",
        include_str!("../../../test/lib/LibDecimalFloatImplementationMulPr307.sol"),
    ),
    (
        "LibDecimalFloatImplementationSeriesLoop",
        include_str!("../../../test/lib/LibDecimalFloatImplementationSeriesLoop.sol"),
    ),
    (
        "LibDecimalFloatImplementationLog10RatioPr336",
        include_str!("../../../test/lib/LibDecimalFloatImplementationLog10RatioPr336.sol"),
    ),
    (
        "LibDecimalFloatImplementationAddPre394",
        include_str!("../../../test/lib/LibDecimalFloatImplementationAddPre394.sol"),
    ),
];

/// The first `<library>.<identifier>(` in `source`: a call on `library`, not
/// the `.sol` of an import path or a mention in a comment.
fn call_on<'a>(library: &str, source: &'a str) -> Option<&'a str> {
    let prefix = format!("{library}.");
    source.match_indices(&prefix).find_map(|(at, _)| {
        let rest = &source[at + prefix.len()..];
        let end = rest
            .find(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .unwrap_or(rest.len());
        (end > 0 && rest[end..].starts_with('(')).then(|| &rest[..end])
    })
}

/// The first call in `source` on the live implementation.
fn live_call(source: &str) -> Option<&str> {
    call_on("LibDecimalFloatImplementation", source)
}

#[test]
fn live_call_finds_calls_only() {
    assert_eq!(
        live_call("x = LibDecimalFloatImplementation.mulDiv(a, b, c);"),
        Some("mulDiv")
    );
    assert_eq!(
        live_call("import {A} from \"src/lib/implementation/LibDecimalFloatImplementation.sol\";"),
        None
    );
    assert_eq!(
        live_call("/// `LibDecimalFloatImplementation.sqrt`, for"),
        None
    );
}

#[test]
fn equivalence_baselines_call_no_live_library_function() {
    for (name, source) in BASELINES {
        assert_eq!(
            live_call(source),
            None,
            "{name} calls the live implementation"
        );
    }
}

/// The error bounds, as committed.
const ERROR_BOUND: &str = include_str!("../../../test/lib/LibTestErrorBound.sol");

#[test]
fn error_bounds_call_no_library_function() {
    assert!(
        !ERROR_BOUND.contains("using LibDecimalFloat"),
        "LibTestErrorBound binds LibDecimalFloat to Float"
    );
    assert_eq!(
        call_on("LibDecimalFloat", ERROR_BOUND),
        None,
        "LibTestErrorBound calls LibDecimalFloat"
    );
}
