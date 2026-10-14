//! The equivalence baselines in `test/lib` are frozen copies of the library at
//! the commits their NatSpec cites. A baseline that called a helper on the
//! live library would change with that helper, and the equivalence tests would
//! compare the live helper with itself (#645). The sources are bound at
//! compile time, so a baseline that calls the live library fails here.

/// Each frozen baseline, by name, as committed.
const BASELINES: [(&str, &str); 6] = [
    (
        "LibDecimalFloatImplementationMain",
        include_str!("../../../test/lib/LibDecimalFloatImplementationMain.sol"),
    ),
    (
        "LibDecimalFloatGasMain",
        include_str!("../../../test/lib/LibDecimalFloatGasMain.sol"),
    ),
    (
        "LibDecimalFloatImplementationMulPr307",
        include_str!("../../../test/lib/LibDecimalFloatImplementationMulPr307.sol"),
    ),
    (
        "LibDecimalFloatImplementationSeriesMain",
        include_str!("../../../test/lib/LibDecimalFloatImplementationSeriesMain.sol"),
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

/// The first `LibDecimalFloatImplementation.<identifier>(` in `source`: a
/// call on the live library, not the `.sol` of an import path or a comment.
fn live_call(source: &str) -> Option<&str> {
    const LIBRARY: &str = "LibDecimalFloatImplementation.";
    source.match_indices(LIBRARY).find_map(|(at, _)| {
        let rest = &source[at + LIBRARY.len()..];
        let end = rest
            .find(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .unwrap_or(rest.len());
        (end > 0 && rest[end..].starts_with('(')).then(|| &rest[..end])
    })
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
