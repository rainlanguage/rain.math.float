//! Test-support sources that must not use the library under test.
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
//! The sources are bound at compile time, so a source that uses the library
//! fails here.

/// A frozen baseline, as committed.
struct Baseline {
    name: &'static str,
    source: &'static str,
    /// Functions in `source` that are deliberate variants of live code rather
    /// than frozen copies, each with why it shares the live library.
    variants: &'static [(&'static str, &'static str)],
}

/// The live libraries no baseline may use.
const LIVE: [&str; 4] = [
    "LibDecimalFloatImplementation",
    "LibDecimalFloat",
    "LibFormatDecimalFloat",
    "LibParseDecimalFloat",
];

/// Why the sqrt variants share the live library.
const SQRT_VARIANT: &str = "differs from the live sqrt only in its named step, \
     and its equivalence test asserts the same bytes as the live sqrt";

const BASELINES: [Baseline; 10] = [
    Baseline {
        name: "LibDecimalFloatImplementationMain",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationMain.sol"),
        variants: &[],
    },
    Baseline {
        name: "LibDecimalFloatGasMain",
        source: include_str!("../../../test/lib/LibDecimalFloatGasMain.sol"),
        variants: &[],
    },
    Baseline {
        name: "LibDecimalFloatImplementationMulPr307",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationMulPr307.sol"),
        variants: &[],
    },
    Baseline {
        name: "LibDecimalFloatImplementationSeriesMain",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationSeriesMain.sol"),
        variants: &[],
    },
    Baseline {
        name: "LibDecimalFloatImplementationLog10RatioPr336",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationLog10RatioPr336.sol"),
        variants: &[],
    },
    Baseline {
        name: "LibDecimalFloatImplementationAddPre394",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationAddPre394.sol"),
        variants: &[],
    },
    Baseline {
        name: "LibDecimalFloatSqrtVariants",
        source: include_str!("../../../test/lib/LibDecimalFloatSqrtVariants.sol"),
        variants: &[
            ("sqrtPlainNewton", SQRT_VARIANT),
            ("sqrtAsmResidual", SQRT_VARIANT),
            ("sqrt512Residual", SQRT_VARIANT),
        ],
    },
    Baseline {
        name: "LibDecimalFloatPackLossyLiftFirst",
        source: include_str!("../../../test/lib/LibDecimalFloatPackLossyLiftFirst.sol"),
        variants: &[],
    },
    Baseline {
        name: "LibFormatDecimalFloatPr321",
        source: include_str!("../../../test/lib/LibFormatDecimalFloatPr321.sol"),
        variants: &[],
    },
    Baseline {
        name: "LibParseDecimalFloatPr321",
        source: include_str!("../../../test/lib/LibParseDecimalFloatPr321.sol"),
        variants: &[],
    },
];

/// `source` with every comment and string literal blanked to spaces, so
/// newlines and offsets are kept and only code is left to match.
fn code_only(source: &str) -> String {
    let bytes = source.as_bytes();
    let mut out = bytes.to_vec();
    let mut i = 0;
    while i < bytes.len() {
        let start = i;
        if bytes[i..].starts_with(b"//") {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
        } else if bytes[i..].starts_with(b"/*") {
            i += 2;
            while i < bytes.len() && !bytes[i..].starts_with(b"*/") {
                i += 1;
            }
            i = (i + 2).min(bytes.len());
        } else if bytes[i] == b'"' || bytes[i] == b'\'' {
            let quote = bytes[i];
            i += 1;
            while i < bytes.len() && bytes[i] != quote {
                i += if bytes[i] == b'\\' { 2 } else { 1 };
            }
            i = (i + 1).min(bytes.len());
        } else {
            i += 1;
            continue;
        }
        // A blanked span starts and ends on ASCII, so it holds whole
        // characters and the result stays UTF-8.
        for byte in &mut out[start..i] {
            if *byte != b'\n' {
                *byte = b' ';
            }
        }
    }
    String::from_utf8(out).expect("blanking keeps UTF-8")
}

fn is_identifier(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '$'
}

/// The first `<library>.<identifier>` in `code`, a call or a constant read on
/// `library` itself, not on a library whose name merely ends in it.
fn use_on<'a>(library: &str, code: &'a str) -> Option<&'a str> {
    let prefix = format!("{library}.");
    code.match_indices(&prefix).find_map(|(at, _)| {
        if code[..at].chars().next_back().is_some_and(is_identifier) {
            return None;
        }
        let rest = &code[at + prefix.len()..];
        let end = rest.find(|c| !is_identifier(c)).unwrap_or(rest.len());
        (end > 0).then(|| &rest[..end])
    })
}

