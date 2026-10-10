// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    DivisionByZero,
    ExponentOverflow
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {THREES, ONES} from "../../../lib/LibCommonResults.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatImplementationDivTest is Test {
    function divExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function checkDiv(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 signedCoefficientC,
        int256 exponentC
    ) internal pure {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, signedCoefficientC, "coefficient");
        assertEq(exponent, exponentC, "exponent");
    }

    function testDivZero(int256 signedCoefficient, int256 exponent) external {
        exponent = bound(exponent, type(int256).min / 2, type(int256).max);
        vm.expectRevert(abi.encodeWithSelector(DivisionByZero.selector, signedCoefficient, exponent));
        this.divExternal(signedCoefficient, exponent, 0, 0);
    }

    function testDivMaxPositiveValueDenominatorNotRevert(int256 signedCoefficient, int256 exponent) external pure {
        LibDecimalFloatImplementation.div(signedCoefficient, exponent, type(int256).max, type(int32).max);
    }

    /// A ±1 divisor at the floor divides exactly when the quotient exponent
    /// fits in int256, and reverts `ExponentOverflow` when it does not.
    function testDivByOneAtFloor(int256 signedCoefficient, int256 exponent, bool negative) external {
        vm.assume(signedCoefficient != 0);
        int256 one = negative ? int256(-1) : int256(1);
        // The quotient is ±m * 10^(exponent - shift - type(int256).min). At
        // exponent 0 the shift never reaches the floor, so it is -mExponent.
        (int256 m, int256 mExponent,) = LibTestExactDecimal.maximize(signedCoefficient, 0);
        int256 shift = -mExponent;
        if (exponent >= shift) {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, m, exponent - shift));
            this.divExternal(signedCoefficient, exponent, one, type(int256).min);
            return;
        }
        int256 qe;
        // qe is in [-76, type(int256).max], so the wrapping terms cancel.
        unchecked {
            qe = exponent - shift - type(int256).min;
        }
        if (negative) {
            if (m == type(int256).min) {
                // 2^255 does not fit, so it sheds a digit into the exponent.
                if (qe == type(int256).max) {
                    vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, m, exponent));
                    this.divExternal(signedCoefficient, exponent, one, type(int256).min);
                    return;
                }
                m /= 10;
                qe++;
            }
            m = -m;
        }
        checkDiv(signedCoefficient, exponent, one, type(int256).min, m, qe);
    }

    /// #320: 2^255 * 10^type(int256).max has no representation.
    function testDivMinByMinusOneAtFloorOverflows() external {
        int256 min = type(int256).min;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, min, -1));
        this.divExternal(min, -1, -1, min);
    }

    /// The neighbours of the #320 counterexample divide.
    function testDivMinByOneAtFloorNearMax() external pure {
        int256 min = type(int256).min;
        checkDiv(min, -1, 1, min, min, type(int256).max);
        checkDiv(min, -2, -1, min, -(min / 10), type(int256).max);
        checkDiv(min, -2, 1, min, min, type(int256).max - 1);
    }

    /// A negative divisor that is not a power of ten leaves a quotient under
    /// 2^255, so the exponent can be exactly `type(int256).max`.
    function testDivMinByNegativeNonPowerOfTenAtMax() external pure {
        checkDiv(
            type(int256).min,
            type(int256).max,
            -3,
            0,
            19298681539552699237261830834781317975544997444273427339909597334652188273322,
            type(int256).max
        );
    }

    function testDivOneByOneAtFloor() external pure {
        int256 min = type(int256).min;
        checkDiv(1, min, 1, min, 1e76, -76);
        checkDiv(-1, min, 1, min, -1e76, -76);
        checkDiv(1, min, -1, min, -1e76, -76);
        checkDiv(-1, min, -1, min, 1e76, -76);
    }

    /// A power of ten divisor at the floor loses no quotient digit.
    function testDivByUnfullPowerOfTenAtFloor() external pure {
        int256 min = type(int256).min;
        int256 divisor = 10;
        for (int256 k = 1; k <= 74; ++k) {
            checkDiv(1, min, divisor, min, 1e76, -76 - k);
            divisor *= 10;
        }
    }

    /// The quotient exponent is exactly `type(int256).max` on one side of the
    /// boundary and overflows on the other.
    function testDivExponentOverflowBoundary() external {
        checkDiv(1e76, 75, 1, type(int256).min + 76, 1e76, type(int256).max);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, 1e76, 0));
        this.divExternal(1e76, 76, 1, type(int256).min + 76);
    }

    /// An unfull divisor at the floor overflows the quotient exponent for a
    /// numerator with a non-negative maximized exponent.
    function testDivUnfullDivisorExponentOverflow() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, 1e76, 924));
        this.divExternal(1, 1000, 3, type(int256).min);
    }

    /// 1 / 3 gas by parts 10
    function testDiv1Over3Gas10() external pure {
        (int256 c, int256 e) = LibDecimalFloatImplementation.div(1, 0, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
    }

    /// 1 / 3
    function testDiv1Over3() external pure {
        checkDiv(1, 0, 3, 0, THREES, -76);
    }

    /// - 1 / 3
    function testDivNegative1Over3() external pure {
        checkDiv(-1, 0, 3, 0, -THREES, -76);
    }

    /// 1 / 3 gas
    function testDiv1Over3Gas0() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.div(1e37, -37, 3e37, -37);
        (signedCoefficient, exponent);
    }

    /// 1e18 / 3
    function testDiv1e18Over3() external pure {
        checkDiv(1e18, 0, 3, 0, THREES, -58);
    }

    /// 10,0 / 1e38,-37 == 1
    function testDivTenOverOOMs() external pure {
        checkDiv(10, 0, 1e38, -37, 1e76, -76);
    }

    /// 1e38,-37 / 2,0 == 5
    function testDivOOMsOverTen() external pure {
        checkDiv(1e38, -37, 2, 0, 5e75, -75);
    }

    /// 5e37,-37 / 2e37,-37 == 2.5
    function testDivOOMs5and2() external pure {
        checkDiv(5e37, -37, 2e37, -37, 2.5e76, -76);
    }

    /// (1 / 9) / (1 / 3) == 0.333..
    function testDiv1Over9Over1Over3() external pure {
        // 1 / 9
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloatImplementation.div(1, 0, 9, 0);
        assertEq(signedCoefficientA, ONES);
        assertEq(exponentA, -76);

        // 1 / 3
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloatImplementation.div(1, 0, 3, 0);
        assertEq(signedCoefficientB, THREES);
        assertEq(exponentB, -76);

        // (1 / 9) / (1 / 3)
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, THREES);
        assertEq(exponent, -76);

        // (1 / 3) / (1 / 9) == 3
        (signedCoefficient, exponent) =
            LibDecimalFloatImplementation.div(signedCoefficientB, exponentB, signedCoefficientA, exponentA);
        assertEq(signedCoefficient, 3e76);
        assertEq(exponent, -76);
    }

    /// a / a == 1 for all nonzero in-range inputs.
    function testDivSelf(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, type(int256).min / 2 + 76, type(int256).max);
        vm.assume(signedCoefficient != 0);

        (int256 resultCoeff, int256 resultExp) =
            LibDecimalFloatImplementation.div(signedCoefficient, exponent, signedCoefficient, exponent);
        assertTrue(LibTestExactDecimal.eq(resultCoeff, resultExp, 1, 0), "a / a should equal 1");
    }

    /// Should be possible to divide every number by 1.
    function testDivBy1(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, type(int256).min + 76, type(int256).max);
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.maximizeFloat(signedCoefficient, exponent);

        int256 one = 1;
        for (int256 oneExponent = 0; oneExponent >= -76; --oneExponent) {
            checkDiv(signedCoefficient, exponent, one, oneExponent, expectedCoefficient, expectedExponent);
            if (oneExponent == -76) {
                break;
            }
            one *= 10;
        }
    }

    function testDivByNegativeOneFloat(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, type(int256).min + 76, type(int256).max - 1);
        (int256 maximized, int256 maximizedExponent) = LibTestExactDecimal.maximizeFloat(signedCoefficient, exponent);
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.signedParts(maximized > 0, LibTestExactDecimal.abs(maximized), maximizedExponent);

        int256 negativeOne = -1;
        for (int256 oneExponent = 0; oneExponent >= -76; --oneExponent) {
            checkDiv(signedCoefficient, exponent, negativeOne, oneExponent, expectedCoefficient, expectedExponent);
            if (oneExponent == -76) {
                break;
            }
            negativeOne *= 10;
        }
    }

    /// forge-config: default.fuzz.runs = 100
    function testUnnormalizedThreesDiv0(int256 exponentA, int256 exponentB) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 2, EXPONENT_MAX / 2);
        exponentB = bound(exponentB, EXPONENT_MIN / 2, EXPONENT_MAX / 2);

        int256 d = 3;
        int256 di = 0;
        while (true) {
            int256 i = 1;
            int256 j = -76 - di;
            while (true) {
                // want to see full precision on the THREES regardless of the
                // scale of the numerator and denominator.
                checkDiv(i, exponentA, d, exponentB, THREES, exponentA - exponentB + j);

                if (i == 1e76) {
                    break;
                }

                i *= 10;
                ++j;
            }

            if (d == 3e76) {
                break;
            }
            d *= 10;
            ++di;
        }
    }

    /// Asserts `(a / b) * b == a` exactly for exact divisions. This pins both the quotient mantissa AND the exponent
    /// bookkeeping (including the `adjustExponent` constant selected for `b`),
    /// because a wrong `adjustExponent` would scale the quotient by a power of
    /// ten and break the equality.
    function checkDivInverse(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
    {
        (int256 q, int256 qe) =
            LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertTrue(
            LibTestExactDecimal.productEq(q, qe, signedCoefficientB, exponentB, signedCoefficientA, exponentA),
            "(a / b) * b == a"
        );
    }

    /// A divisor at `type(int256).min` with every digit count its shortfall
    /// can take. Each row divides `3 * d` by `d`, an exact `3`, so the quotient
    /// mantissa is always the maximized `3` (i.e. `3e75`) and the round trip
    /// must hold.
    function testDivAdjustExponentLeaves() external pure {
        int256 min = type(int256).min;
        int256[16] memory divisors =
            [int256(3), 3e6, 3e11, 3e15, 3e20, 3e24, 3e29, 3e34, 3e39, 3e44, 3e49, 3e54, 3e59, 3e64, 3e69, 3e73];
        for (uint256 i = 0; i < divisors.length; i++) {
            int256 numerator = 3 * divisors[i];
            (int256 q, int256 qe) = LibDecimalFloatImplementation.div(numerator, 0, divisors[i], min);
            // A single significant figure "3" maximizes to 76 digits, i.e. 3e75.
            assertEq(q, 3e75, "quotient mantissa");
            // The exponent is enormous (close to -type(int256).min) so it is
            // pinned by the round trip rather than a literal here.
            assertTrue(LibTestExactDecimal.productEq(q, qe, divisors[i], min, numerator, 0), "round trip");
        }
    }

    /// A power of ten divisor at the floor divides a power of ten exactly.
    function testDivAdjustExponentBoundaries() external pure {
        int256 min = type(int256).min;
        int256[14] memory boundaries =
            [int256(1e5), 1e10, 1e14, 1e19, 1e23, 1e28, 1e33, 1e38, 1e43, 1e48, 1e53, 1e58, 1e63, 1e68];
        for (uint256 i = 0; i < boundaries.length; i++) {
            checkDivInverse(boundaries[i], 0, boundaries[i], min);
        }
    }

    /// A maximized divisor below 1e76 takes `scale = 1e75` /
    /// `adjustExponent = 75`. `6e75 * 10` overflows, so it stays below 1e76.
    function testDivAdjustExponentFullDivisor() external pure {
        int256 min = type(int256).min;
        (int256 q, int256 qe) = LibDecimalFloatImplementation.div(18e75, 0, 6e75, min);
        assertEq(q, 3e75, "full divisor quotient mantissa");
        assertTrue(LibTestExactDecimal.productEq(q, qe, 6e75, min, 18e75, 0), "full divisor round trip");
    }

    /// A maximized divisor at or above 1e76 keeps the starting
    /// `adjustExponent = 76`.
    function testDivAdjustExponentLargeDivisor() external pure {
        int256 min = type(int256).min;
        checkDivInverse(3e76, 0, 3e76, min);
    }

    /// The exponent adjustment is first applied to `exponentA`. When `exponentA`
    /// is already at `type(int256).min` the leftover adjustment spills over onto
    /// `exponentB` instead.
    function testDivAdjustExponentSpillsToExponentB() external pure {
        int256 min = type(int256).min;
        // 1e76 * 10^min / (3e75 * 10^min) == 10/3.
        checkDiv(1e76, min, 3e75, min, THREES, -75);
    }

    /// When the adjustment cannot be applied to `exponentA` (already at the
    /// minimum) and applying the remainder to `exponentB` would overflow it past
    /// `type(int256).max`, `div` returns maximized zero.
    function testDivAdjustExponentSpillOverflowReturnsZero() external pure {
        checkDiv(1e76, type(int256).min, 3e75, type(int256).max, 0, 0);
    }

    /// A division whose true exponent underflows below what a single result can
    /// represent returns maximized zero.
    function testDivUnderflowReturnsZero() external pure {
        checkDiv(1e76, type(int256).min, 3, type(int256).max, 0, 0);
    }

    /// A numerator that cannot be maximized because its exponent is pinned at
    /// `type(int256).min` keeps full precision.
    function testDivUnfullNumeratorOneThird() external pure {
        checkDiv(1, type(int256).min, 3, type(int256).min, THREES, -76);
        checkDiv(-1, type(int256).min, 3, type(int256).min, -THREES, -76);
    }

    /// An unfull numerator over a divisor that maximizes past `1e76`.
    function testDivUnfullNumeratorLargeDivisor() external pure {
        checkDiv(1, type(int256).min, 3, type(int256).min + 76, THREES, -152);
    }

    /// A numerator at the floor, full or not, divides to the exact quotient
    /// floored as `divParts`, which only the exponent difference reaches.
    function testDivFloorNumeratorExact(int256 signedCoefficientA, int256 signedCoefficientB, int256 shift)
        external
        pure
    {
        vm.assume(signedCoefficientA != 0);
        vm.assume(signedCoefficientB != 0);
        shift = bound(shift, 76, type(int128).max);
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.divParts(signedCoefficientA, 0, signedCoefficientB, shift);
        checkDiv(
            signedCoefficientA,
            type(int256).min,
            signedCoefficientB,
            type(int256).min + shift,
            expectedCoefficient,
            expectedExponent
        );
    }

    /// Both operands near the floor, either one short of its full shift,
    /// divide to the exact quotient floored as `divParts`.
    function testDivNearFloorExact(
        int256 signedCoefficientA,
        int256 signedCoefficientB,
        uint256 headroomA,
        uint256 headroomB
    ) external pure {
        vm.assume(signedCoefficientA != 0);
        vm.assume(signedCoefficientB != 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentA = int256(bound(headroomA, 0, 80));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentB = int256(bound(headroomB, 0, 80));
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.divParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        checkDiv(
            signedCoefficientA,
            type(int256).min + exponentA,
            signedCoefficientB,
            type(int256).min + exponentB,
            expectedCoefficient,
            expectedExponent
        );
    }

    /// A 76 digit numerator at the floor divides with all 77 digits.
    function testDivFullNumeratorAtFloorKeepsLastDigit() external pure {
        int256 a = -1721758284977530853596865604091066801911468845366650376773079384479962783021;
        int256 b = -868809616206213416579646778253544419036053804;
        (int256 q, int256 qe) = LibDecimalFloatImplementation.div(a, type(int256).min, b, type(int256).min + 76);
        assertEq(q, 1981744047097274120016830328557190949665214948375329466032481915679868495689, "coefficient");
        (int256 shifted, int256 shiftedExponent) = LibDecimalFloatImplementation.div(a, 0, b, 76);
        assertEq(q, shifted, "shifted coefficient");
        assertEq(qe, shiftedExponent, "shifted exponent");
    }

    /// Signs are the exclusive or of the operand signs for an unfull numerator.
    function testDivUnfullNumeratorSigns() external pure {
        int256 min = type(int256).min;
        checkDiv(1, min, 3, min, THREES, -76);
        checkDiv(-1, min, 3, min, -THREES, -76);
        checkDiv(1, min, -3, min, -THREES, -76);
        checkDiv(-1, min, -3, min, THREES, -76);
        checkDiv(1, min, 3, min + 76, THREES, -152);
        checkDiv(-1, min, 3, min + 76, -THREES, -152);
        checkDiv(1, min, -3, min + 76, -THREES, -152);
        checkDiv(-1, min, -3, min + 76, THREES, -152);
    }

    /// Every numerator digit count that is one digit short or more at the
    /// floor, so every amount of digits the exponent cannot take, over both a
    /// small and a large maximized divisor.
    function testDivFloorNumeratorEveryDigitCount() external pure {
        int256 min = type(int256).min;
        int256 numerator = 1;
        for (int256 digits = 1; digits <= 76; ++digits) {
            checkDiv(numerator, min, 3, min, THREES, -77 + digits);
            checkDiv(-numerator, min, 3, min, -THREES, -77 + digits);
            checkDiv(numerator, min, 3, min + 76, THREES, -153 + digits);
            (int256 quotient, int256 quotientExponent) = LibDecimalFloatImplementation.div(numerator * 7, min, 7, min);
            assertTrue(LibTestExactDecimal.eq(quotient, quotientExponent, 1, digits - 1), "7n / 7 == n");
            numerator *= 10;
        }
    }

    /// The unabsorbed digits push exponentB past `type(int256).max`, so the
    /// quotient is maximized zero.
    function testDivUnfullNumeratorSpillOverflowReturnsZero() external pure {
        int256 max = type(int256).max;
        checkDiv(1, type(int256).min, 3e76, max - 100, 0, 0);
        checkDiv(-1, type(int256).min, 3e76, max - 100, 0, 0);
    }

    /// `(a / b) * b == a` for exact divisions of an unfull numerator.
    function testDivUnfullNumeratorMulRoundTrip(int256 quotient, int256 divisor, int256 shift) external pure {
        quotient = bound(quotient, -1e37, 1e37);
        divisor = bound(divisor, -1e37, 1e37);
        vm.assume(quotient != 0);
        vm.assume(divisor != 0);
        shift = bound(shift, 0, type(int128).max);
        int256 numerator = quotient * divisor;
        (int256 q, int256 qe) =
            LibDecimalFloatImplementation.div(numerator, type(int256).min, divisor, type(int256).min + shift);
        // Both sides divided by 10^type(int256).min.
        assertTrue(LibTestExactDecimal.productEq(q, qe, divisor, shift, numerator, 0), "(a / b) * b == a");
    }
}
