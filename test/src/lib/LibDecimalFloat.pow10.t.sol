// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestPowRange, PowRange, LOG10_OVERFLOW, THRESHOLD_SLACK} from "test/lib/LibTestPowRange.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibTranscendentalOracle} from "test/lib/LibTranscendentalOracle.sol";

contract LibDecimalFloatPow10Test is Test {
    using LibDecimalFloat for Float;

    function pow10External(Float float) external pure returns (Float) {
        return LibDecimalFloat.pow10(float);
    }

    /// `pow10` of an input whose effective result exponent falls below
    /// `int32.min` reverts instead of silently producing `FLOAT_ZERO`. x is
    /// -3.74e49, its coefficient and exponent the low 224 and high 32 bits.
    function testPow10RevertsOnExponentUnderflow() external {
        Float float = Float.wrap(0xffffffffffffffffffffff0000000000000000000000000000000000000000ff);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentUnderflow.selector, int256(-374144419156711147060143317175368453031918731001601), int256(-1)
            )
        );
        this.pow10External(float);
    }

    /// Issue #297 review: below 1e-2147483608 the result sheds digits at the
    /// int32 floor. 10^-2147483645.5 is 316.2277e-2147483648 and
    /// 10^-2147483647.5 is 3.162277e-2147483648, truncated.
    function testPow10Floor() external view {
        (int256 signedCoefficient, int256 exponent) =
            this.pow10External(LibDecimalFloat.packLossless(-21474836455, -1)).unpack();
        assertEq(signedCoefficient, 316);
        assertEq(exponent, type(int32).min);
        (signedCoefficient, exponent) = this.pow10External(LibDecimalFloat.packLossless(-21474836475, -1)).unpack();
        assertEq(signedCoefficient, 3);
        assertEq(exponent, type(int32).min);
    }

    /// 10^(int32.max + k) is 10^k at int32.max while 10^k fits int224, which
    /// it does up to k 67.
    function testPow10PastInt32Max() external view {
        int256[2] memory ks = [int256(1), 67];
        for (uint256 i = 0; i < ks.length; i++) {
            (int256 signedCoefficient, int256 exponent) =
                this.pow10External(LibDecimalFloat.packLossless(int256(type(int32).max) + ks[i], 0)).unpack();
            // forge-lint: disable-next-line(unsafe-typecast)
            assertEq(signedCoefficient, int256(10 ** uint256(ks[i])));
            assertEq(exponent, type(int32).max);
        }
    }

    /// An x whose integer part is past int256 reverts on the side of its sign.
    /// It reverted `WithTargetExponentOverflow` before.
    function testPow10HugeX() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), int256(77)));
        this.pow10External(LibDecimalFloat.packLossless(1, 77));
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(-1), int256(77)));
        this.pow10External(LibDecimalFloat.packLossless(-1, 77));
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(58), int256(75)));
        this.pow10External(LibDecimalFloat.packLossless(58, 75));
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(-58), int256(75)));
        this.pow10External(LibDecimalFloat.packLossless(-58, 75));
    }

    /// 10^0 is 1 for a zero of any exponent. 0e77 reverted before.
    function testPow10ZeroAnyExponent(int32 exponent) external view {
        assertEq(
            Float.unwrap(this.pow10External(LibDecimalFloat.packLossless(0, exponent))),
            Float.unwrap(LibDecimalFloat.FLOAT_ONE)
        );
        assertEq(
            Float.unwrap(this.pow10External(LibDecimalFloat.packLossless(0, 77))),
            Float.unwrap(LibDecimalFloat.FLOAT_ONE)
        );
    }

    /// 10^(int32.max + 68) is 1e68 at int32.max, past int224.
    function testPow10PastInt32MaxOverflows() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(type(int32).max) + 68, int256(0)));
        this.pow10External(LibDecimalFloat.packLossless(int256(type(int32).max) + 68, 0));
    }

    /// pow10 returns inside the range, reverts the range error past it, and
    /// may do either at an edge, as `LibTestPowRange.pow10Range` decides.
    function testPow10Range(Float float) external view {
        checkPow10(float);
    }

    /// x 10^-57 for x within 1e-40 of each threshold, across the edge.
    function testPow10NearThresholds(int256 offset, bool overflowSide) external view {
        offset = bound(offset, -1e17, 1e17);
        int256 threshold = overflowSide ? LOG10_OVERFLOW / 1e9 : int256(type(int32).min) * 1e57;
        checkPow10(LibDecimalFloat.packLossless(threshold + offset, -57));
    }

    /// x 10^-57 at THRESHOLD_SLACK past each threshold must revert and as far
    /// inside must return. LOG10_OVERFLOW / 1e9 is the overflow threshold
    /// truncated at 1e-57, and one more is above it.
    function testPow10Thresholds() external {
        int256 overflow = LOG10_OVERFLOW / 1e9;
        int256 underflow = int256(type(int32).min) * 1e57;
        Float past = LibDecimalFloat.packLossless(overflow + 1 + THRESHOLD_SLACK, -57);
        Float inside = LibDecimalFloat.packLossless(overflow - THRESHOLD_SLACK, -57);
        assertTrue(LibTestPowRange.pow10Range(past) == PowRange.Over, "over");
        assertTrue(LibTestPowRange.pow10Range(inside) == PowRange.Inside, "inside over");
        assertPow10Value(inside, this.pow10External(inside));
        vm.expectRevert(LibTestPowRange.rangeError(true, past));
        this.pow10External(past);

        past = LibDecimalFloat.packLossless(underflow - 1 - THRESHOLD_SLACK, -57);
        inside = LibDecimalFloat.packLossless(underflow + THRESHOLD_SLACK, -57);
        assertTrue(LibTestPowRange.pow10Range(past) == PowRange.Under, "under");
        assertTrue(LibTestPowRange.pow10Range(inside) == PowRange.Inside, "inside under");
        assertPow10Value(inside, this.pow10External(inside));
        vm.expectRevert(LibTestPowRange.rangeError(false, past));
        this.pow10External(past);
    }

    function checkPow10(Float x) internal view {
        PowRange range = LibTestPowRange.pow10Range(x);
        try this.pow10External(x) returns (Float result) {
            assertTrue(LibTestPowRange.mayReturn(range), "returned past the range");
            assertPow10Value(x, result);
        } catch (bytes memory reason) {
            bool over = keccak256(reason) == keccak256(LibTestPowRange.rangeError(true, x));
            assertTrue(over || keccak256(reason) == keccak256(LibTestPowRange.rangeError(false, x)), "pow10 revert");
            assertTrue(LibTestPowRange.mayRevert(range, over), "reverted inside the range");
        }
    }

    /// A returned 10^x is exactly 1 for a zero x, exactly 10^x for a whole x,
    /// and otherwise within 5.0000005e-41 of the oracle's power P: pow10's
    /// 5.0000004e-41 of the true power, which is within 1e-67 of P. Below
    /// 1e-2147483608 the bound adds 1e-2147483648.
    function assertPow10Value(Float x, Float result) internal pure {
        (int256 signedCoefficientX, int256 exponentX) = x.unpack();
        (int256 signedCoefficient, int256 exponent) = result.unpack();
        assertTrue(signedCoefficient > 0, "positive");
        if (signedCoefficientX == 0) {
            assertTrue(LibTestExactDecimal.eq(signedCoefficient, exponent, 1, 0), "pow10 zero");
            return;
        }
        if (LibTestExactDecimal.isWhole(signedCoefficientX, exponentX)) {
            // A returned x is within int32 of zero, so its whole value and
            // the power of ten it is read with fit, and a whole x below 1e-67
            // is zero.
            int256 whole;
            if (exponentX >= 0) {
                // forge-lint: disable-next-line(unsafe-typecast)
                whole = signedCoefficientX * int256(10 ** uint256(exponentX));
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                whole = signedCoefficientX / int256(10 ** uint256(-exponentX));
            }
            assertTrue(LibTestExactDecimal.eq(signedCoefficient, exponent, 1, whole), "pow10 whole");
            return;
        }
        (uint256 power, int256 powerExponent) = LibTranscendentalOracle.exp10(signedCoefficientX, exponentX);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 magnitude = uint256(signedCoefficient);
        assertTrue(
            LibTestExactDecimal.cmpScaled(
                LibTestExactDecimal.u512(magnitude),
                exponent,
                LibTestExactDecimal.mul(power, 1e48 + 50000005),
                powerExponent - 48
            ) <= 0,
            "pow10 above the bound"
        );
        if (exponent == type(int32).min && magnitude < 1e40) {
            magnitude += 1;
        }
        assertTrue(
            LibTestExactDecimal.cmpScaled(
                LibTestExactDecimal.u512(magnitude),
                exponent,
                LibTestExactDecimal.mul(power, 1e48 - 50000005),
                powerExponent - 48
            ) >= 0,
            "pow10 below the bound"
        );
    }
}
