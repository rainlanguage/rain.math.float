// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibDecimalFloatImplementation,
    LOG10_RATIO_Z_MAX,
    LOG10_SKIP_BELOW
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibExactFloat, ORACLE_ONE, ORACLE_LN10} from "../../../lib/LibExactFloat.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";
import {Log10RatioRelativeSumTooSmall, Log10RatioOutOfRange} from "src/error/ErrDecimalFloat.sol";

/// Bounds from the `log10Ratio` NatSpec, for z = |a - b| / (a + b) at most
/// 5.1e-4: the magnitude is at most 1.3e-51 relative above the true log, and
/// below it by under 1.0036 units of 1e-50 for a coefficient at that scale,
/// or by C 8.03e-50 plus a unit of its exponent when `relative`. Up to
/// `LOG10_RATIO_Z_MAX` those are 1.0053 units and C 8.082e-50 plus a unit.
contract LibDecimalFloatImplementationLog10RatioTest is Test {
    function abs(int256 value) internal pure returns (int256) {
        return value < 0 ? -value : value;
    }

    /// `m × c × 10^e` exactly, as two terms that each fit an int256 for a
    /// non-negative `c` and `m` below 100.
    function multiple(int256 c, int256 m, int256 e) internal pure returns (int256, int256, int256, int256) {
        return (m * (c / 100), e + 2, m * (c % 100), e);
    }

    /// log10Ratio against the proven bounds, for an expected value truncated
    /// toward zero to 70 significant digits by `bc -l`, so below the true
    /// magnitude by under a unit in its last place.
    function checkAgainstBc(uint256 a, uint256 b, bool relative, int256 expectedCoefficient, int256 expectedExponent)
        internal
        pure
    {
        checkAgainstBcWithin(a, b, relative, expectedCoefficient, expectedExponent, 10036, 8030);
    }

    /// As `checkAgainstBc`, with the fixed point bound below the log at
    /// `fixedBelow` units of 1e-54 and the relative bound at C
    /// `relativeBelow` 1e-53, whose last three digits are under 100.
    function checkAgainstBcWithin(
        uint256 a,
        uint256 b,
        bool relative,
        int256 expectedCoefficient,
        int256 expectedExponent,
        int256 fixedBelow,
        int256 relativeBelow
    ) internal pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(a, b, relative);
        assertTrue(expectedCoefficient < 0 ? signedCoefficient <= 0 : signedCoefficient >= 0, "sign");
        int256 c = abs(signedCoefficient);
        int256[] memory coefficients = new int256[](2);
        int256[] memory exponents = new int256[](2);
        (coefficients[0], exponents[0]) = (c, exponent);
        (coefficients[1], exponents[1]) = (-abs(expectedCoefficient), expectedExponent);
        int256[] memory boundCoefficients = new int256[](5);
        int256[] memory boundExponents = new int256[](5);
        (boundCoefficients[0], boundExponents[0], boundCoefficients[1], boundExponents[1]) =
            multiple(c, 13, exponent - 52);
        (boundCoefficients[2], boundExponents[2]) = (1, expectedExponent);
        assertTrue(LibExactFloat.sumLte(coefficients, exponents, boundCoefficients, boundExponents), "log10Ratio above");
        (coefficients[0], coefficients[1]) = (-coefficients[0], -coefficients[1]);
        if (relative) {
            // C relativeBelow 1e-53 as its thousands at 1e-50 and the rest at
            // 1e-53, and a unit.
            (boundCoefficients[0], boundExponents[0], boundCoefficients[1], boundExponents[1]) =
                multiple(c, relativeBelow / 1000, exponent - 50);
            (boundCoefficients[2], boundExponents[2], boundCoefficients[3], boundExponents[3]) =
                multiple(c, relativeBelow % 1000, exponent - 53);
            (boundCoefficients[4], boundExponents[4]) = (1, exponent);
        } else {
            (boundCoefficients[0], boundExponents[0]) = (fixedBelow, -54);
            (boundCoefficients[1], boundCoefficients[2]) = (0, 0);
        }
        assertTrue(LibExactFloat.sumLte(coefficients, exponents, boundCoefficients, boundExponents), "log10Ratio below");
        if (relative) {
            assertGe(c, 1e48, "48 digits");
        } else {
            assertEq(exponent, -50, "fixed point exponent");
        }
    }

    function checkBothModes(uint256 a, uint256 b, int256 expectedCoefficient, int256 expectedExponent) internal pure {
        checkAgainstBc(a, b, false, expectedCoefficient, expectedExponent);
        checkAgainstBc(a, b, true, expectedCoefficient, expectedExponent);
    }

    function testLog10RatioZero() external pure {
        for (uint256 i = 0; i < 2; i++) {
            (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(1e75, 1e75, i == 0);
            assertEq(signedCoefficient, 0, "coefficient");
            assertEq(exponent, -50, "exponent");
        }
    }

    /// z = 510e70 / 1e76 = 5.1e-4, the proven maximum. Relative, the bound
    /// is under 1e-48 of the log, so the series truncated before z^14 / 15
    /// is outside it.
    function testLog10RatioMaxZ() external pure {
        checkBothModes(
            500255e70, 499745e70, 4429804099477210705399422316980433955478368064312877891379041293560355, -73
        );
        checkBothModes(
            499745e70, 500255e70, -4429804099477210705399422316980433955478368064312877891379041293560355, -73
        );
    }

    /// The 1.001 edges log10Unrounded hands over.
    function testLog10RatioTableEdges() external pure {
        checkBothModes(1001e72, 1e75, 4340774793186406689213877779888660200037751774867729013649473955595637, -73);
        checkBothModes(
            // Positive constant.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256(LOG10_SKIP_BELOW),
            1e76,
            -4340774793186406689213877779888660200037751774867729013649473955595637,
            -73
        );
        checkBothModes(1001e73, 1e76, 4340774793186406689213877779888660200037751774867729013649473955595637, -73);
    }

    /// A difference of one unit keeps 48 digits only when `relative`; at the
    /// fixed point it is under a unit and the bound allows 0.
    function testLog10RatioUnitDifference() external pure {
        checkBothModes(1e75 + 1, 1e75, 4342944819032518276511289189166050822943970058036665661144537831658646, -145);
        checkBothModes(1e76 - 1, 1e76, -4342944819032518276511289189166050822943970058036665661144537831658646, -146);
    }

    function ratio(uint256 a, uint256 b, bool relative) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.log10Ratio(a, b, relative);
    }

    /// #311: z = 5e-5 at every scale. Not relative the result is the same at
    /// every scale.
    function testLog10RatioFixedPointScaleFree() external pure {
        uint256[4] memory bs = [uint256(1e4), 1e40, 1e60, 1e72];
        for (uint256 i = 0; i < 4; i++) {
            uint256 b = bs[i];
            (int256 signedCoefficient, int256 exponent) =
                LibDecimalFloatImplementation.log10Ratio(b + b / 1e4, b, false);
            assertEq(signedCoefficient, 4342727686266963731352758509826813109796277589, "coefficient");
            assertEq(exponent, -50, "exponent");
        }
    }

    /// #311: relative needs a + b of at least 1e50.
    function testLog10RatioRelativeScale() external pure {
        uint256[2] memory bs = [uint256(1e60), 1e72];
        for (uint256 i = 0; i < 2; i++) {
            uint256 b = bs[i];
            checkAgainstBc(
                b + b / 1e4, b, true, 4342727686266963731352758509826813109796277589253077324640421158475901, -74
            );
        }
    }

    /// a + b = 1e50 with the difference maximizing to just below int256.max,
    /// the largest relative quotient the domain admits.
    function testLog10RatioRelativeMinSum() external pure {
        uint256 a = 50002894802230932904885589274625217197696331749616;
        uint256 b = 49997105197769067095114410725374782802303668250384;
        checkAgainstBc(a, b, true, 5028786546000284264695559962415145454590065007477657882759658232905352, -74);
    }

    /// a + b = 1e50 and a - b = 3e45, so z is exactly 3e-5 and z squared is
    /// exactly 9e40 units, on the floor boundary of z squared and three series
    /// terms.
    function testLog10RatioRelativeZOnFloorBoundary() external pure {
        uint256 a = 5.00015e49;
        uint256 b = 4.99985e49;
        checkAgainstBc(a, b, true, 26057668922012410337547610399529953336038179692555075595894572145948150, -75);
    }

    /// a / b = 1 - 1 / 9.9e16 or 1 - 1 / 8.9e18 leaves at most one series
    /// term after 1, and an allowance above the log of under a tenth of a
    /// unit.
    function testLog10RatioRelativeSingleTerm() external pure {
        checkAgainstBc(
            9.9e75 - 1e59, 9.9e75, true, -4386812948517695250954902961368209206711636146525587715889593569661493, -87
        );
        checkAgainstBc(
            8.9e75 - 1e57, 8.9e75, true, -4879713279811818288489072868715327794801115417300392678358697535622065, -89
        );
    }

    /// The guard boundary: a + b = 1e50 - 1 reverts with its inputs.
    function testLog10RatioRelativeSumJustBelowMin() external {
        uint256 a = 50002894802230932904885589274625217197696331749615;
        uint256 b = 49997105197769067095114410725374782802303668250384;
        vm.expectRevert(abi.encodeWithSelector(Log10RatioRelativeSumTooSmall.selector, a, b));
        this.ratio(a, b, true);
    }

    /// #311: below a + b of 1e50 relative reverts with its inputs, where it
    /// reverted `MulDivOverflow` before.
    function testLog10RatioRelativeBelowDomain() external {
        vm.expectRevert(abi.encodeWithSelector(Log10RatioRelativeSumTooSmall.selector, 10001, 10000));
        this.ratio(10001, 10000, true);
    }

    /// a + b = 0 reverts with its inputs rather than dividing by zero.
    function testLog10RatioRelativeZeroSum() external {
        vm.expectRevert(abi.encodeWithSelector(Log10RatioRelativeSumTooSmall.selector, 0, 0));
        this.ratio(0, 0, true);
    }

    /// Every relative a + b below 1e50 reverts with its inputs, including 0,
    /// before any arithmetic can return a value or overflow.
    function testLog10RatioRelativeBelowDomainFuzz(uint256 a, uint256 b) external {
        a = bound(a, 0, 1e50 - 1);
        b = bound(b, 0, 1e50 - 1 - a);
        vm.expectRevert(abi.encodeWithSelector(Log10RatioRelativeSumTooSmall.selector, a, b));
        this.ratio(a, b, true);
    }

    /// The largest relative shortfall found, 7.556e-50 of C against the
    /// bound's 8.03e-50, so a series a few units low leaves the bound.
    /// Reference from `bc -l` at scale 200.
    function testLog10RatioRelativeNearWorst() external pure {
        checkAgainstBc(
            233589395330683330993119953099800888842671881715980,
            233376197779936277454916859050523443841026703458223,
            true,
            3965625204261743005014801431648182388098283587976277313518805519142685,
            -73
        );
    }

    function testLog10RatioMidDomain() external pure {
        checkBothModes(
            3141592653589793238462643383279502884197169399375105820974944592307816e6,
            314e73,
            2202246209189223760482636691221418182974501328043174641783612023602581,
            -73
        );
    }

    /// a = b ± d for b in [1e75, 9.9e75] and z at most 5.1e-4: d / b is at
    /// most 1.02e-3 above b and 1.019e-3 below.
    function inputs(uint256 b, uint256 d, bool below) internal pure returns (uint256, uint256, uint256) {
        b = bound(b, 1e75, 9.9e75);
        d = bound(d, 0, b / 1e6 * (below ? 1019 : 1020));
        return (below ? b - d : b + d, b, d);
    }

    /// log10(1 + d / b) / (d / b) at `ORACLE_ONE`. lnOnePlusOverRatio is
    /// within 50 units of 1e-70, so this is within 24.
    function oracleRatio(uint256 d, uint256 b, bool below) internal pure returns (uint256) {
        return Math.mulDiv(LibExactFloat.lnOnePlusOverRatio(d, b, below), ORACLE_ONE, ORACLE_LN10);
    }

    /// Not relative: the expected log, d / b times the ratio, at 1e-70 is
    /// within 24 d / b + 1 of the truth, under 2.
    function testLog10RatioFixedPointOracle(uint256 seedB, uint256 seedD, bool below) external pure {
        (uint256 a, uint256 b, uint256 d) = inputs(seedB, seedD, below);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(a, b, false);
        assertEq(exponent, -50, "exponent");
        assertTrue(below ? signedCoefficient <= 0 : signedCoefficient >= 0, "sign");
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 actual = abs(signedCoefficient) * 1e20;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expected = int256(Math.mulDiv(d, oracleRatio(d, b, below), b));
        assertLe(abs(actual - expected), 1.0036e20 + 2, "fixed point error");
    }

    /// Relative: d is maximized to D = d 10^k in [1e75, 1e77) and the log is
    /// D / b times the ratio in units of 10^(exponent - 20). D / b is below
    /// 100, so the expected value is within 2401 of the truth.
    function testLog10RatioRelativeOracle(uint256 seedB, uint256 seedD, bool below) external pure {
        (uint256 a, uint256 b, uint256 d) = inputs(seedB, seedD, below);
        d = d == 0 ? 1 : d;
        a = below ? b - d : b + d;
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(a, b, true);
        assertTrue(below ? signedCoefficient < 0 : signedCoefficient > 0, "sign");
        assertGe(abs(signedCoefficient), 1e48, "48 digits");
        int256 shift = -50 - exponent;
        assertGe(shift, 0, "shift");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 maximized = d * 10 ** uint256(shift);
        assertGe(maximized, 1e75, "maximized low");
        assertLt(maximized, 1e77, "maximized high");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 actual = uint256(abs(signedCoefficient)) * 1e20;
        uint256 expected = Math.mulDiv(maximized, oracleRatio(d, b, below), b);
        uint256 error = actual > expected ? actual - expected : expected - actual;
        // forge-lint: disable-next-line(unsafe-typecast)
        assertLe(error, Math.mulDiv(actual, 803, 1e52, Math.Rounding.Ceil) + 1e20 + 2401, "relative error");
    }

    /// |C 10^g - D / b times the ratio at 10^-g| against the bound, where g
    /// shrinks from 20 as C grows to keep C 10^g below 1e75. The expected
    /// value is within 24 D / (b 10^(20 - g)) + 1 of the truth.
    function checkRelativeError(uint256 c, uint256 maximized, uint256 d, uint256 b, bool below) internal pure {
        uint256 digits = Math.log10(c) + 1;
        uint256 g = digits <= 55 ? 20 : digits >= 75 ? 0 : 75 - digits;
        uint256 denominator = b * 10 ** (20 - g);
        uint256 actual = c * 10 ** g;
        uint256 expected = Math.mulDiv(maximized, oracleRatio(d, b, below), denominator);
        uint256 error = actual > expected ? actual - expected : expected - actual;
        assertLe(
            error,
            Math.mulDiv(actual, 803, 1e52, Math.Rounding.Ceil) + 10 ** g + Math.mulDiv(maximized, 24, denominator) + 1,
            "relative error"
        );
    }

    /// Relative at every scale with a + b of at least 1e50: never reverts,
    /// keeps 48 digits and is within C 8.03e-50 + 1 units of its exponent. C
    /// reaches 5.8e76 near a + b = 1e50.
    function testLog10RatioRelativeOracleAnyScale(uint256 seedB, uint256 seedD, uint256 seedP, bool below)
        external
        pure
    {
        uint256 p = bound(seedP, 49, 75);
        uint256 b = bound(seedB, p == 49 ? 5.0026e49 : 10 ** p, p == 75 ? 9.9e75 : 10 ** (p + 1) - 1);
        uint256 d = bound(seedD, 1, b / 1e6 * (below ? 1019 : 1020));
        uint256 a = below ? b - d : b + d;
        assertGe(a + b, 1e50, "domain");
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(a, b, true);
        assertTrue(below ? signedCoefficient < 0 : signedCoefficient > 0, "sign");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 c = uint256(abs(signedCoefficient));
        assertGe(c, 1e48, "48 digits");
        int256 shift = -50 - exponent;
        assertGe(shift, 0, "shift");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 maximized = d * 10 ** uint256(shift);
        assertGe(maximized, 1e75, "maximized low");
        assertLt(maximized, 1e77, "maximized high");
        checkRelativeError(c, maximized, d, b, below);
    }

    /// #422: a + b = 2e50 and a - b = 2 LOG10_RATIO_Z_MAX make z exactly the
    /// largest proven, where the eighth power of z^2 is under a unit and the
    /// fixed point log is within 1 + 0.8686 8.0815 z, under 1.0053 units, and
    /// the relative log under C 8.082e-50 plus a unit below. One more
    /// unit of z reverts in both modes.
    function testLog10RatioZMaxBoundary() external {
        uint256 a = 1e50 + LOG10_RATIO_Z_MAX;
        uint256 b = 1e50 - LOG10_RATIO_Z_MAX;
        int256 expected = 6513499563422593298128000933088432572485617893851531354484903266260892;
        checkAgainstBcWithin(a, b, false, expected, -73, 10053, 8082);
        checkAgainstBcWithin(a, b, true, expected, -73, 10053, 8082);
        checkAgainstBcWithin(b, a, false, -expected, -73, 10053, 8082);
        checkAgainstBcWithin(b, a, true, -expected, -73, 10053, 8082);
        for (uint256 i = 0; i < 2; i++) {
            vm.expectRevert(abi.encodeWithSelector(Log10RatioOutOfRange.selector, a + 1, b - 1));
            this.ratio(a + 1, b - 1, i == 0);
            vm.expectRevert(abi.encodeWithSelector(Log10RatioOutOfRange.selector, b - 1, a + 1));
            this.ratio(b - 1, a + 1, i == 0);
        }
    }

    /// #422: a / b = 9 had z = 0.8 and a log 83 units below, and (1e76, 1)
    /// ran out of gas. Both revert with their inputs, as does a zero b.
    function testLog10RatioOutOfRange() external {
        uint256[2][4] memory cases = [[uint256(9e75), 1e75], [uint256(1e76), 1], [uint256(1e75), 0], [uint256(0), 1e75]];
        for (uint256 i = 0; i < cases.length; i++) {
            for (uint256 j = 0; j < 2; j++) {
                vm.expectRevert(abi.encodeWithSelector(Log10RatioOutOfRange.selector, cases[i][0], cases[i][1]));
                this.ratio(cases[i][0], cases[i][1], j == 0);
            }
        }
    }

    /// #422: a + b = 0 not relative reverts with its inputs rather than
    /// dividing by zero.
    function testLog10RatioFixedPointZeroSum() external {
        vm.expectRevert(abi.encodeWithSelector(Log10RatioOutOfRange.selector, 0, 0));
        this.ratio(0, 0, false);
    }

    /// #422: a + b = uint256.max is the largest sum, and one more wraps past
    /// 2^256 and reverts with its inputs where it panicked before.
    function testLog10RatioSumBoundary() external {
        uint256 half = 2 ** 255;
        int256 expected = 7501280696527793531715342934058121490318235872468032620580942125833437;
        checkBothModes(half, half - 1, expected, -147);
        checkBothModes(half - 1, half, -expected, -147);
        for (uint256 i = 0; i < 2; i++) {
            vm.expectRevert(abi.encodeWithSelector(Log10RatioOutOfRange.selector, half, half));
            this.ratio(half, half, i == 0);
            vm.expectRevert(abi.encodeWithSelector(Log10RatioOutOfRange.selector, type(uint256).max, 1));
            this.ratio(type(uint256).max, 1, i == 0);
        }
    }

    /// Every a + b past 2^256 reverts with its inputs.
    function testLog10RatioSumOverflowFuzz(uint256 a, uint256 b, bool relative) external {
        a = bound(a, 1, type(uint256).max);
        b = bound(b, type(uint256).max - a + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Log10RatioOutOfRange.selector, a, b));
        this.ratio(a, b, relative);
    }

    /// Every z past LOG10_RATIO_Z_MAX at 1e-50, floored, reverts with its
    /// inputs.
    function testLog10RatioZOutOfRangeFuzz(uint256 a, uint256 b, bool relative) external {
        b = bound(b, 1e50, type(uint256).max / 2);
        a = bound(a, 0, type(uint256).max - b);
        uint256 difference = a < b ? b - a : a - b;
        vm.assume(Math.mulDiv(difference, 1e50, a + b) > LOG10_RATIO_Z_MAX);
        vm.expectRevert(abi.encodeWithSelector(Log10RatioOutOfRange.selector, a, b));
        this.ratio(a, b, relative);
    }
}
