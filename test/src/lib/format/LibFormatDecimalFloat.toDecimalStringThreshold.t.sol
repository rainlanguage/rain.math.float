// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {UnformatableExponent} from "src/error/ErrFormat.sol";
import {ScientificMinNotLessThanMax} from "src/error/ErrDecimalFloat.sol";
import {TestDecimalFloat} from "test/concrete/TestDecimalFloat.sol";

contract LibFormatDecimalFloatToDecimalStringThresholdTest is Test {
    using LibDecimalFloat for Float;

    Float internal constant MIN = Float.wrap(0xfffffffc00000000000000000000000000000000000000000000000000000001);
    Float internal constant MAX = Float.wrap(0x0000000900000000000000000000000000000000000000000000000000000001);

    function formatExternal(Float float, Float scientificMin, Float scientificMax)
        external
        pure
        returns (string memory)
    {
        return LibFormatDecimalFloat.toDecimalString(float, scientificMin, scientificMax);
    }

    function formatExternal(Float float, bool scientific) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(float, scientific);
    }

    function check(
        int256 coefficient,
        int256 exponent,
        Float scientificMin,
        Float scientificMax,
        string memory expected
    ) internal pure {
        assertEq(
            LibFormatDecimalFloat.toDecimalString(
                LibDecimalFloat.packLossless(coefficient, exponent), scientificMin, scientificMax
            ),
            expected
        );
    }

    /// Issue #319: the magnitude of int224.min at int32.max does not pack, but
    /// it is above the max threshold so it formats scientifically, whose display
    /// exponent is past int32.
    function testThresholdInt224MinAtExponentCeiling() external {
        Float a = LibDecimalFloat.packLossless(type(int224).min, type(int32).max);
        vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, int256(type(int32).max)));
        this.formatExternal(a, MIN, MAX);
        vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, int256(type(int32).max)));
        this.formatExternal(a, true);
    }

    /// The concrete's default `format` delegates to the library threshold
    /// format, so it reverts the same.
    function testConcreteFormatInt224MinAtExponentCeiling() external {
        TestDecimalFloat concrete = new TestDecimalFloat();
        Float a = LibDecimalFloat.packLossless(type(int224).min, type(int32).max);
        vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, int256(type(int32).max)));
        concrete.format(a);
        vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, int256(type(int32).max)));
        concrete.format(a, MIN, MAX);
        assertEq(concrete.format(LibDecimalFloat.packLossless(1000000001, 0)), "1.000000001e9");
        assertEq(concrete.format(LibDecimalFloat.packLossless(-1, 9)), "-1000000000");
    }

    /// The magnitude is compared exactly. `abs` of int224.min sheds its last
    /// digit, which would make it equal to this max and so not scientific.
    function testThresholdInt224MinMagnitudeIsExact() external pure {
        Float max = LibDecimalFloat.packLossless(type(int224).min / 10 * -1, 1);
        check(
            type(int224).min, 0, MIN, max, "-1.3479973333575319897333507543509815336818572211270286240551805124608e67"
        );
        check(
            type(int224).min,
            0,
            MIN,
            LibDecimalFloat.packLossless(2, 67),
            "-13479973333575319897333507543509815336818572211270286240551805124608"
        );
    }

    /// Both thresholds are inclusive of the non-scientific range, for both
    /// signs.
    function testThresholdBoundaries() external pure {
        check(1, 9, MIN, MAX, "1000000000");
        check(-1, 9, MIN, MAX, "-1000000000");
        check(1000000001, 0, MIN, MAX, "1.000000001e9");
        check(-1000000001, 0, MIN, MAX, "-1.000000001e9");
        check(1, -4, MIN, MAX, "0.0001");
        check(-1, -4, MIN, MAX, "-0.0001");
        check(99, -6, MIN, MAX, "9.9e-5");
        check(-99, -6, MIN, MAX, "-9.9e-5");
        check(5, 0, MIN, MAX, "5");
        check(-5, 0, MIN, MAX, "-5");
        check(0, 0, MIN, MAX, "0");
    }

    function testThresholdMinNotLessThanMax() external {
        vm.expectRevert(abi.encodeWithSelector(ScientificMinNotLessThanMax.selector, MAX, MIN));
        this.formatExternal(LibDecimalFloat.FLOAT_ONE, MAX, MIN);
        vm.expectRevert(abi.encodeWithSelector(ScientificMinNotLessThanMax.selector, MIN, MIN));
        this.formatExternal(LibDecimalFloat.FLOAT_ONE, MIN, MIN);
    }

    /// Against negated thresholds instead of the magnitude, which needs no
    /// `abs` of the value.
    function testThresholdAgainstNegatedThresholds(Float a, int128 minCoefficient, int32 minExponent, int32 maxExponent)
        external
        view
    {
        vm.assume(minCoefficient > 0);
        Float scientificMin = LibDecimalFloat.packLossless(minCoefficient, minExponent);
        Float scientificMax = LibDecimalFloat.packLossless(minCoefficient, maxExponent);
        vm.assume(scientificMin.lt(scientificMax));
        bool scientific = a.gte(LibDecimalFloat.FLOAT_ZERO)
            ? a.lt(scientificMin) || a.gt(scientificMax)
            : a.gt(scientificMin.minus()) || a.lt(scientificMax.minus());
        (bool successActual, bytes memory actual) = address(this)
            .staticcall(
                abi.encodeWithSignature("formatExternal(bytes32,bytes32,bytes32)", a, scientificMin, scientificMax)
            );
        (bool successExpected, bytes memory expected) =
            address(this).staticcall(abi.encodeWithSignature("formatExternal(bytes32,bool)", a, scientific));
        assertEq(successActual, successExpected);
        assertEq(actual, expected);
    }
}
