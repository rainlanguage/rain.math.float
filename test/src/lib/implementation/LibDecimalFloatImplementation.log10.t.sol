// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LogTest, console2} from "../../../abstract/LogTest.sol";

contract LibDecimalFloatImplementationLog10Test is LogTest {
    function checkLog10(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        address tables = logTables();
        uint256 aGas = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10(tables, signedCoefficient, exponent);
        uint256 bGas = gasleft();
        console2.log("%d %d Gas used: %d", uint256(signedCoefficient), uint256(exponent), aGas - bGas);
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
