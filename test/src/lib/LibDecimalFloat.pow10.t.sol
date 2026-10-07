// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTestPowRange, PowRange} from "test/lib/LibTestPowRange.sol";

contract LibDecimalFloatPow10Test is Test {
    using LibDecimalFloat for Float;

    function pow10External(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.pow10(signedCoefficient, exponent);
    }

    function pow10External(Float float) external pure returns (Float) {
        return LibDecimalFloat.pow10(float);
    }

    /// `pow10` of an input whose effective result exponent falls below
    /// `int32.min` reverts instead of silently producing `FLOAT_ZERO`.
    function testPow10RevertsOnExponentUnderflow() external {
        Float float = Float.wrap(0xffffffffffffffffffffff0000000000000000000000000000000000000000ff);
        // 10^x for x = -3.74...160.1 is 10^-0.1 = 0.794328234724281502065918282836387932588960 from `bc -l`.
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentUnderflow.selector,
                int256(79432823472428150206591828283638793258896),
                int256(-37414441915671114706014331717536845303191873100201)
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
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), int256(type(int32).max) + 68));
        this.pow10External(LibDecimalFloat.packLossless(int256(type(int32).max) + 68, 0));
    }

    /// pow10 matches its implementation packed. It reverts only for an x past
    /// the range by more than twice pow10's relative bound, the slack it puts
    /// on 10^x in log10, and returns for any x inside it by as much.
    function testPow10Packed(Float float) external {
        (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
        PowRange range = LibTestPowRange.range(signedCoefficientFloat, exponentFloat, 11, -41);
        try this.pow10External(signedCoefficientFloat, exponentFloat) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            if (exponent > type(int32).max) {
                // Digits are taken back to pack at int32.max when int224 holds
                // them.
                int256 excess = exponent - type(int32).max;
                int256 lifted = signedCoefficient;
                // forge-lint: disable-next-line(unsafe-typecast)
                for (int256 i = 0; i < excess && int224(lifted) == lifted; i++) {
                    lifted *= 10;
                }
                // forge-lint: disable-next-line(unsafe-typecast)
                if (int224(lifted) == lifted) {
                    (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = this.pow10External(float).unpack();
                    assertEq(signedCoefficientUnpacked, lifted);
                    assertEq(exponentUnpacked, type(int32).max);
                    assertTrue(range != PowRange.Over, "returned past the range");
                } else {
                    assertTrue(range == PowRange.Over || range == PowRange.OverEdge, "overflow inside the range");
                    vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
                    this.pow10External(float);
                }
            } else {
                // Predict whether packArithmeticResult will revert on underflow.
                (Float predicted, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
                if (!lossless && Float.unwrap(predicted) == bytes32(0)) {
                    assertTrue(range == PowRange.Under || range == PowRange.UnderEdge, "underflow inside the range");
                    vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, signedCoefficient, exponent));
                    this.pow10External(float);
                } else {
                    Float floatPower10 = this.pow10External(float);
                    (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = floatPower10.unpack();
                    (signedCoefficient, exponent) = predicted.unpack();
                    assertEq(signedCoefficient, signedCoefficientUnpacked);
                    assertEq(exponent, exponentUnpacked);
                    assertTrue(range != PowRange.Over && range != PowRange.Under, "returned past the range");
                }
            }
        } catch {
            // The implementation cannot rescale an integer part past int256,
            // which for any nonzero x is far past the range.
            if (signedCoefficientFloat == 0) {
                assertEq(Float.unwrap(this.pow10External(float)), Float.unwrap(LibDecimalFloat.FLOAT_ONE));
            } else {
                assertTrue(
                    range == PowRange.Over || range == PowRange.Under, "implementation reverted inside the range"
                );
                vm.expectRevert(
                    abi.encodeWithSelector(
                        range == PowRange.Over ? ExponentOverflow.selector : ExponentUnderflow.selector,
                        signedCoefficientFloat,
                        exponentFloat
                    )
                );
                this.pow10External(float);
            }
        }
    }
}
