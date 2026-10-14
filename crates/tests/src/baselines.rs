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
    /// Symbols `source` imports from a live library's file beyond
    /// `ALLOWED_IMPORTS`, each with why the copy still reads it live.
    imports: &'static [(&'static str, &'static str)],
}

/// The live libraries no baseline may use.
const LIVE: [&str; 4] = [
    "LibDecimalFloatImplementation",
    "LibDecimalFloat",
    "LibFormatDecimalFloat",
    "LibParseDecimalFloat",
];

/// The files the live libraries are declared in. A baseline importing from
/// one of them imports live code unless every symbol is allowed.
const LIVE_FILES: [&str; 4] = [
    "LibDecimalFloat.sol",
    "LibDecimalFloatImplementation.sol",
    "LibFormatDecimalFloat.sol",
    "LibParseDecimalFloat.sol",
];

/// What any baseline may import from a live library's file: the `Float` type.
/// Error types come from `src/error/Err*.sol`, which no live library file is,
/// so they need no entry; a live library's own name may be imported, since
/// `use_on` finds every use of it.
const ALLOWED_IMPORTS: [&str; 1] = ["Float"];

/// A file-level constant the copy reads from the live library. Its value is
/// the one at the commit the copy cites, so the copy's results are that
/// commit's; a change to it would move the copy, which is why it is listed.
const SAME_CONSTANT: &str = "file-level constant, equal to its value at the cited commit";

/// Why the sqrt variants share the live library.
const SQRT_VARIANT: &str = "differs from the live sqrt only in its named step, \
     and its equivalence test asserts the same bytes as the live sqrt";

const BASELINES: [Baseline; 10] = [
    Baseline {
        name: "LibDecimalFloatImplementationPreShortfall",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationPreShortfall.sol"),
        variants: &[],
        imports: &[
            ("ADD_MAX_EXPONENT_DIFF", SAME_CONSTANT),
            ("MAXIMIZED_ZERO_SIGNED_COEFFICIENT", SAME_CONSTANT),
            ("MAXIMIZED_ZERO_EXPONENT", SAME_CONSTANT),
        ],
    },
    Baseline {
        name: "LibDecimalFloatPre310Mul",
        source: include_str!("../../../test/lib/LibDecimalFloatPre310Mul.sol"),
        variants: &[],
        imports: &[
            ("MAXIMIZED_ZERO_SIGNED_COEFFICIENT", SAME_CONSTANT),
            ("MAXIMIZED_ZERO_EXPONENT", SAME_CONSTANT),
            ("FIVE_INVERSE", SAME_CONSTANT),
        ],
    },
    Baseline {
        name: "LibDecimalFloatImplementationMulPr307",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationMulPr307.sol"),
        variants: &[],
        imports: &[
            ("MAXIMIZED_ZERO_SIGNED_COEFFICIENT", SAME_CONSTANT),
            ("MAXIMIZED_ZERO_EXPONENT", SAME_CONSTANT),
        ],
    },
    Baseline {
        name: "LibDecimalFloatImplementationSeriesLoop",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationSeriesLoop.sol"),
        variants: &[],
        imports: &[
            ("POW_FIXED_ONE", SAME_CONSTANT),
            ("POW_FIXED_LN10", SAME_CONSTANT),
            ("POW_FIXED_ONE_ODD_INVERSE", SAME_CONSTANT),
            ("LOG10_RATIO_Z_MAX", SAME_CONSTANT),
        ],
    },
    Baseline {
        name: "LibDecimalFloatImplementationLog10RatioPr336",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationLog10RatioPr336.sol"),
        variants: &[],
        imports: &[
            ("MAXIMIZED_ZERO_SIGNED_COEFFICIENT", SAME_CONSTANT),
            ("MAXIMIZED_ZERO_EXPONENT", SAME_CONSTANT),
            ("POW_FIXED_ONE", SAME_CONSTANT),
            ("POW_FIXED_LN10", SAME_CONSTANT),
            (
                "POW_FIXED_SQRT_ONE",
                "file-level constant the live pow added after 5210e11; the copy has always read it live",
            ),
            (
                "POW_FIXED_TWO_SQRT_ONE",
                "file-level constant the live pow added after 5210e11; the copy has always read it live",
            ),
            ("POW_FIXED_ONE_ODD_INVERSE", SAME_CONSTANT),
        ],
    },
    Baseline {
        name: "LibDecimalFloatImplementationAddPre394",
        source: include_str!("../../../test/lib/LibDecimalFloatImplementationAddPre394.sol"),
        variants: &[],
        imports: &[
            ("ADD_MAX_EXPONENT_DIFF", SAME_CONSTANT),
            ("MAXIMIZED_ZERO_SIGNED_COEFFICIENT", SAME_CONSTANT),
            ("MAXIMIZED_ZERO_EXPONENT", SAME_CONSTANT),
        ],
    },
    Baseline {
        name: "LibDecimalFloatSqrtVariants",
        source: include_str!("../../../test/lib/LibDecimalFloatSqrtVariants.sol"),
        variants: &[
            ("sqrtPlainNewton", SQRT_VARIANT),
            ("sqrtAsmResidual", SQRT_VARIANT),
            ("sqrt512Residual", SQRT_VARIANT),
        ],
        imports: &[],
    },
    Baseline {
        name: "LibDecimalFloatPackLossyLiftFirst",
        source: include_str!("../../../test/lib/LibDecimalFloatPackLossyLiftFirst.sol"),
        variants: &[],
        imports: &[],
    },
    Baseline {
        name: "LibFormatDecimalFloatPr321",
        source: include_str!("../../../test/lib/LibFormatDecimalFloatPr321.sol"),
        variants: &[],
        imports: &[],
    },
    Baseline {
        name: "LibParseDecimalFloatPr321",
        source: include_str!("../../../test/lib/LibParseDecimalFloatPr321.sol"),
        variants: &[],
        imports: &[],
    },
];

