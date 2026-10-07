// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTranscendentalOracle, ORACLE_ONE, ORACLE_LN10} from "../../../lib/LibTranscendentalOracle.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {Log10RatioRelativeSumTooSmall} from "src/error/ErrDecimalFloat.sol";

/// Bounds from the `log10Ratio` NatSpec: 1.005 units of 1e-50 for a
/// coefficient at that scale, or C / 1e49 + 2 units of its exponent when
/// `relative`, for z = |a - b| / (a + b) at most 5.1e-4.
contract LibDecimalFloatImplementationLog10RatioTest is Test {
    function abs(int256 value) internal pure returns (int256) {
        return value < 0 ? -value : value;
    }

    /// |log10Ratio - expected| against the proven bound, for an expected
    /// value truncated to 70 significant digits by `bc -l`, so plus a unit
    /// in its last place.
    function checkAgainstBc(uint256 a, uint256 b, bool relative, int256 expectedCoefficient, int256 expectedExponent)
        internal
        pure
    {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(a, b, relative);
        assertTrue(expectedCoefficient < 0 ? signedCoefficient <= 0 : signedCoefficient >= 0, "sign");
        (int256 errorCoefficient, int256 errorExponent) =
            LibDecimalFloatImplementation.sub(signedCoefficient, exponent, expectedCoefficient, expectedExponent);
        (int256 boundCoefficient, int256 boundExponent) =
            relative ? (abs(signedCoefficient) + 2e49, exponent - 49) : (int256(1005), int256(-53));
        (boundCoefficient, boundExponent) =
            LibDecimalFloatImplementation.add(boundCoefficient, boundExponent, 1, expectedExponent);
        assertTrue(
            LibDecimalFloatImplementation.lte(abs(errorCoefficient), errorExponent, boundCoefficient, boundExponent),
            "log10Ratio error"
        );
        if (relative) {
            assertGe(abs(signedCoefficient), 1e48, "48 digits");
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
        int256[2] memory coefficients = [
            int256(434272768626696373135275850982681310979627758925298735063246837658),
            434272768626696373135275850982681310979627758925298735
        ];
        int256[2] memory exponents = [int256(-70), -58];
        for (uint256 i = 0; i < 2; i++) {
            uint256 b = bs[i];
            checkAgainstBc(
                b + b / 1e4, b, true, 4342727686266963731352758509826813109796277589253077324640421158475901, -74
            );
            (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(b + b / 1e4, b, true);
            assertEq(signedCoefficient, coefficients[i], "coefficient");
            assertEq(exponent, exponents[i], "exponent");
        }
    }

    /// a + b = 1e50 with the difference maximizing to just below int256.max,
    /// the largest relative quotient the domain admits.
    function testLog10RatioRelativeMinSum() external pure {
        uint256 a = 50002894802230932904885589274625217197696331749616;
        uint256 b = 49997105197769067095114410725374782802303668250384;
        checkAgainstBc(a, b, true, 5028786546000284264695559962415145454590065007477657882759658232905352, -74);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(a, b, true);
        assertEq(
            signedCoefficient,
            50287865460002842646955599624151454545900650074775565315544486988760780321019,
            "coefficient"
        );
        assertEq(exponent, -81, "exponent");
    }

    /// #311: below a + b of 1e50 relative reverts with its inputs, where it
    /// reverted `MulDivOverflow` before.
    function testLog10RatioRelativeBelowDomain() external {
        vm.expectRevert(abi.encodeWithSelector(Log10RatioRelativeSumTooSmall.selector, 10001, 10000));
        this.ratio(10001, 10000, true);
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
}
