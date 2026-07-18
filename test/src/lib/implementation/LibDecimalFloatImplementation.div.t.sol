// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    DivisionByZero
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {THREES, ONES} from "../../../lib/LibCommonResults.sol";

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
        // The numerator exponent stays far enough inside the domain that the
        // result exponent cannot leave it.
        exponent = bound(exponent, EXPONENT_MIN / 2, EXPONENT_MAX);
        LibDecimalFloatImplementation.div(signedCoefficient, exponent, type(int256).max, type(int32).max);
    }

    /// A divisor exponent at `type(int256).min` is out of the arithmetic
    /// domain and is rejected before maximization can revert on it.
    function testDivMinPositiveValueDenominatorRevert(int256 signedCoefficient, int256 exponent) external {
        vm.assume(signedCoefficient != 0);
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, 1, type(int256).min));
        this.divExternal(signedCoefficient, exponent, 1, type(int256).min);
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

    /// a / a == 1 for all nonzero in-domain inputs.
    function testDivSelf(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        vm.assume(signedCoefficient != 0);

        (int256 resultCoeff, int256 resultExp) =
            LibDecimalFloatImplementation.div(signedCoefficient, exponent, signedCoefficient, exponent);
        assertTrue(LibDecimalFloatImplementation.eq(resultCoeff, resultExp, 1, 0), "a / a should equal 1");
    }

    /// Should be possible to divide every number by 1, as long as the
    /// maximized form of the number (which is the result) stays in the
    /// exponent domain.
    function testDivBy1(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN + 77, EXPONENT_MAX);
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);

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
        // EXPONENT_MAX itself is excluded: negating a maximized
        // type(int256).min coefficient there would need EXPONENT_MAX + 1.
        exponent = bound(exponent, EXPONENT_MIN + 77, EXPONENT_MAX - 1);
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);
        (expectedCoefficient, expectedExponent) =
            LibDecimalFloatImplementation.minus(expectedCoefficient, expectedExponent);

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
        exponentA = bound(exponentA, EXPONENT_MIN / 2 + 100, EXPONENT_MAX / 2 - 100);
        exponentB = bound(exponentB, EXPONENT_MIN / 2 + 100, EXPONENT_MAX / 2 - 100);

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

    /// Asserts the round trip identity `(a / b) * b == a` (as a value, via `eq`)
    /// for exact divisions. This pins both the quotient mantissa AND the exponent
    /// bookkeeping (including the `adjustExponent` constant selected for `b`),
    /// because a wrong `adjustExponent` would scale the quotient by a power of
    /// ten and break the equality.
    function checkDivInverse(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
    {
        (int256 q, int256 qe) =
            LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 back, int256 backE) = LibDecimalFloatImplementation.mul(q, qe, signedCoefficientB, exponentB);
        assertTrue(LibDecimalFloatImplementation.eq(back, backE, signedCoefficientA, exponentA), "(a / b) * b == a");
    }

    /// The scaling logic inside `div` selects an `adjustExponent` based on a
    /// binary search over the order of magnitude of the (maximized) divisor
    /// coefficient. The smaller-than-`1e75` leaves of that search are only
    /// reachable when the divisor cannot be maximized because its exponent sits
    /// at `type(int256).min` — but such an exponent is outside the arithmetic
    /// domain, so `div` rejects the divisor operand with `ExponentOverflow`
    /// before the search runs. Each leaf divisor below pins that rejection.
    function testDivAdjustExponentLeaves() external {
        int256 min = type(int256).min;
        // [div by, lands in sub-range)
        int256[16] memory divisors = [
            int256(3), // < 1e5
            3e6, // [1e5, 1e10)
            3e11, // [1e10, 1e14)
            3e15, // [1e14, 1e19)
            3e20, // [1e19, 1e23)
            3e24, // [1e23, 1e28)
            3e29, // [1e28, 1e33)
            3e34, // [1e33, 1e38)
            3e39, // [1e38, 1e43)
            3e44, // [1e43, 1e48)
            3e49, // [1e48, 1e53)
            3e54, // [1e53, 1e58)
            3e59, // [1e58, 1e63)
            3e64, // [1e63, 1e68)
            3e69, // [1e68, 1e73)
            3e73 // [1e73, 1e75) the "noop" leaf that keeps the starting 1e76 scale
        ];
        for (uint256 i = 0; i < divisors.length; i++) {
            int256 numerator = 3 * divisors[i];
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, divisors[i], min));
            this.divExternal(numerator, 0, divisors[i], min);
        }
    }

    /// A divisor sitting exactly on a power-of-ten boundary of the binary
    /// search is still an out-of-domain operand at `type(int256).min` and is
    /// rejected before the search runs.
    function testDivAdjustExponentBoundaries() external {
        int256 min = type(int256).min;
        int256[14] memory boundaries =
            [int256(1e5), 1e10, 1e14, 1e19, 1e23, 1e28, 1e33, 1e38, 1e43, 1e48, 1e53, 1e58, 1e63, 1e68];
        for (uint256 i = 0; i < boundaries.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, boundaries[i], min));
            this.divExternal(boundaries[i], 0, boundaries[i], min);
        }
    }

    /// When the maximized divisor coefficient is full (>= 1e75) but still less
    /// than 1e76, `div` takes the dedicated `scale = 1e75` / `adjustExponent = 75`
    /// branch rather than the binary search. A coefficient in
    /// `[int256.max / 10, 1e76)` cannot grow another order of magnitude, so
    /// maximization leaves it below 1e76 even with an in-domain exponent.
    function testDivAdjustExponentFullDivisor() external pure {
        // maximize(6e75) stops at 6e75 because 6e76 would overflow int256, so
        // fullB holds with 6e75 < 1e76. 1.2e76 / 6e75 == 2 exactly.
        (int256 q, int256 qe) = LibDecimalFloatImplementation.div(1.2e76, 0, 6e75, 0);
        assertEq(q, 2e75, "full divisor quotient mantissa");
        assertEq(qe, -75, "full divisor quotient exponent");
        (int256 back, int256 backE) = LibDecimalFloatImplementation.mul(q, qe, 6e75, 0);
        assertTrue(LibDecimalFloatImplementation.eq(back, backE, 1.2e76, 0), "full divisor round trip");
    }

    /// When the maximized divisor coefficient is already >= 1e76 the whole
    /// scaling block is skipped and the starting `adjustExponent = 76` is used.
    function testDivAdjustExponentLargeDivisor() external pure {
        // 3e76 >= 1e76 so the `if (signedCoefficientBAbs < scale)` block is skipped.
        checkDivInverse(3e76, 0, 3e76, 0);
    }

    /// The exponent-adjustment spill from `exponentA` onto `exponentB` only
    /// engages when `exponentA` sits at `type(int256).min` — an out-of-domain
    /// operand, rejected before the spill machinery runs.
    function testDivAdjustExponentSpillsToExponentB() external {
        int256 min = type(int256).min;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, 1e76, min));
        this.divExternal(1e76, min, 3e75, min);
    }

    /// The spill-overflow-to-zero path likewise requires operands at the
    /// int256 extremes, which are out-of-domain and rejected up front.
    function testDivAdjustExponentSpillOverflowReturnsZero() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, 1e76, type(int256).min));
        this.divExternal(1e76, type(int256).min, 3e75, type(int256).max);
    }

    /// A division whose operands sit at the int256 exponent extremes is
    /// rejected as out-of-domain rather than underflowing to zero.
    function testDivUnderflowReturnsZero() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, 1e76, type(int256).min));
        this.divExternal(1e76, type(int256).min, 3, type(int256).max);
    }

    /// A division whose true result exponent lands below `EXPONENT_MIN` from
    /// in-domain operands reverts `ExponentOverflow` on the result instead of
    /// returning a truncated value at an out-of-domain exponent.
    function testDivInDomainOperandsResultBelowDomainReverts() external {
        // 1e(EXPONENT_MIN) / 1e(EXPONENT_MAX): both operands are in-domain but
        // the true result exponent is ~2 * EXPONENT_MIN, far below the domain.
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, 100, type(int256).min));
        this.divExternal(1, EXPONENT_MIN, 1, EXPONENT_MAX);
    }
}
