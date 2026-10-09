// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTranscendentalOracle, ORACLE_ONE, ORACLE_LN10} from "../../../lib/LibTranscendentalOracle.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {Log10RatioRelativeSumTooSmall} from "src/error/ErrDecimalFloat.sol";

/// Bounds from the `log10Ratio` NatSpec, for z = |a - b| / (a + b) at most
/// 5.1e-4: the magnitude is at most 1.3e-51 relative above the true log, and
/// below it by under 1.0043 units of 1e-50 for a coefficient at that scale,
/// or by C 9.6e-50 plus a unit of its exponent when `relative`.
contract LibDecimalFloatImplementationLog10RatioTest is Test {
    function abs(int256 value) internal pure returns (int256) {
        return value < 0 ? -value : value;
    }

    /// log10Ratio against the proven bounds, for an expected value truncated
    /// toward zero to 70 significant digits by `bc -l`, so below the true
    /// magnitude by under a unit in its last place.
    function checkAgainstBc(uint256 a, uint256 b, bool relative, int256 expectedCoefficient, int256 expectedExponent)
        internal
        pure
    {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(a, b, relative);
        assertTrue(expectedCoefficient < 0 ? signedCoefficient <= 0 : signedCoefficient >= 0, "sign");
        int256 c = abs(signedCoefficient);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 above = int256(Math.mulDiv(uint256(c), 13, 100, Math.Rounding.Ceil));
        (int256 aboveCoefficient, int256 aboveExponent) =
            LibDecimalFloatImplementation.add(above, exponent - 50, 1, expectedExponent);
        (int256 belowCoefficient, int256 belowExponent) = (int256(10043), int256(-54));
        if (relative) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 below = int256(Math.mulDiv(uint256(c), 96, 100, Math.Rounding.Ceil));
            (belowCoefficient, belowExponent) = LibDecimalFloatImplementation.add(below, exponent - 49, 1, exponent);
        }
        (int256 errorCoefficient, int256 errorExponent) =
            LibDecimalFloatImplementation.sub(c, exponent, abs(expectedCoefficient), expectedExponent);
        assertTrue(
            LibDecimalFloatImplementation.lte(errorCoefficient, errorExponent, aboveCoefficient, aboveExponent),
            "log10Ratio above"
        );
        assertTrue(
            LibDecimalFloatImplementation.lte(-errorCoefficient, errorExponent, belowCoefficient, belowExponent),
            "log10Ratio below"
        );
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
        checkBothModes(9999e72, 1e76, -4343161980751038455604402380722667375072594570258433791106376134065183, -74);
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
        return Math.mulDiv(LibTranscendentalOracle.lnOnePlusOverRatio(d, b, below), ORACLE_ONE, ORACLE_LN10);
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
        assertLe(abs(actual - expected), 1.005e20 + 2, "fixed point error");
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
        assertLe(error, uint256(abs(signedCoefficient)) / 1e29 + 1 + 2e20 + 2401, "relative error");
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
        assertLe(error, actual / 1e49 + 2 * 10 ** g + Math.mulDiv(maximized, 24, denominator) + 1, "relative error");
    }

    /// Relative at every scale with a + b of at least 1e50: never reverts,
    /// keeps 48 digits and is within C / 1e49 + 2 units of its exponent. C
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
}
