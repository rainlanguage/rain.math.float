// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibFormatDecimalFloatPr321} from "./LibFormatDecimalFloatPr321.sol";
import {LibExactFloat} from "./LibExactFloat.sol";

/// The frozen format copy's `maximize`, which formatting observes only through
/// the digits it prints, against the exact reference.
contract LibFormatDecimalFloatPr321Test is Test {
    /// The copied `maximize` against the digit-at-a-time exact reference, at
    /// zero, at 1e74 where its fast steps stop and the loop starts, at both
    /// signs of the `int256.max / 10` threshold, and at the int256 exponent
    /// floor where the shift wraps into a shortfall.
    function testFrozenMaximizeOracle() external pure {
        int256 tenLimit = type(int256).max / 10;
        int256[9] memory coefficients =
            [int256(0), 1, -1, 1e74, -1e74, tenLimit, tenLimit + 1, -tenLimit, -tenLimit - 1];
        int256[2] memory exponents = [int256(0), type(int256).min];
        for (uint256 i = 0; i < coefficients.length; i++) {
            for (uint256 j = 0; j < exponents.length; j++) {
                (int256 expectedCoefficient, int256 expectedExponent, int256 expectedShortfall) =
                    LibExactFloat.maximize(coefficients[i], exponents[j]);
                (int256 coefficient, int256 exponent, int256 shortfall) =
                    LibFormatDecimalFloatPr321.maximize(coefficients[i], exponents[j]);
                assertEq(coefficient, expectedCoefficient);
                assertEq(exponent, expectedExponent);
                assertEq(shortfall, expectedShortfall);
            }
        }
    }
}
