// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    WithTargetExponentOverflow
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatImplementationWithTargetExponentTest is Test {
    function withTargetExponentExternal(int256 signedCoefficient, int256 exponent, int256 targetExponent)
        external
        pure
        returns (int256)
    {
        return LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, targetExponent);
    }

    /// The int256 coefficients c with c 10^d in int256, for d in [1, 76].
    /// Division truncates toward zero, which floors the positive bound and
    /// ceils the negative one, so both are the exact bounds.
    function growthRange(int256 diff) internal pure returns (int256 lo, int256 hi) {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** uint256(diff));
        return (type(int256).min / scale, type(int256).max / scale);
    }

    function expectOverflow(int256 signedCoefficient, int256 exponent, int256 targetExponent) internal {
        vm.expectRevert(
            abi.encodeWithSelector(WithTargetExponentOverflow.selector, signedCoefficient, exponent, targetExponent)
        );
        this.withTargetExponentExternal(signedCoefficient, exponent, targetExponent);
    }

    function testWithTargetExponentSameExponentNoop(int256 signedCoefficient, int256 exponent) external pure {
        (int256 actualSignedCoefficient) =
            LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, exponent);
        assertEq(actualSignedCoefficient, signedCoefficient, "signedCoefficient");
    }

    /// 0 10^d = 0 fits for every d, including past 76 and past int256.max.
    function testWithTargetExponentScaleUpZero(int256 exponent, int256 targetExponent) external pure {
        exponent = bound(exponent, type(int256).min + 1, type(int256).max);
        targetExponent = bound(targetExponent, type(int256).min, exponent - 1);
        assertEq(LibDecimalFloatImplementation.withTargetExponent(0, exponent, targetExponent), 0);
    }

    /// |c| 10^d >= 10^77 > 2^255 for any nonzero c and d >= 77.
    function testWithTargetExponentScaleUpLargeDiffRevert(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponent
    ) external {
        vm.assume(signedCoefficient != 0);
        exponent = bound(exponent, type(int256).min + 77, type(int256).max);
        targetExponent = bound(targetExponent, type(int256).min, exponent - 77);
        expectOverflow(signedCoefficient, exponent, targetExponent);
    }

    function testWithTargetExponentScaleUpNotOverflow(int256 signedCoefficient, int256 exponent, int256 diff)
        external
        pure
    {
        diff = bound(diff, 1, 76);
        exponent = bound(exponent, type(int256).min + diff, type(int256).max);
        (int256 lo, int256 hi) = growthRange(diff);
        signedCoefficient = bound(signedCoefficient, lo, hi);

        // Checked, so a wrong bound fails here rather than passing silently.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expected = signedCoefficient * int256(10 ** uint256(diff));
        assertEq(
            LibDecimalFloatImplementation.withTargetExponent(signedCoefficient, exponent, exponent - diff), expected
        );
    }

    function testWithTargetExponentScaleUpOverflow(
        int256 signedCoefficient,
        int256 exponent,
        int256 diff,
        bool negative
    ) external {
        diff = bound(diff, 1, 76);
        exponent = bound(exponent, type(int256).min + diff, type(int256).max);
        (int256 lo, int256 hi) = growthRange(diff);
        signedCoefficient = negative
            ? bound(signedCoefficient, type(int256).min, lo - 1)
            : bound(signedCoefficient, hi + 1, type(int256).max);
        expectOverflow(signedCoefficient, exponent, exponent - diff);
    }

    /// The fit bounds at every d, each side: the last coefficient that fits
    /// and the first that does not.
    function testWithTargetExponentScaleUpBoundaries() external {
        assertEq(LibDecimalFloatImplementation.withTargetExponent(5, 76, 0), 5e76);
        assertEq(LibDecimalFloatImplementation.withTargetExponent(-5, 76, 0), -5e76);
        expectOverflow(6, 76, 0);
        expectOverflow(-6, 76, 0);
        expectOverflow(1, 77, 0);
        expectOverflow(-1, 77, 0);
        assertEq(
            LibDecimalFloatImplementation.withTargetExponent(
                5789604461865809771178549250434395392663499233282028201972879200395656481996, 1, 0
            ),
            57896044618658097711785492504343953926634992332820282019728792003956564819960
        );
        expectOverflow(5789604461865809771178549250434395392663499233282028201972879200395656481997, 1, 0);
        assertEq(
            LibDecimalFloatImplementation.withTargetExponent(
                -5789604461865809771178549250434395392663499233282028201972879200395656481996, 1, 0
            ),
            -57896044618658097711785492504343953926634992332820282019728792003956564819960
        );
        expectOverflow(-5789604461865809771178549250434395392663499233282028201972879200395656481997, 1, 0);
        for (int256 d = 1; d <= 76; d++) {
            (int256 lo, int256 hi) = growthRange(d);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 scale = int256(10 ** uint256(d));
            assertEq(LibDecimalFloatImplementation.withTargetExponent(hi, d, 0), hi * scale);
            assertEq(LibDecimalFloatImplementation.withTargetExponent(lo, d, 0), lo * scale);
            expectOverflow(hi + 1, d, 0);
            expectOverflow(lo - 1, d, 0);
        }
    }

    function checkWithTargetExponent(
        int256 signedCoefficient,
        int256 exponent,
        int256 targetExponent,
        int256 expectedSignedCoefficient
    ) internal pure {
        int256 actualSignedCoefficient = LibDecimalFloatImplementation.withTargetExponent(
            signedCoefficient, exponent, targetExponent
        );
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
        checkWithTargetExponent(0, 77, 0, 0);
        checkWithTargetExponent(0, 0, -77, 0);
        checkWithTargetExponent(0, type(int256).max, type(int256).min, 0);
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
        // targetExponentDiff [1, 76]
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = signedCoefficient / int256(10 ** uint256(targetExponentDiff));
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
    }
}
