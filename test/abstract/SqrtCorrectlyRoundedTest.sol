// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibExactFloat} from "../lib/LibExactFloat.sol";

/// @title SqrtCorrectlyRoundedTest
/// @notice The correct-rounding oracle for square roots, shared by the
/// implementation and the Float sqrt tests.
abstract contract SqrtCorrectlyRoundedTest is Test {
    /// @notice Asserts the root `rootCoefficient × 10^rootExponent` of
    /// `signedCoefficient × 10^exponent` is correctly rounded at 41 digits.
    /// With the root as `c × 10^e`, `c` in `[1e40, 1e41)`, that holds exactly
    /// when `(c - 1/2)^2 10^2e < a < (c + 1/2)^2 10^2e`, except that at
    /// `c = 1e40` the lower neighbour is `1e41 - 1` one exponent down, so the
    /// lower midpoint is a twentieth of a unit below. With `a = A 10^f`, `A`
    /// in `[1e75, 1e76)`, both compare `4 A 10^(f - 2e)` against
    /// `(2c ± 1)^2`.
    /// @param signedCoefficient The radicand's coefficient, in `[1, 1e76)`.
    /// @param exponent The radicand's exponent.
    /// @param rootCoefficient The root's coefficient, positive.
    /// @param rootExponent The root's exponent.
    function assertSqrtCorrectlyRounded(
        int256 signedCoefficient,
        int256 exponent,
        int256 rootCoefficient,
        int256 rootExponent
    ) internal pure {
        assertGt(signedCoefficient, 0, "radicand positive");
        assertLt(signedCoefficient, 1e76, "radicand digits");
        assertGt(rootCoefficient, 0, "root positive");
        while (rootCoefficient < 1e40) {
            rootCoefficient *= 10;
            rootExponent -= 1;
        }
        while (rootCoefficient >= 1e41) {
            assertEq(rootCoefficient % 10, 0, "root digits");
            rootCoefficient /= 10;
            rootExponent += 1;
        }
        int256 radicandShift = 0;
        while (signedCoefficient < 1e75) {
            signedCoefficient *= 10;
            radicandShift += 1;
        }
        // `f - 2e` as `exponent - e - e - shift`: each step stays within
        // int256 for any exponent, as the root's exponent is near half the
        // radicand's.
        int256 scale = exponent - rootExponent - rootExponent - radicandShift;
        assertTrue(scale >= 4 && scale <= 7, "root scale");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 quadrupled = uint256(signedCoefficient) * 4;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 doubledRoot = uint256(2 * rootCoefficient);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertFalse(LibExactFloat.pastMidpoint(quadrupled, uint256(scale), doubledRoot + 1), "above upper midpoint");
        if (rootCoefficient == 1e40) {
            assertTrue(
                // forge-lint: disable-next-line(unsafe-typecast)
                LibExactFloat.pastMidpoint(quadrupled, uint256(scale + 2), 2e41 - 1),
                "below lower midpoint"
            );
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            assertTrue(LibExactFloat.pastMidpoint(quadrupled, uint256(scale), doubledRoot - 1), "below lower midpoint");
        }
    }
}