/// `source` with every comment and string literal blanked to spaces, so
/// newlines and offsets are kept and only code is left to match.
fn code_only(source: &str) -> String {
    blanked(source, true)
}

/// `source` with every comment blanked to spaces, and every string literal
/// too when `strings`, keeping newlines and offsets.
fn blanked(source: &str, strings: bool) -> String {
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
        } else if strings && (bytes[i] == b'"' || bytes[i] == b'\'') {
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
/// `library` itself, not on a library whose name merely starts or ends with
/// it. Solidity allows whitespace either side of the dot, so both are skipped.
fn use_on<'a>(library: &str, code: &'a str) -> Option<&'a str> {
    code.match_indices(library).find_map(|(at, _)| {
        if code[..at].chars().next_back().is_some_and(is_identifier) {
            return None;
        }
        let rest = code[at + library.len()..]
            .trim_start()
            .strip_prefix('.')?
            .trim_start();
        let end = rest.find(|c| !is_identifier(c)).unwrap_or(rest.len());
        Some(&rest[..end])
    })
}

/// Whether `code` binds `library` with a `using` directive: the word `using`,
/// whitespace, the library name, then a character that cannot continue it.
fn binds(library: &str, code: &str) -> bool {
    code.match_indices("using").any(|(at, _)| {
        if code[..at].chars().next_back().is_some_and(is_identifier) {
            return false;
        }
        let after_using = &code[at + "using".len()..];
        let rest = after_using.trim_start();
        rest.len() < after_using.len()
            && rest
                .strip_prefix(library)
                .is_some_and(|after| !after.starts_with(is_identifier))
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

/// The first `import` in `code` (comments blanked, strings kept) from a live
/// library's file of anything not allowed: the whole file, or a symbol that is
/// neither in `ALLOWED_IMPORTS`, a live library's name nor declared in
/// `imports`. An aliased symbol, `X as Y`, matches no allowed name, so it is
/// never allowed.
fn live_import(code: &str, imports: &[(&str, &str)]) -> Option<String> {
    let mut rest = code;
    while let Some(at) = rest.find("import") {
        let word = !rest[..at].chars().next_back().is_some_and(is_identifier);
        let after = &rest[at + "import".len()..];
        let Some(end) = after.find(';') else {
            break;
        };
        let statement = &after[..end];
        rest = &after[end + 1..];
        if !word || statement.starts_with(is_identifier) {
            continue;
        }
        let Some(path) = statement.rsplit('"').nth(1) else {
            continue;
        };
        let file = path.rsplit('/').next().unwrap_or(path);
        if !LIVE_FILES.contains(&file) {
            continue;
        }
        let (Some(open), Some(close)) = (statement.find('{'), statement.find('}')) else {
            return Some(format!("import {file}"));
        };
        for symbol in statement[open + 1..close].split(',') {
            let symbol = symbol.trim();
            let allowed = !symbol.is_empty()
                && (ALLOWED_IMPORTS.contains(&symbol)
                    || LIVE.contains(&symbol)
                    || imports.iter().any(|(declared, _)| *declared == symbol));
            if !allowed {
                return Some(format!("import {symbol} from {file}"));
            }
        }
    }
    None
}

/// The first use in `source` of a live library: an import from its file that
/// is not allowed, or `library.member` or `using library` outside the
/// functions in `variants`.
fn live_use(
    source: &str,
    variants: &[(&str, &str)],
    imports: &[(&str, &str)],
) -> Result<Option<String>, String> {
    if let Some(import) = live_import(&blanked(source, false), imports) {
        return Ok(Some(import));
    }
    let mut code = code_only(source);
    for (variant, _) in variants {
        code = without_function(&code, variant).ok_or(format!("no function {variant}"))?;
    }
    for library in LIVE {
        if binds(library, &code) {
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
        live_use(
            "x = LibDecimalFloatImplementation.mulDiv(a, b, c);",
            none,
            none
        ),
        Ok(Some("LibDecimalFloatImplementation.mulDiv".into()))
    );
    assert_eq!(
        live_use("return (LibDecimalFloat.FLOAT_ZERO, true);", none, none),
        Ok(Some("LibDecimalFloat.FLOAT_ZERO".into()))
    );
    assert_eq!(
        live_use(
            "(Float f, bool l) = LibDecimalFloat.packLossy(c, e);",
            none,
            none
        ),
        Ok(Some("LibDecimalFloat.packLossy".into()))
    );
    assert_eq!(
        live_use(
            "return LibFormatDecimalFloat.toDecimalString(f, true);",
            none,
            none
        ),
        Ok(Some("LibFormatDecimalFloat.toDecimalString".into()))
    );
    assert_eq!(
        live_use("LibParseDecimalFloat.parseDecimalFloat(s);", none, none),
        Ok(Some("LibParseDecimalFloat.parseDecimalFloat".into()))
    );
    assert_eq!(
        live_use("using LibDecimalFloat for Float;", none, none),
        Ok(Some("using LibDecimalFloat".into()))
    );
    assert_eq!(
        live_use("using LibDecimalFloat\nfor Float;", none, none),
        Ok(Some("using LibDecimalFloat".into()))
    );
    assert_eq!(
        live_use("using LibDecimalFloatPr321 for Float;", none, none),
        Ok(None)
    );
    assert_eq!(
        live_use("usingLibDecimalFloat for Float;", none, none),
        Ok(None)
    );
    assert_eq!(
        live_use("reusing LibDecimalFloat for Float;", none, none),
        Ok(None)
    );
    assert_eq!(
        live_use("LibDecimalFloat .unpack(f);", none, none),
        Ok(Some("LibDecimalFloat.unpack".into()))
    );
    assert_eq!(
        live_use("LibDecimalFloat. unpack(f);", none, none),
        Ok(Some("LibDecimalFloat.unpack".into()))
    );
    assert_eq!(
        live_use(
            "import {Float} from \"src/lib/LibDecimalFloat.sol\";",
            none,
            none
        ),
        Ok(None)
    );
    assert_eq!(
        live_use("/// `LibDecimalFloatImplementation.sqrt`, for", none, none),
        Ok(None)
    );
    assert_eq!(
        live_use("/* LibDecimalFloat.unpack(f) */ x = 1;", none, none),
        Ok(None)
    );
    assert_eq!(
        live_use("// LibDecimalFloat.unpack(f)", none, none),
        Ok(None)
    );
    assert_eq!(
        live_use("s = \"\\\"LibDecimalFloat.unpack\\\"\";", none, none),
        Ok(None)
    );
    assert_eq!(
        live_use("$LibDecimalFloat.unpack(f);", none, none),
        Ok(None)
    );
    assert_eq!(
        live_use(
            "LibFormatDecimalFloatPr321.toDecimalString(f, true);",
            none,
            none
        ),
        Ok(None)
    );
    assert_eq!(
        live_use("MyLibDecimalFloat.unpack(f);", none, none),
        Ok(None)
    );
}

#[test]
fn live_import_finds_live_files_only() {
    let none: &[(&str, &str)] = &[];
    let implementation = "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
    assert_eq!(
        live_use(
            "import {LibDecimalFloat as L} from \"../../src/lib/LibDecimalFloat.sol\";\nL.unpack(f);",
            none,
            none
        ),
        Ok(Some(
            "import LibDecimalFloat as L from LibDecimalFloat.sol".into()
        ))
    );
    assert_eq!(
        live_use(
            &format!("import {{MAXIMIZED_ZERO_EXPONENT}} from \"{implementation}\";"),
            none,
            none
        ),
        Ok(Some(
            "import MAXIMIZED_ZERO_EXPONENT from LibDecimalFloatImplementation.sol".into()
        ))
    );
    assert_eq!(
        live_use(
            &format!("import {{MAXIMIZED_ZERO_EXPONENT}} from \"{implementation}\";"),
            none,
            &[("MAXIMIZED_ZERO_EXPONENT", "why")]
        ),
        Ok(None)
    );
    assert_eq!(
        live_use(
            &format!(
                "import {{\n    Float,\n    MAXIMIZED_ZERO_EXPONENT\n}} from \"{implementation}\";"
            ),
            none,
            none
        ),
        Ok(Some(
            "import MAXIMIZED_ZERO_EXPONENT from LibDecimalFloatImplementation.sol".into()
        ))
    );
    assert_eq!(
        live_use(
            &format!("import {{LibDecimalFloatImplementation}} from \"{implementation}\";"),
            none,
            none
        ),
        Ok(None)
    );
    assert_eq!(
        live_use("import \"../../src/lib/LibDecimalFloat.sol\";", none, none),
        Ok(Some("import LibDecimalFloat.sol".into()))
    );
    assert_eq!(
        live_use(
            "import * as D from \"../../src/lib/LibDecimalFloat.sol\";",
            none,
            none
        ),
        Ok(Some("import LibDecimalFloat.sol".into()))
    );
    assert_eq!(
        live_use(
            "import {ExponentOverflow} from \"../../src/error/ErrDecimalFloat.sol\";",
            none,
            none
        ),
        Ok(None)
    );
    assert_eq!(
        live_use(
            "import {LibDecimalFloatPr321} from \"./LibDecimalFloatPr321.sol\";",
            none,
            none
        ),
        Ok(None)
    );
    assert_eq!(
        live_use(
            "// import {X} from \"../../src/lib/LibDecimalFloat.sol\";",
            none,
            none
        ),
        Ok(None)
    );
    assert_eq!(
        live_use(
            "reimport {X} from \"../../src/lib/LibDecimalFloat.sol\";",
            none,
            none
        ),
        Ok(None)
    );
}

#[test]
fn live_use_skips_variants_only() {
    let none: &[(&str, &str)] = &[];
    let source = "function a() { if (x) { LibDecimalFloat.unpack(f); } }\n\
                  function b() { LibDecimalFloat.pack(c, e); }";
    assert_eq!(
        live_use(source, &[("a", "why")], none),
        Ok(Some("LibDecimalFloat.pack".into()))
    );
    assert_eq!(
        live_use(source, &[("a", "why"), ("b", "why")], none),
        Ok(None)
    );
    assert_eq!(
        live_use(source, &[("c", "why")], none),
        Err("no function c".into())
    );
    // A variant's name that prefixes another function's blanks only its own.
    let prefixed = "function ab() { LibDecimalFloat.unpack(f); }\n\
                    function a() { LibDecimalFloat.pack(c, e); }";
    assert_eq!(
        live_use(prefixed, &[("a", "why")], none),
        Ok(Some("LibDecimalFloat.unpack".into()))
    );
}

#[test]
fn equivalence_baselines_use_no_live_library() {
    for baseline in BASELINES {
        assert_eq!(
            live_use(baseline.source, baseline.variants, baseline.imports),
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
                matches!(
                    live_use(baseline.source, &others, baseline.imports),
                    Ok(Some(_))
                ),
                "{}.{variant} is listed as a variant but uses no live library",
                baseline.name
            );
        }
    }
}

/// A symbol is declared as a live import only because the baseline imports
/// it from a live library's file: one it does not import is stale.
#[test]
fn declared_imports_are_imported() {
    for baseline in BASELINES {
        for (symbol, reason) in baseline.imports {
            assert!(!reason.is_empty());
            let others: Vec<(&str, &str)> = baseline
                .imports
                .iter()
                .copied()
                .filter(|(other, _)| other != symbol)
                .collect();
            assert_eq!(
                live_use(baseline.source, baseline.variants, &others),
                Ok(Some(format!(
                    "import {symbol} from LibDecimalFloatImplementation.sol"
                ))),
                "{}.{symbol} is declared imported but is not",
                baseline.name
            );
        }
    }
}

/// Files in `test/lib` that are live code by design although they read as
/// baselines, each with why.
const EXEMPT: [(&str, &str); 2] = [
    (
        "LibFormatDecimalFloatSolidity",
        "the live format with its assembly in plain Solidity, compared against the live library",
    ),
    (
        "LibDecimalFloatImplementationSeriesSolidity",
        "the live series with their assembly in plain Solidity, compared against the live library",
    ),
];

/// Every file in `test/lib` whose NatSpec calls it a baseline or a verbatim
/// copy is in `BASELINES`, or exempt with a reason; and every listed or
/// exempt name is such a file.
#[test]
fn every_baseline_is_listed() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../test/lib");
    let mut copies = Vec::new();
    for entry in std::fs::read_dir(&dir).expect("test/lib") {
        let path = entry.expect("entry").path();
        if path.extension().and_then(|e| e.to_str()) != Some("sol") {
            continue;
        }
        let source = std::fs::read_to_string(&path).expect("read");
        if source.contains("EQUIVALENCE BASELINE ONLY") || source.contains("verbatim from") {
            let stem = path.file_stem().and_then(|s| s.to_str()).expect("stem");
            copies.push(stem.to_string());
        }
    }
    for stem in &copies {
        let listed = BASELINES.iter().any(|baseline| baseline.name == stem);
        let exempt = EXEMPT
            .iter()
            .any(|(name, reason)| name == stem && !reason.is_empty());
        assert!(
            listed || exempt,
            "{stem} reads as a frozen copy but is neither in BASELINES nor exempt"
        );
    }
    for name in BASELINES
        .iter()
        .map(|baseline| baseline.name)
        .chain(EXEMPT.iter().map(|(name, _)| *name))
    {
        assert!(
            copies.iter().any(|stem| stem == name),
            "{name} is listed but no such file in test/lib reads as a frozen copy"
        );
    }
}

/// The error bounds, as committed.
const ERROR_BOUND: &str = include_str!("../../../test/lib/LibTestErrorBound.sol");

#[test]
fn error_bounds_use_no_library() {
    assert_eq!(
        live_use(ERROR_BOUND, &[], &[]),
        Ok(None),
        "LibTestErrorBound uses the live library"
    );
}
