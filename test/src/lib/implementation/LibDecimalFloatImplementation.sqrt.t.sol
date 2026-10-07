// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatSqrtVariants} from "test/lib/LibDecimalFloatSqrtVariants.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

contract LibDecimalFloatImplementationSqrtTest is Test {
    /// x 10^d > m^2 in 512 bits.
    function past(uint256 x, uint256 d, uint256 m) internal pure returns (bool) {
        (uint256 xHigh, uint256 xLow) = LibDecimalFloatImplementation.mul512(x, 10 ** d);
        (uint256 mHigh, uint256 mLow) = LibDecimalFloatImplementation.mul512(m, m);
        return xHigh > mHigh || (xHigh == mHigh && xLow > mLow);
    }

    /// The root r 10^e of c 10^f, r in [1e40, 1e41], is correctly rounded
    /// exactly when (r - 1/2)^2 10^2e < c 10^f < (r + 1/2)^2 10^2e. With c
    /// scaled into [1e75, 1e76) both compare 4c 10^(f - 2e) against
    /// (2r +- 1)^2.
    function assertCorrectlyRounded(int256 signedCoefficient, int256 exponent, int256 root, int256 rootExponent)
        internal
        pure
    {
        assertGe(root, 1e40, "root low");
        assertLe(root, 1e41, "root high");
        while (signedCoefficient < 1e75) {
            signedCoefficient *= 10;
            exponent -= 1;
        }
        int256 d = exponent - 2 * rootExponent;
        assertTrue(d >= 4 && d <= 7, "root scale");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 x = uint256(signedCoefficient) * 4;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 m = uint256(2 * root);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertFalse(past(x, uint256(d), m + 1), "above upper midpoint");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertTrue(past(x, uint256(d), m - 1), "below lower midpoint");
    }

    function testSqrtCorrectlyRounded(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, 1e76 - 1);
        exponent = bound(exponent, -1e70, 1e70);
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        assertCorrectlyRounded(signedCoefficient, exponent, root, rootExponent);
    }

    /// The exponent extremes the scaling and halving pass through. Both are
    /// odd, so each is exponent 1 shifted by an even exponent - 1.
    function testSqrtExponentEnds(int256 signedCoefficient, bool high) external pure {
        signedCoefficient = bound(signedCoefficient, 1, 1e76 - 1);
        int256 exponent = high ? type(int256).max : type(int256).min + 81;
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

    /// Byte-identical to the integer sqrt of #309's branch, which compares the
    /// residual in 512 bits.
    function testSqrtBaseEquivalence(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, 1e76 - 1);
        exponent = bound(exponent, type(int256).min + 81, type(int256).max);
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        (int256 baseRoot, int256 baseExponent) = LibDecimalFloatSqrtVariants.sqrtBase(signedCoefficient, exponent);
        assertEq(root, baseRoot, "root");
        assertEq(rootExponent, baseExponent, "exponent");
    }

    function testSqrtBaseEquivalencePacked(int224 signedCoefficient, int32 exponent) external pure {
        vm.assume(signedCoefficient > 0);
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        (int256 baseRoot, int256 baseExponent) = LibDecimalFloatSqrtVariants.sqrtBase(signedCoefficient, exponent);
        assertEq(root, baseRoot, "root");
        assertEq(rootExponent, baseExponent, "exponent");
    }

    function testSqrtPlainEquivalence(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, 1e76 - 1);
        exponent = bound(exponent, type(int256).min + 81, type(int256).max);
        (int256 root, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        (int256 plainRoot, int256 plainExponent) =
            LibDecimalFloatSqrtVariants.sqrtPlainNewton(signedCoefficient, exponent);
        assertEq(root, plainRoot, "newton root");
        assertEq(rootExponent, plainExponent, "newton exponent");
        (plainRoot, plainExponent) = LibDecimalFloatSqrtVariants.sqrtPlainResidual(signedCoefficient, exponent);
        assertEq(root, plainRoot, "residual root");
        assertEq(rootExponent, plainExponent, "residual exponent");
    }

    function sqrtGas(int256 signedCoefficient, int256 exponent) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        g -= gasleft();
    }

    function baseGas(int256 signedCoefficient, int256 exponent) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloatSqrtVariants.sqrtBase(signedCoefficient, exponent);
        g -= gasleft();
    }

    function plainNewtonGas(int256 signedCoefficient, int256 exponent) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloatSqrtVariants.sqrtPlainNewton(signedCoefficient, exponent);
        g -= gasleft();
    }

    function plainResidualGas(int256 signedCoefficient, int256 exponent) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloatSqrtVariants.sqrtPlainResidual(signedCoefficient, exponent);
        g -= gasleft();
    }

    function logGas(string memory name, int256 signedCoefficient, int256 exponent) internal view {
        console2.log(name);
        console2.log("  library", this.sqrtGas(signedCoefficient, exponent));
        console2.log("  512-bit residual", this.baseGas(signedCoefficient, exponent));
        console2.log("  plain Newton", this.plainNewtonGas(signedCoefficient, exponent));
        console2.log("  plain residual", this.plainResidualGas(signedCoefficient, exponent));
    }

    /// Run with `-vv`: the library against the 512-bit residual of #309's
    /// branch and against each assembly block in plain Solidity.
    function testSqrtGas() external view {
        logGas("2", 2, 0);
        logGas("2e-1", 2, -1);
        logGas("int224 max", type(int224).max, 0);
        logGas("1e75 - 1", 1e75 - 1, 0);
        logGas("1e76 - 1", 1e76 - 1, 0);
    }
}
