// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";

/// Probe hand-constructed "exotic" Floats — valid packings with extreme
/// trailing-zero coefficients and negative exponents beyond the formatter's
/// -76 limit — for observable problems across each library operation. The
/// hypothesis under test: does Approach A (trailing-zero stripping in
/// `packLossy`) fix anything that Approach B (formatter rewrite) would not
/// also fix? If every op except non-scientific format works correctly on
/// exotic inputs, A buys nothing beyond formatting.
contract LibDecimalFloatExoticFloatTest is Test {
    using LibDecimalFloat for Float;
    using LibFormatDecimalFloat for Float;

    // 1e66 × 10^-78 = 1e-12. Coefficient has 66 trailing decimal zeros,
    // exponent is beyond the -76 formatter range. Canonical form is (1, -12).
    int256 constant EXOTIC_COEF = int256(1e66);
    int256 constant EXOTIC_EXP = -78;
    int256 constant CANONICAL_COEF = 1;
    int256 constant CANONICAL_EXP = -12;

    function exotic() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(EXOTIC_COEF, EXOTIC_EXP);
    }

    function canonical() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(CANONICAL_COEF, CANONICAL_EXP);
    }

    /// Exotic and canonical representations compare equal.
    function testExoticEq() external pure {
        assertTrue(exotic().eq(canonical()));
        assertTrue(canonical().eq(exotic()));
    }

    /// Ordering works across representations.
    function testExoticOrdering() external pure {
        Float bigger = LibDecimalFloat.packLossless(2, -12);
        assertTrue(exotic().lt(bigger));
        assertTrue(bigger.gt(exotic()));
        assertTrue(exotic().lte(canonical()));
        assertTrue(exotic().gte(canonical()));
    }

    /// Addition of exotics produces a numerically correct result.
    function testExoticAdd() external pure {
        Float sum = exotic().add(exotic());
        Float expected = LibDecimalFloat.packLossless(2, -12);
        assertTrue(sum.eq(expected));
    }

    /// Subtraction of exotic minus canonical same-value = 0.
    function testExoticSubSelfToZero() external pure {
        Float diff = exotic().sub(canonical());
        assertTrue(diff.eq(LibDecimalFloat.packLossless(0, 0)));
    }

    /// Multiplication of exotics.
    function testExoticMul() external pure {
        Float product = exotic().mul(exotic());
        Float expected = LibDecimalFloat.packLossless(1, -24);
        assertTrue(product.eq(expected));
    }

    /// Division of exotics = 1.
    function testExoticDivSelf() external pure {
        Float q = exotic().div(exotic());
        assertTrue(q.eq(LibDecimalFloat.packLossless(1, 0)));
    }

    /// Negation preserves value semantics.
    function testExoticMinus() external pure {
        Float neg = exotic().minus();
        Float expected = LibDecimalFloat.packLossless(-1, -12);
        assertTrue(neg.eq(expected));
    }

    /// Inverse produces numerically correct result.
    function testExoticInv() external pure {
        Float i = exotic().inv();
        Float expected = LibDecimalFloat.packLossless(1, 12);
        assertTrue(i.eq(expected));
    }

    /// Floor of a tiny positive number is 0.
    function testExoticFloor() external pure {
        Float f = exotic().floor();
        assertTrue(f.eq(LibDecimalFloat.packLossless(0, 0)));
    }

    /// Ceiling of a tiny positive number is 1.
    function testExoticCeil() external pure {
        Float c = exotic().ceil();
        assertTrue(c.eq(LibDecimalFloat.packLossless(1, 0)));
    }

    /// Scientific formatting works on exotic Floats.
    function testExoticToScientificString() external pure {
        string memory s = exotic().toDecimalString(true);
        string memory sc = canonical().toDecimalString(true);
        assertEq(s, sc, "Scientific format should match canonical");
    }

    /// Non-scientific formatting of the exotic form now succeeds. Prior to
    /// the #182 fix this reverted with `UnformatableExponent` because the
    /// formatter computed `10^78` as int256. The rewritten formatter uses
    /// direct string placement and renders the correct value.
    function testExoticToDecimalStringMatchesCanonical() external pure {
        assertEq(exotic().toDecimalString(false), canonical().toDecimalString(false));
        assertEq(exotic().toDecimalString(false), "0.000000000001");
    }

    /// Canonical form formats fine in non-sci mode.
    function testCanonicalToDecimalStringWorks() external pure {
        string memory s = canonical().toDecimalString(false);
        assertEq(s, "0.000000000001");
    }
}
