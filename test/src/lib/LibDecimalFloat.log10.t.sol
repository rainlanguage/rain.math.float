// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "../../abstract/LogTest.sol";

import {console} from "forge-std/Test.sol";

contract LibDecimalFloatLog10Test is LogTest {
    using LibDecimalFloat for Float;

    function log10External(int256 signedCoefficient, int256 exponent) external returns (int256, int256) {
        address tables = logTables();
        return LibDecimalFloat.log10(tables, signedCoefficient, exponent);
    }

    function log10External(Float float) external returns (Float) {
        address tables = logTables();
        return LibDecimalFloat.log10(tables, float);
    }
    /// Stack and mem are the same.

    function testLog10Mem(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        try this.log10External(signedCoefficient, exponent) returns (
            int256 signedCoefficientResult, int256 exponentResult
        ) {
            Float floatLog10 = this.log10External(float);
            (int256 signedCoefficientResultUnpacked, int256 exponentResultUnpacked) = floatLog10.unpack();
            assertEq(signedCoefficientResultUnpacked, signedCoefficientResult);
            assertEq(exponentResultUnpacked, exponentResult);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.log10External(float);
        }
    }

    function checkLog10(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        address tables = logTables();
        uint256 a = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloat.log10(tables, signedCoefficient, exponent);
        uint256 b = gasleft();
        console.log("%d %d Gas used: %d", uint256(signedCoefficient), uint256(exponent), a - b);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    function testExactLogs() external {
        checkLog10(1, 0, 0, 0);
        checkLog10(10, 0, 1, 0);
        checkLog10(100, 0, 2, 0);
        checkLog10(1000, 0, 3, 0);
        checkLog10(10000, 0, 4, 0);
        checkLog10(1e37, -37, 0, 0);
    }

    function testExactLookups() external {
        checkLog10(1001, 0, 3.0004e41, -41);
        checkLog10(100.1e1, -1, 2.0004e41, -41);
        checkLog10(10.01e2, -2, 1.0004e41, -41);
        checkLog10(1.001e3, -3, 0.0004e38, -38);

        checkLog10(10.02e2, -2, 1.0009e41, -41);
        checkLog10(10.99e2, -2, 1.0411e39, -39);

        checkLog10(6566, 0, 3.8173e38, -38);
    }

    function testInterpolatedLookups() external {
        checkLog10(10.015e3, -3, 1.00065e41, -41);
    }

    function testSub1() external {
        checkLog10(0.1001e4, -4, -0.9996e38, -38);
    }
}