/// `code` with the whole of function `name`, header to closing brace,
/// blanked. `None` when `code` defines no function `name`.
fn without_function(code: &str, name: &str) -> Option<String> {
    let header = format!("function {name}(");
    let start = code.find(&header)?;
    let open = start + code[start..].find('{')?;
    let mut depth = 0usize;
    let mut end = None;
    for (offset, c) in code[open..].char_indices() {
        match c {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    end = Some(open + offset + 1);
                    break;
                }
            }
            _ => {}
        }
    }
    let end = end?;
    Some(format!(
        "{}{}{}",
        &code[..start],
        " ".repeat(end - start),
        &code[end..]
    ))
}

/// The first use in `source` of a live library, as `library.member` or
/// `using library`, outside the functions in `variants`.
fn live_use(source: &str, variants: &[(&str, &str)]) -> Result<Option<String>, String> {
    let mut code = code_only(source);
    for (variant, _) in variants {
        code = without_function(&code, variant).ok_or(format!("no function {variant}"))?;
    }
    for library in LIVE {
        if code.contains(&format!("using {library} ")) {
            return Ok(Some(format!("using {library}")));
        }
        if let Some(member) = use_on(library, &code) {
            return Ok(Some(format!("{library}.{member}")));
        }
    }
    Ok(None)
}

#[test]
fn live_use_finds_code_only() {
    let none: &[(&str, &str)] = &[];
    assert_eq!(
        live_use("x = LibDecimalFloatImplementation.mulDiv(a, b, c);", none),
        Ok(Some("LibDecimalFloatImplementation.mulDiv".into()))
    );
    assert_eq!(
        live_use("return (LibDecimalFloat.FLOAT_ZERO, true);", none),
        Ok(Some("LibDecimalFloat.FLOAT_ZERO".into()))
    );
    assert_eq!(
        live_use("(Float f, bool l) = LibDecimalFloat.packLossy(c, e);", none),
        Ok(Some("LibDecimalFloat.packLossy".into()))
    );
    assert_eq!(
        live_use(
            "return LibFormatDecimalFloat.toDecimalString(f, true);",
            none
        ),
        Ok(Some("LibFormatDecimalFloat.toDecimalString".into()))
    );
    assert_eq!(
        live_use("LibParseDecimalFloat.parseDecimalFloat(s);", none),
        Ok(Some("LibParseDecimalFloat.parseDecimalFloat".into()))
    );
    assert_eq!(
        live_use("using LibDecimalFloat for Float;", none),
        Ok(Some("using LibDecimalFloat".into()))
    );
    assert_eq!(
        live_use(
            "import {A} from \"src/lib/implementation/LibDecimalFloatImplementation.sol\";",
            none
        ),
        Ok(None)
    );
    assert_eq!(
        live_use("/// `LibDecimalFloatImplementation.sqrt`, for", none),
        Ok(None)
    );
    assert_eq!(
        live_use("/* LibDecimalFloat.unpack(f) */ x = 1;", none),
        Ok(None)
    );
    assert_eq!(
        live_use("LibFormatDecimalFloatPr321.toDecimalString(f, true);", none),
        Ok(None)
    );
    assert_eq!(live_use("MyLibDecimalFloat.unpack(f);", none), Ok(None));
}

#[test]
fn live_use_skips_variants_only() {
    let source = "function a() { if (x) { LibDecimalFloat.unpack(f); } }\n\
                  function b() { LibDecimalFloat.pack(c, e); }";
    assert_eq!(
        live_use(source, &[("a", "why")]),
        Ok(Some("LibDecimalFloat.pack".into()))
    );
    assert_eq!(live_use(source, &[("a", "why"), ("b", "why")]), Ok(None));
    assert_eq!(
        live_use(source, &[("c", "why")]),
        Err("no function c".into())
    );
}

#[test]
fn equivalence_baselines_use_no_live_library() {
    for baseline in BASELINES {
        assert_eq!(
            live_use(baseline.source, baseline.variants),
            Ok(None),
            "{} uses the live library",
            baseline.name
        );
    }
}

/// A function is listed as a variant only because it shares the live
/// library: one that does not belongs with the frozen copies.
#[test]
fn variants_use_the_live_library() {
    for baseline in BASELINES {
        for (variant, reason) in baseline.variants {
            assert!(!reason.is_empty());
            let others: Vec<(&str, &str)> = baseline
                .variants
                .iter()
                .copied()
                .filter(|(other, _)| other != variant)
                .collect();
            assert!(
                matches!(live_use(baseline.source, &others), Ok(Some(_))),
                "{}.{variant} is listed as a variant but uses no live library",
                baseline.name
            );
        }
    }
}

/// The error bounds, as committed.
const ERROR_BOUND: &str = include_str!("../../../test/lib/LibTestErrorBound.sol");

#[test]
fn error_bounds_use_no_library() {
    assert_eq!(
        live_use(ERROR_BOUND, &[]),
        Ok(None),
        "LibTestErrorBound uses the live library"
    );
}
