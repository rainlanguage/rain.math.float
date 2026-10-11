// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {
    LibDecimalFloatImplementation,
    DivisionByZero,
    ExponentOverflow
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationInvTest is Test {
    function invExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        return (signedCoefficient, exponent);
    }

    /// `inv` of a non-zero `x` is `1 / x` truncated towards zero to a
    /// coefficient in `[1e75, 1e76]`: `q × 10^E × |x| <= 1 < (q + 1) × 10^E ×
    /// |x|`, decided exactly in 512 bits, with the sign of `x`. The parts are
    /// also those `div` documents for `1e76e-76 / x`, which picks between
    /// `1e76` and `1e75` at one exponent apart when `1 / x` is a power of ten:
    /// `divPayloadWide`, so `ExponentOverflow` above `type(int256).max` and below
    /// `10^type(int256).min` the digits truncated towards zero.
    function checkInv(int256 signedCoefficient, int256 exponent) internal {
        (bool overflowed, int256 expectedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.divPayloadWide(1e76, -76, signedCoefficient, exponent);
        if (overflowed) {
            vm.expectPartialRevert(ExponentOverflow.selector);
            this.invExternal(signedCoefficient, exponent);
            return;
        }
        (int256 q, int256 e) = this.invExternal(signedCoefficient, exponent);
        assertEq(q, expectedCoefficient, "coefficient");
        assertEq(e, expectedExponent, "exponent");

        (, int256 unfloored) = LibTestExactDecimal.divPayload(1e76, 0, signedCoefficient, 0);
        (int256 cls,) = LibTestExactDecimal.wideExponent(-76, exponent, 0, unfloored);
        if (cls == -1) {
            return;
        }

        assertEq(q < 0, signedCoefficient < 0, "sign");
        uint256 magnitude = LibTestExactDecimal.abs(q);
        assertGe(magnitude, 1e75, "precision low");
        assertLe(magnitude, 1e76, "precision high");

        uint256 x = LibTestExactDecimal.abs(signedCoefficient);
        int256 scale = e + exponent;
        assertLe(
            LibTestExactDecimal.cmpScaled(LibTestExactDecimal.mul(magnitude, x), scale, LibTestExactDecimal.u512(1), 0),
            0,
            "above 1 / x"
        );
        assertGt(
            LibTestExactDecimal.cmpScaled(
                LibTestExactDecimal.mul(magnitude + 1, x), scale, LibTestExactDecimal.u512(1), 0
            ),
            0,
            "not floor"
        );
    }

    function testInvExact(int256 signedCoefficient, int256 exponent) external {
        vm.assume(signedCoefficient != 0);
        checkInv(signedCoefficient, exponent);
    }

    /// Small coefficients, where `1 / x` is often exact.
    function testInvExactSmall(int256 signedCoefficient, int256 exponent) external {
        signedCoefficient = bound(signedCoefficient, -1000, 1000);
        vm.assume(signedCoefficient != 0);
        checkInv(signedCoefficient, exponent);
    }

    /// Powers of ten, where `1 / x` is exact and a power of ten.
    function testInvExactPowerOfTen(uint256 digits, bool negative, int256 exponent) external {
        digits = bound(digits, 0, 76);
        // 10^76 < 2^255.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(10 ** digits);
        if (negative) {
            signedCoefficient = -signedCoefficient;
        }
        checkInv(signedCoefficient, exponent);
    }

    function testInvExactExtremes() external {
        checkInv(type(int256).max, 0);
        checkInv(type(int256).min, 0);
        checkInv(type(int256).min, type(int256).min);
        checkInv(type(int256).max, type(int256).max);
        checkInv(1, type(int256).min);
        checkInv(-1, type(int256).max);
        checkInv(3, 0);
        checkInv(7, -5);
    }

    function testInvOne() external pure {
        (int256 q, int256 e) = LibDecimalFloatImplementation.inv(1, 0);
        assertEq(q, 1e76);
        assertEq(e, -76);
    }

    function testInvGas0() external pure {
        (int256 outputSignedCoefficient, int256 outputExponent) = LibDecimalFloatImplementation.inv(3e37, -37);
        (outputSignedCoefficient, outputExponent);
    }

    function testInv0() external {
        vm.expectRevert(abi.encodeWithSelector(DivisionByZero.selector, 1e76, -76));
        this.invExternal(0, 0);
    }
}
