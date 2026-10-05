// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

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
        assertTrue(
            LibDecimalFloatImplementation.eq(resultCoeff, resultExp, signedCoefficient, exponent),
            "a * 1 should equal a"
        );
    }

    /// a * b == b * a for all in-range inputs.
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

        assertEq(coeffAB, coeffBA, "commutative coefficient");
        assertEq(expAB, expBA, "commutative exponent");
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
            LibDecimalFloatSlow.mulSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
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

    /// `mul` in a frame shifted up by 2^254 per operand, with the exponent
    /// moved back down and lifted to `type(int256).min` by shedding digits.
    function mulBelowFloorExpected(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal pure returns (int256, int256) {
        int256 shift = 2 ** 254;
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(
            signedCoefficientA, exponentA + shift, signedCoefficientB, exponentB + shift
        );
        if (exponent >= 0) {
            return (signedCoefficient, exponent + type(int256).min);
        }
        if (exponent < -76) {
            return (0, 0);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        signedCoefficient /= int256(10 ** uint256(-exponent));
        return (signedCoefficient, signedCoefficient == 0 ? int256(0) : type(int256).min);
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
        assertTrue(LibDecimalFloatImplementation.eq(back, backE, 19507 * -77, type(int256).min));
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
        checkMul(1, min, 1, -1, 0, 0);
        checkMul(1, min, 1, min, 0, 0);
        checkMul(type(int256).min, min, type(int256).min, min, 0, 0);
    }

    function testMulExponentSumBelowFloorMatchesShifted(
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
    function testMulExponentSumNearFloorMatchesShifted(
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
}
