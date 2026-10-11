// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatImplementationMulTest is Test {
    function checkMul(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    /// -1 * -1 = 1
    function testMulNegativeOne() external pure {
        checkMul(-1, 0, -1, 0, 1, 0);
    }

    /// -1 * 1 = -1
    function testMulNegativeOneOne() external pure {
        checkMul(-1, 0, 1, 0, -1, 0);
    }

    /// 1 * -1 = -1
    function testMulOneNegativeOne() external pure {
        checkMul(1, 0, -1, 0, -1, 0);
    }

    /// found during testing
    /// 1.3979 * 0.5 = 0.69895
    function testMul1_3979_0_5() external pure {
        checkMul(1.3979e76, -76, 0.5e66, -66, 0.69895e76, -76);
    }

    /// Simple 0 multiply 0
    /// 0 * 0 = 0
    function testMulZero0Exponent() external pure {
        checkMul(0, 0, 0, 0, 0, 0);
    }

    /// 0 multiply 0 any exponent
    /// 0 * 0 = 0
    function testMulZeroAnyExponent(int64 exponentA, int64 exponentB) external pure {
        checkMul(0, exponentA, 0, exponentB, 0, 0);
    }

    /// 0 multiply 1
    /// 0 * 1 = 0
    function testMulZeroOne() external pure {
        checkMul(0, 0, 1, 0, 0, 0);
    }

    /// 1 multiply 0
    /// 1 * 0 = 0
    function testMulOneZero() external pure {
        checkMul(1, 0, 0, 0, 0, 0);
    }

    /// 1 multiply 1
    /// 1 * 1 = 1
    function testMulOneOne() external pure {
        checkMul(1, 0, 1, 0, 1, 0);
    }

    /// 123456789 multiply 987654321
    /// 123456789 * 987654321 = 121932631112635269
    function testMul123456789987654321() external pure {
        checkMul(123456789, 0, 987654321, 0, 121932631112635269, 0);
    }

    function testMulMaxSignedCoefficient() external pure {
        checkMul(
            type(int256).max,
            0,
            type(int256).max,
            0,
            int256(3.3519519824856492748935062495514615318698414551480983444308903609304410075182e76),
            77
        );
    }

    /// 123456789 multiply 987654321 with exponents
    /// 123456789 * 987654321 = 121932631112635269
    function testMul123456789987654321WithExponents(int128 exponentA, int128 exponentB) external pure {
        exponentA = int128(bound(exponentA, -127, 127));
        exponentB = int128(bound(exponentB, -127, 127));

        checkMul(123456789, exponentA, 987654321, exponentB, 121932631112635269, exponentA + exponentB);
    }

    /// 1e18 * 1e-19 = 1e-1
    function testMul1e181e19() external pure {
        checkMul(1, 18, 1, -19, 1, -1);
    }

    function testMulGasZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(0, 0, 0, 0);
        (signedCoefficient, exponent);
    }

    function testMulGasOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(1e37, -37, 1e37, -37);
        (signedCoefficient, exponent);
    }

    /// a * 1 == a for all in-range inputs.
    function testMulIdentity(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX / 2);

        (int256 resultCoeff, int256 resultExp) = LibDecimalFloatImplementation.mul(signedCoefficient, exponent, 1, 0);
        assertTrue(LibTestExactDecimal.eq(resultCoeff, resultExp, signedCoefficient, exponent), "a * 1 should equal a");
    }

    /// a * b and b * a are both the exact product's parts. The exponent
    /// sum stays above the floor, so no digits are shed into it.
    function testMulCommutative(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN, EXPONENT_MAX / 2);
        exponentB = bound(exponentB, EXPONENT_MIN, EXPONENT_MAX / 2);

        (int256 coeffAB, int256 expAB) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 coeffBA, int256 expBA) =
            LibDecimalFloatImplementation.mul(signedCoefficientB, exponentB, signedCoefficientA, exponentA);

        (int256 expectedCoeff, int256 expectedExp) =
            LibTestExactDecimal.mulPayload(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(coeffAB, expectedCoeff, "a * b coefficient");
        assertEq(expAB, expectedExp, "a * b exponent");
        assertEq(coeffBA, expectedCoeff, "b * a coefficient");
        assertEq(expBA, expectedExp, "b * a exponent");
    }

    function testMulNotRevertAnyExpectation(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN, EXPONENT_MAX / 2);
        exponentB = bound(exponentB, EXPONENT_MIN, EXPONENT_MAX / 2);
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.mulPayload(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(signedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(exponent, expectedExponent, "exponent");
    }

    /// `pow`'s squaring loop hands `mul` exponents up to `type(int128).max` in
    /// magnitude. At that bound, with the coefficients that lift the exponent
    /// the most, `mul` must still return rather than overflow.
    function testMulAtPowSquaringBoundUpper() external pure {
        int256 bound = type(int128).max;
        (, int256 exponent) = LibDecimalFloatImplementation.mul(type(int256).min, bound, type(int256).max, bound);
        assertEq(exponent - 2 * bound, 77);
    }

    function testMulAtPowSquaringBoundLower() external pure {
        int256 bound = type(int128).min;
        (, int256 exponent) = LibDecimalFloatImplementation.mul(type(int256).min, bound, type(int256).max, bound);
        assertEq(exponent - 2 * bound, 77);
    }

    /// The exact product floored to 256 bits as `mulPayload`, with the digits
    /// below `10^type(int256).min` truncated towards zero.
    function mulBelowFloorExpected(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal pure returns (int256, int256) {
        (int256 signedCoefficient, int256 shed) =
            LibTestExactDecimal.mulPayload(signedCoefficientA, 0, signedCoefficientB, 0);
        return LibTestExactDecimal.atFloor(signedCoefficient, exponentA - type(int256).min + exponentB + shed);
    }

    function checkMulBelowFloor(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal pure {
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            mulBelowFloorExpected(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        checkMul(
            signedCoefficientA, exponentA, signedCoefficientB, exponentB, expectedSignedCoefficient, expectedExponent
        );
    }

    /// The repro from #296.
    function testMulExponentSumBelowFloorIssueRepro() external pure {
        (int256 q, int256 qe) =
            LibDecimalFloatImplementation.div(19507 * -77, type(int256).min, -77, type(int256).min + 11002);
        (int256 back, int256 backE) = LibDecimalFloatImplementation.mul(q, qe, -77, type(int256).min + 11002);
        assertTrue(LibTestExactDecimal.eq(back, backE, 19507 * -77, type(int256).min));
    }

    /// The digits `mul` drops when the product is wider than 256 bits lift
    /// the exponent back above the floor without losing anything.
    function testMulExponentSumBelowFloorLiftedByAdjust() external pure {
        int256 min = type(int256).min;
        checkMul(1e76, min, 1e76, -50, 1e76, min + 26);
        checkMul(1e76, min, -1e76, -76, -1e76, min);
    }

    function testMulExponentSumBelowFloorShedsDigits() external pure {
        int256 min = type(int256).min;
        checkMul(1e76, min, 1e76, -77, 1e75, min);
        checkMul(-1e76, min, 1e76, -152, -1, min);
        checkMul(1e76, min, -1e76, -153, 0, 0);
        checkMul(type(int256).max, min, 1, -76, 5, min);
        checkMul(type(int256).max, min, 1, -77, 0, 0);
        checkMul(1, min, 1, -1, 0, 0);
        checkMul(1, min, 1, min, 0, 0);
        checkMul(type(int256).min, min, type(int256).min, min, 0, 0);
    }

    function testMulExponentSumBelowFloorExact(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        vm.assume(signedCoefficientA != 0 && signedCoefficientB != 0);
        exponentA = bound(exponentA, type(int256).min, -40);
        exponentB = bound(exponentB, type(int256).min, -40);
        checkMulBelowFloor(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Exponent sums within 80 of the floor, where the lift and the digit
    /// shedding meet.
    function testMulExponentSumNearFloorExact(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 offset
    ) external pure {
        vm.assume(signedCoefficientA != 0 && signedCoefficientB != 0);
        exponentA = bound(exponentA, type(int256).min + 100, -100);
        offset = bound(offset, -80, 80);
        checkMulBelowFloor(signedCoefficientA, exponentA, signedCoefficientB, type(int256).min - exponentA + offset);
    }

    function mulExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function checkMulExponentOverflow(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientA, exponentA));
        this.mulExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// The exponent sum itself overflows.
    function testMulExponentSumAboveCeiling() external {
        int256 max = type(int256).max;
        checkMul(1, max, 1, 0, 1, max);
        checkMulExponentOverflow(1, max, 1, 1);
        checkMulExponentOverflow(-1, 1, 1, max);
        checkMulExponentOverflow(1, max, 1, max);
    }

    /// Both repros from #325, and the second with its operands swapped.
    function testMulIssue325Repros() external {
        int256 max = type(int256).max;
        checkMulExponentOverflow(1, max, 1, 1);
        checkMulExponentOverflow(type(int256).min, max, -1, 0);
        checkMulExponentOverflow(-1, 0, type(int256).min, max);
    }

    /// The sum fits but the normalisation lift of up to 77 does not.
    function testMulExponentLiftAboveCeiling() external {
        int256 max = type(int256).max;
        int256 maxSquared = int256(3.3519519824856492748935062495514615318698414551480983444308903609304410075182e76);
        checkMul(max, max - 77, max, 0, maxSquared, max);
        checkMulExponentOverflow(max, max - 76, max, 0);
        checkMul(max, max, max, -77, maxSquared, max);
        checkMulExponentOverflow(max, max, max, -76);
    }

    /// The lift fits but the divide by 10 for a coefficient wider than int256
    /// does not.
    function testMulExponentCoefficientRescaleAboveCeiling() external {
        int256 max = type(int256).max;
        checkMul(1e76, max - 76, -1e76, 0, -1e76, max);
        checkMulExponentOverflow(1e76, max - 75, -1e76, 0);
    }

    /// The exponent guard's window edges: [-2^253, 2^253) skips the checks.
    function testMulExponentGuardEdges() external pure {
        int256 edge = 2 ** 253;
        checkMul(1, edge - 1, 1, edge - 1, 1, 2 * edge - 2);
        checkMul(1, edge, 1, edge, 1, 2 * edge);
        checkMul(1, -edge, 1, -edge, 1, -2 * edge);
        checkMul(1, -edge - 1, 1, -edge - 1, 1, -2 * edge - 2);
    }

    /// Both exponents in the guard window's upper margin wrap the sum.
    function testMulExponentGuardUpperMarginWraps() external {
        int256 e = 2 ** 254 + (2 ** 253 - 1);
        checkMulExponentOverflow(1, e, 1, e);
    }

    /// Both exponents below -2^254 wrap the sum past the floor.
    function testMulExponentGuardLowerMarginWraps() external pure {
        int256 e = -(2 ** 254) - 1;
        checkMul(1e70, e, 1, e, 1e68, type(int256).min);
    }

    function checkMulNearCeiling(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal {
        (int256 expectedSignedCoefficient, int256 normalisedExponent) =
            LibTestExactDecimal.productInt256(signedCoefficientA, signedCoefficientB);
        // exponentA is non-negative and exponentB + normalisedExponent small,
        // so neither side wraps.
        if (exponentB + normalisedExponent > type(int256).max - exponentA) {
            checkMulExponentOverflow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        } else {
            checkMul(
                signedCoefficientA,
                exponentA,
                signedCoefficientB,
                exponentB,
                expectedSignedCoefficient,
                exponentA + exponentB + normalisedExponent
            );
        }
    }

    function testMulExponentNearCeiling(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external {
        vm.assume(signedCoefficientA != 0 && signedCoefficientB != 0);
        exponentA = bound(exponentA, type(int256).max - 200, type(int256).max);
        exponentB = bound(exponentB, -200, 200);
        checkMulNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Small coefficients leave the normalisation at most a few digits, so
    /// the boundary sits next to the exponent sum.
    function testMulExponentNearCeilingSmallCoefficients(
        int64 signedCoefficientA,
        int256 exponentA,
        int64 signedCoefficientB,
        int256 exponentB
    ) external {
        vm.assume(signedCoefficientA != 0 && signedCoefficientB != 0);
        exponentA = bound(exponentA, type(int256).max - 100, type(int256).max);
        exponentB = bound(exponentB, -100, 100);
        checkMulNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Exponents anywhere in the upper half, mostly wrapping the sum.
    function testMulExponentAboveCeilingWide(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external {
        vm.assume(signedCoefficientA != 0 && signedCoefficientB != 0);
        exponentA = bound(exponentA, 0, type(int256).max);
        exponentB = bound(exponentB, 0, type(int256).max);
        (int256 expectedSignedCoefficient, int256 normalisedExponent) =
            LibTestExactDecimal.productInt256(signedCoefficientA, signedCoefficientB);
        if (exponentB > type(int256).max - exponentA - normalisedExponent) {
            checkMulExponentOverflow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        } else {
            checkMul(
                signedCoefficientA,
                exponentA,
                signedCoefficientB,
                exponentB,
                expectedSignedCoefficient,
                exponentA + exponentB + normalisedExponent
            );
        }
    }

    /// True iff `exponentA + exponentB + lift` is above `type(int256).max`,
    /// for `lift` in [0, 78].
    function exceedsCeiling(int256 exponentA, int256 exponentB, int256 lift) internal pure returns (bool) {
        if (exponentA >= 0) {
            if (exponentB > type(int256).max - exponentA) {
                return true;
            }
        } else if (exponentB < type(int256).min - exponentA) {
            return false;
        }
        return exponentA + exponentB > type(int256).max - lift;
    }

    /// Any operands: `mul` either returns or reverts `ExponentOverflow` with
    /// the first operand, and reverts iff the exact result exponent is above
    /// `type(int256).max`. Never a panic.
    function checkMulRevertsOnlyExponentOverflow(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal view {
        bool overflows = false;
        if (signedCoefficientA != 0 && signedCoefficientB != 0) {
            (, int256 lift) = LibTestExactDecimal.productInt256(signedCoefficientA, signedCoefficientB);
            overflows = exceedsCeiling(exponentA, exponentB, lift);
        }
        try this.mulExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) {
            assertFalse(overflows, "returned past the ceiling");
        } catch (bytes memory err) {
            assertEq(err, abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientA, exponentA), "revert");
            assertTrue(overflows, "reverted below the ceiling");
        }
    }

    function testMulRevertsOnlyExponentOverflow(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external view {
        checkMulRevertsOnlyExponentOverflow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// The same over every pairing of edge operands.
    function testMulRevertsOnlyExponentOverflowEdges() external view {
        int256 min = type(int256).min;
        int256 max = type(int256).max;
        int256[10] memory coefficients = [min, min + 1, -1e76, -10, -1, 1, 9, 1e76, max - 1, max];
        int256[16] memory exponents = [
            min,
            min + 1,
            min + 77,
            -(2 ** 254) - 1,
            -(2 ** 254),
            -(2 ** 253) - 1,
            -(2 ** 253),
            -1,
            0,
            1,
            2 ** 253 - 1,
            2 ** 253,
            2 ** 254,
            max - 78,
            max - 77,
            max
        ];
        for (uint256 ia = 0; ia < coefficients.length; ia++) {
            for (uint256 ib = 0; ib < coefficients.length; ib++) {
                for (uint256 ja = 0; ja < exponents.length; ja++) {
                    for (uint256 jb = 0; jb < exponents.length; jb++) {
                        checkMulRevertsOnlyExponentOverflow(
                            coefficients[ia], exponents[ja], coefficients[ib], exponents[jb]
                        );
                    }
                }
            }
        }
    }
}
