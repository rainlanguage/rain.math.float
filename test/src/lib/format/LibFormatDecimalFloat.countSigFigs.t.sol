// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";

/// @title LibFormatDecimalFloatCountSigFigs
contract LibFormatDecimalFloatCountSigFigs is Test {
    function checkCountSigFigs(int256 signedCoefficient, int256 exponent, uint256 expected) internal pure {
        uint256 actual = LibFormatDecimalFloat.countSigFigs(signedCoefficient, exponent);
        assertEq(actual, expected, "Unexpected significant figures count");
    }

    function testCountSigFigsExamples() external pure {
        checkCountSigFigs(0, 0, 1);

        // 1 = 1
        checkCountSigFigs(1, 0, 1);
        checkCountSigFigs(10, -1, 1);

        // -1 = 1
        checkCountSigFigs(-1, 0, 1);
        checkCountSigFigs(-10, -1, 1);

        // 10 = 2
        checkCountSigFigs(10, 0, 2);
        checkCountSigFigs(100, -1, 2);

        // -10 = 2
        checkCountSigFigs(-10, 0, 2);
        checkCountSigFigs(-100, -1, 2);

        // 0.1 = 1
        checkCountSigFigs(1, -1, 1);
        checkCountSigFigs(10, -2, 1);

        // -0.1 = 1
        checkCountSigFigs(-1, -1, 1);
        checkCountSigFigs(-10, -2, 1);

        // 0.01 = 2
        checkCountSigFigs(1, -2, 2);
        checkCountSigFigs(10, -3, 2);

        // -0.01 = 2
        checkCountSigFigs(-1, -2, 2);
        checkCountSigFigs(-10, -3, 2);

        // 0.001 = 3
        checkCountSigFigs(1, -3, 3);
        checkCountSigFigs(10, -4, 3);

        // -0.001 = 3
        checkCountSigFigs(-1, -3, 3);
        checkCountSigFigs(-10, -4, 3);

        // 1.1 = 2
        checkCountSigFigs(11, -1, 2);
        checkCountSigFigs(110, -2, 2);

        // -1.1 = 2
        checkCountSigFigs(-11, -1, 2);
        checkCountSigFigs(-110, -2, 2);

        // 1.01 = 3
        checkCountSigFigs(101, -2, 3);
        checkCountSigFigs(1010, -3, 3);

        // -1.01 = 3
        checkCountSigFigs(-101, -2, 3);
        checkCountSigFigs(-1010, -3, 3);

        // 10.1 = 3
        checkCountSigFigs(101, -1, 3);
        checkCountSigFigs(1010, -2, 3);

        // -10.1 = 3
        checkCountSigFigs(-101, -1, 3);
        checkCountSigFigs(-1010, -2, 3);

        // 10.01 = 4
        checkCountSigFigs(1001, -2, 4);
        checkCountSigFigs(10010, -3, 4);

        // -10.01 = 4
        checkCountSigFigs(-1001, -2, 4);
        checkCountSigFigs(-10010, -3, 4);

        // internal zeros are significant
        checkCountSigFigs(100100, 0, 6);
        checkCountSigFigs(-100100, 0, 6);

        // trailing zeros without decimal are significant
        checkCountSigFigs(100, 0, 3);
        checkCountSigFigs(1000, 0, 4);

        // trailing zeros after decimal are not significant
        // 1.00 and 0.00100
        checkCountSigFigs(100, -2, 1);
        checkCountSigFigs(100, -5, 3);
    }

    function testCountSigFigsZero(int256 exponent) external pure {
        checkCountSigFigs(0, exponent, 1);
    }

    function testCountSigFigsOne(int256 exponent) external pure {
        exponent = bound(exponent, -76, 0);
        int256 one = int256(10 ** uint256(-exponent));
        checkCountSigFigs(one, exponent, 1);
        checkCountSigFigs(-one, exponent, 1);
    }
}
