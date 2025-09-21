// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    WithTargetExponentOverflow
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatImplementationWithTargetExponentTest is Test {
    function withTargetExponentExternal(int256 signedCoefficient, int256 exponent, int256 targetExponent)
        external
        pure
        returns (int256)
    {
        return LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, targetExponent);
    }

    function testWithTargetExponentSameExponentNoop(int256 signedCoefficient, int256 exponent) external pure {
        (int256 actualSignedCoefficient) =
            LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, exponent);
        assertEq(actualSignedCoefficient, signedCoefficient, "signedCoefficient");
    }

    function testWithTargetExponentLargerTargetExponentNoRevert(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponent
    ) external pure {
        targetExponent = bound(targetExponent, type(int256).min + 1, type(int256).max);
        exponent = bound(exponent, type(int256).min, targetExponent - 1);
        LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, targetExponent);
    }

    function testWithTargetExponentLargerExponentVeryLargeDiffRevert(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponent
    ) external {
        targetExponent = bound(targetExponent, type(int256).min, type(int256).max - 77);
        exponent = bound(exponent, targetExponent + 77, type(int256).max);
        vm.expectRevert(
            abi.encodeWithSelector(WithTargetExponentOverflow.selector, signedCoefficient, exponent, targetExponent)
        );
        this.withTargetExponentExternal(signedCoefficient, exponent, targetExponent);
    }

    function testWithTargetExponentLargerExponentOverflowRescaleRevert(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponent
    ) external {
        targetExponent = bound(targetExponent, type(int256).min, type(int256).max - 76);
        exponent = bound(exponent, targetExponent + 1, targetExponent + 76);

        unchecked {
            int256 scale = int256(10 ** uint256(exponent - targetExponent));
            int256 c = signedCoefficient * scale;
            vm.assume(c / scale != signedCoefficient);
        }

        vm.expectRevert(
            abi.encodeWithSelector(WithTargetExponentOverflow.selector, signedCoefficient, exponent, targetExponent)
        );
        this.withTargetExponentExternal(signedCoefficient, exponent, targetExponent);
    }

    function testWithTargetExponentSmallerExponentNoRevert(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponent
    ) external pure {
        targetExponent = bound(targetExponent, type(int256).min, type(int256).max - 76);
        exponent = bound(exponent, targetExponent + 1, targetExponent + 76);

        unchecked {
            int256 scale = int256(10 ** uint256(exponent - targetExponent));
            int256 c = signedCoefficient * scale;
            vm.assume(c / scale == signedCoefficient);
        }
        int256 actualSignedCoefficient =
            LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, targetExponent);
        int256 expectedSignedCoefficient = signedCoefficient * int256(10 ** uint256(exponent - targetExponent));
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
    }

    function checkWithTargetExponent(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponent,
        int256 expectedSignedCoefficient
    ) internal pure {
        int256 actualSignedCoefficient =
            LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, targetExponent);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
    }

    function testWithTargetExponentExamples() external pure {
        checkWithTargetExponent(1e37, -37, -37, 1e37);
        checkWithTargetExponent(1e37, -37, -36, 1e36);
        checkWithTargetExponent(1e37, -37, -38, 1e38);
        checkWithTargetExponent(1, 0, -37, 1e37);
        checkWithTargetExponent(1, 0, -36, 1e36);
        checkWithTargetExponent(1, 0, -76, 1e76);
        checkWithTargetExponent(type(int256).min, 0, 0, type(int256).min);
        checkWithTargetExponent(type(int256).max, 0, 0, type(int256).max);
        checkWithTargetExponent(type(int256).min, 0, 1, type(int256).min / 10);
        checkWithTargetExponent(type(int256).max, 0, 1, type(int256).max / 10);
    }


    function testWithTargetExponentTargetMoreThan76Larger(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponent
    ) external pure {
        targetExponent = bound(targetExponent, type(int256).min + 77, type(int256).max);
        exponent = bound(exponent, type(int256).min, targetExponent - 77);

        int256 actualSignedCoefficient =
            LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, targetExponent);
        assertEq(actualSignedCoefficient, 0, "signedCoefficient");
    }

    function testWithTargetExponentMaxOverflow(int256 signedCoefficient) external pure {
        int256 actualSignedCoefficient =
            LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, type(int256).min, type(int256).max);
        assertEq(actualSignedCoefficient, 0, "signedCoefficient");
    }

    function testWithTargetExponentScaleDown(int256 signedCoefficient, int256 exponent, int256 targetExponentDiff)
        external
        pure
    {
        targetExponentDiff = bound(targetExponentDiff, int256(1), int256(76));
        exponent = bound(exponent, type(int256).min, type(int256).max - targetExponentDiff);
        int256 targetExponent = exponent + targetExponentDiff;

        int256 actualSignedCoefficient =
            LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, targetExponent);
        int256 expectedSignedCoefficient = signedCoefficient / int256(10 ** uint256(targetExponentDiff));
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
    }

    function testWithTargetExponentScaleUpLargeDiffRevert(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponent
    ) external {
        exponent = bound(exponent, type(int256).min + 77, type(int256).max);
        targetExponent = bound(targetExponent, type(int256).min, exponent - 77);

        vm.expectRevert(
            abi.encodeWithSelector(WithTargetExponentOverflow.selector, signedCoefficient, exponent, targetExponent)
        );
        this.withTargetExponentExternal(signedCoefficient, exponent, targetExponent);
    }

    function testWithTargetExponentScaleUpNotOverflow(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponentDiff
    ) external pure {
        targetExponentDiff = bound(targetExponentDiff, int256(1), int256(76));
        exponent = bound(exponent, type(int256).min + targetExponentDiff, type(int256).max);
        int256 targetExponent = exponent - targetExponentDiff;

        // Assume not overflow.
        unchecked {
            int256 scale = int256(10 ** uint256(exponent - targetExponent));
            int256 c = signedCoefficient * scale;
            vm.assume(c / scale == signedCoefficient);
        }

        int256 actualSignedCoefficient =
            LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, targetExponent);
        int256 expectedSignedCoefficient = signedCoefficient * int256(10 ** uint256(exponent - targetExponent));
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
    }

    function testWithTargetExponentScaleUpOverflow(int256 signedCoefficient, int256 exponent, int256 targetExponentDiff)
        external
    {
        targetExponentDiff = bound(targetExponentDiff, int256(1), int256(76));
        exponent = bound(exponent, type(int256).min + targetExponentDiff, type(int256).max);
        int256 targetExponent = exponent - targetExponentDiff;

        // Assume overflow.
        unchecked {
            int256 scale = int256(10 ** uint256(exponent - targetExponent));
            int256 c = signedCoefficient * scale;
            vm.assume(c / scale != signedCoefficient);
        }

        vm.expectRevert(
            abi.encodeWithSelector(WithTargetExponentOverflow.selector, signedCoefficient, exponent, targetExponent)
        );
        this.withTargetExponentExternal(signedCoefficient, exponent, targetExponent);
    }
}
