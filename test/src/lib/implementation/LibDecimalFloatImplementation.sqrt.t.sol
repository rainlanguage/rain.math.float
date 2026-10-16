// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {SqrtOutOfRange} from "../../../../src/error/ErrDecimalFloat.sol";
import {SqrtCorrectlyRoundedTest} from "../../../abstract/SqrtCorrectlyRoundedTest.sol";

contract LibDecimalFloatImplementationSqrtTest is SqrtCorrectlyRoundedTest {
    /// The implementation returns its root normalized to 41 digits, so on top
    /// of correct rounding the root is in `[1e40, 1e41]`.
    function assertCorrectlyRounded(int256 signedCoefficient, int256 exponent, int256 root, int256 rootExponent)
        internal
        pure
    {
        assertGe(root, 1e40, "root low");
        assertLe(root, 1e41, "root high");
        assertSqrtCorrectlyRounded(signedCoefficient, exponent, root, rootExponent);
    }

    function testSqrtCorrectlyRounded(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, 1e76 - 1);
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        assertCorrectlyRounded(signedCoefficient, exponent, root, rootExponent);
    }

    /// The odd exponent extremes. Each is exponent 1 shifted by an even
    /// exponent - 1.
    function testSqrtExponentEnds(int256 signedCoefficient, bool high) external pure {
        signedCoefficient = bound(signedCoefficient, 1, 1e76 - 1);
        int256 exponent = high ? type(int256).max : type(int256).min + 1;
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        (int256 shifted, int256 shiftedExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, 1);
        assertEq(root, shifted, "root");
        assertEq(rootExponent - shiftedExponent, (exponent - 1) / 2, "exponent");
    }

    /// A = floor((2c + 1)^2 / 4e16) has a root just below the midpoint
    /// (c + 1/2) 1e-8 and A + 1 one just above it, so 100^k A rounds to
    /// c 10^(k - 8) and 100^k (A + 1) to (c + 1) 10^(k - 8), both exactly.
    function checkMidpoint(uint256 c, int256 k) internal pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 a = int256(Math.mulDiv(2 * c + 1, 2 * c + 1, 4e16));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedC = int256(c);
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(a, 2 * k);
        assertEq(root, signedC, "below midpoint");
        assertEq(rootExponent, k - 8, "below midpoint exponent");
        (root, rootExponent) = LibDecimalFloatImplementation.sqrt(a + 1, 2 * k);
        assertEq(root, signedC + 1, "above midpoint");
        assertEq(rootExponent, k - 8, "above midpoint exponent");
    }

    function testSqrtMidpoint(uint256 c, int256 k) external pure {
        checkMidpoint(bound(c, 1e40, 1e41 - 1), bound(k, -1e70, 1e70));
    }

    /// The decade ends, and either side of sqrt 10 1e40, where the scaling
    /// switches between an odd and an even exponent.
    function testSqrtMidpointEnds() external pure {
        checkMidpoint(1e40, 0);
        checkMidpoint(1e40, -1);
        checkMidpoint(1e41 - 1, 0);
        checkMidpoint(1e41 - 1, 7);
        checkMidpoint(31622776601683793319988935444327185337195, 0);
        checkMidpoint(31622776601683793319988935444327185337196, 0);
    }

    /// N = r (r + 1) is a quarter below the midpoint (r + 1/2)^2, so its root
    /// rounds down to r, wherever Newton lands. r = k 10^5 makes N a 76-digit
    /// coefficient times 1e5, the odd scale, and r = k 10^6 one times 1e6, the
    /// even scale. r = k 10^s - 1 puts the factor of 10^s on r + 1 instead.
    function testSqrtProductOfNeighbours(uint256 k, bool even, bool below) external pure {
        uint256 s = even ? 1e6 : 1e5;
        k = even
            ? bound(k, 31622776601683793319988935444327186, 1e35 - 1)
            : bound(k, 1e35 + 1, 316227766016837933199889354443271853);
        uint256 r = below ? k * s - 1 : k * s;
        uint256 c = Math.mulDiv(r, r + 1, s);
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(int256(c), even ? int256(0) : int256(1));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(root, int256(r), "root");
        assertEq(rootExponent, even ? int256(-3) : int256(-2), "exponent");
    }

    /// r^2 10^2k has root r 10^k exactly, for r below 1e38 so r^2 is a
    /// coefficient below 1e76.
    function testSqrtExactSquares(uint256 r, int256 k) external pure {
        r = bound(r, 1, 1e38 - 1);
        k = bound(k, -1e70, 1e70);
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(int256(r * r), 2 * k);
        while (rootExponent < k) {
            assertEq(root % 10, 0, "trailing digits");
            root /= 10;
            rootExponent += 1;
        }
        assertEq(rootExponent, k, "exponent");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(root, int256(r), "root");
    }

    /// Values from `bc`, scale 100: sqrt(2), sqrt(20), sqrt(1e75 - 1), and
    /// sqrt(1e76 - 1) rounded to 41 digits.
    function testSqrtReference() external pure {
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(2, 0);
        assertEq(root, 14142135623730950488016887242096980785697);
        assertEq(rootExponent, -40);
        (root, rootExponent) = LibDecimalFloatImplementation.sqrt(20, 0);
        assertEq(root, 44721359549995793928183473374625524708812);
        assertEq(rootExponent, -40);
        (root, rootExponent) = LibDecimalFloatImplementation.sqrt(1e75 - 1, 0);
        assertEq(root, 31622776601683793319988935444327185337196);
        assertEq(rootExponent, -3);
        (root, rootExponent) = LibDecimalFloatImplementation.sqrt(1e76 - 1, 0);
        assertEq(root, 1e41);
        assertEq(rootExponent, -3);
    }

    function sqrtExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
    }

    /// #422: sqrt(-4, 0) was about 0.2296. A coefficient outside (0, 1e76)
    /// reverts with its input.
    function testSqrtCoefficientOutOfRange() external {
        int256[6] memory coefficients = [int256(-4), -1, 0, type(int256).min, 1e76, type(int256).max];
        for (uint256 i = 0; i < coefficients.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(SqrtOutOfRange.selector, coefficients[i], int256(7)));
            this.sqrtExternal(coefficients[i], 7);
        }
    }

    function testSqrtCoefficientOutOfRangeFuzz(int256 signedCoefficient, int256 exponent, bool high) external {
        signedCoefficient =
            high ? bound(signedCoefficient, 1e76, type(int256).max) : bound(signedCoefficient, type(int256).min, 0);
        vm.expectRevert(abi.encodeWithSelector(SqrtOutOfRange.selector, signedCoefficient, exponent));
        this.sqrtExternal(signedCoefficient, exponent);
    }

    /// The coefficient ends, 1 and 1e76 - 1, are correctly rounded.
    function testSqrtCoefficientEnds() external pure {
        int256[2] memory coefficients = [int256(1), 1e76 - 1];
        for (uint256 i = 0; i < coefficients.length; i++) {
            (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(coefficients[i], 0);
            assertCorrectlyRounded(coefficients[i], 0, root, rootExponent);
        }
    }

    /// #451: c 10^e is taken as N 10^(e - t - s), C = c 10^t in [1e75, 1e76)
    /// and s 5 or 6 to make e - t - s even. Within 81 of int256.min that
    /// exponent passes it, while the root's, about half of it, does not. The
    /// root is correctly rounded there, and as int256.min is even,
    /// sqrt(c 10^(min + k)) is sqrt(c 10^k) 10^(min / 2) exactly.
    function testSqrtExponentFloor(int256 signedCoefficient, int256 room) external pure {
        signedCoefficient = bound(signedCoefficient, 1, 1e76 - 1);
        room = bound(room, 0, 200);
        int256 exponent = type(int256).min + room;
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        assertCorrectlyRounded(signedCoefficient, exponent, root, rootExponent);
        (int256 shifted, int256 shiftedExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, room);
        assertEq(root, shifted, "root");
        assertEq(rootExponent, shiftedExponent + type(int256).min / 2, "exponent");
    }

    /// Values from exact maths and `bc`: 10^(min + 2k) has root 1e40
    /// 10^(min / 2 + k - 40), and 10^(min + 2k + 1) has root sqrt(10) 1e40
    /// 10^(min / 2 + k - 40), sqrt(10) 1e40 being
    /// 31622776601683793319988935444327185337195.55 to scale 60. c = 1 has
    /// t = 75 and c = 1e75 has t = 0, either side of where e - t - s passes
    /// int256.min.
    function testSqrtExponentFloorEnds() external pure {
        int256 min = type(int256).min;
        int256 rootTen = 31622776601683793319988935444327185337196;
        int256[4][6] memory cases = [
            [int256(1), min + 80, 1e40, min / 2],
            [int256(1e75), min + 5, 1e40, min / 2],
            [int256(1), min + 79, rootTen, min / 2 - 1],
            [int256(1e75), min + 4, rootTen, min / 2 - 1],
            [int256(1), min, 1e40, min / 2 - 40],
            [int256(1e75), min, rootTen, min / 2 - 3]
        ];
        for (uint256 i = 0; i < cases.length; i++) {
            (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(cases[i][0], cases[i][1]);
            assertEq(root, cases[i][2], "root");
            assertEq(rootExponent, cases[i][3], "exponent");
        }
    }
}
