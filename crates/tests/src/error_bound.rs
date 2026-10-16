//! `LibTestErrorBound` gives the error bounds `LibTestPowRange` classifies
//! with, so a bound packed or unpacked by `LibDecimalFloat` would rest on the
//! code it tests (#672).
//!
//! The source is bound at compile time, so a source that calls the library
//! fails here.

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

#[test]
fn call_on_finds_calls_only() {
    assert_eq!(
        call_on("LibDecimalFloat", "x = LibDecimalFloat.packLossless(a, b);"),
        Some("packLossless")
    );
    assert_eq!(
        call_on(
            "LibDecimalFloat",
            "import {A} from \"src/lib/LibDecimalFloat.sol\";"
        ),
        None
    );
    assert_eq!(
        call_on("LibDecimalFloat", "/// `LibDecimalFloat.pow`, for"),
        None
    );
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
