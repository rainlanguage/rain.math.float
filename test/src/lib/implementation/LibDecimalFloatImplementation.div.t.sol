// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    DivisionByZero,
    MaximizeOverflow
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
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
        LibDecimalFloatImplementation.div(signedCoefficient, exponent, type(int256).max, type(int32).max);
    }

    function testDivMinPositiveValueDenominatorRevert(int256 signedCoefficient, int256 exponent) external {
        vm.assume(signedCoefficient != 0);
        vm.expectRevert(abi.encodeWithSelector(MaximizeOverflow.selector, 1, type(int256).min));
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

    /// a / a == 1 for all nonzero in-range inputs.
    function testDivSelf(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, type(int256).min / 2 + 76, type(int256).max);
        vm.assume(signedCoefficient != 0);

        (int256 resultCoeff, int256 resultExp) =
            LibDecimalFloatImplementation.div(signedCoefficient, exponent, signedCoefficient, exponent);
        assertTrue(LibDecimalFloatImplementation.eq(resultCoeff, resultExp, 1, 0), "a / a should equal 1");
    }

    /// Should be possible to divide every number by 1.
    function testDivBy1(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, type(int256).min + 76, type(int256).max);
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
        exponent = bound(exponent, type(int256).min + 76, type(int256).max - 1);
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
    /// at `type(int256).min`, leaving the coefficient at its given magnitude.
    ///
    /// Each row below places `9 * 10^j / 3 * 10^j` (an exact `3`) with the
    /// divisor pinned to `type(int256).min` so that `3 * 10^j` lands strictly
    /// inside one sub-range of the binary search. The quotient mantissa is
    /// therefore always the maximized `3` (i.e. `3e75`) and the round trip must
    /// hold regardless of which sub-range was selected.
    function testDivAdjustExponentLeaves() external pure {
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
            (int256 q, int256 qe) = LibDecimalFloatImplementation.div(numerator, 0, divisors[i], min);
            // A single significant figure "3" maximizes to 76 digits, i.e. 3e75.
            assertEq(q, 3e75, "quotient mantissa");
            // The exponent is enormous (close to -type(int256).min) so it is
            // pinned by the round trip rather than a literal here.
            (int256 back, int256 backE) = LibDecimalFloatImplementation.mul(q, qe, divisors[i], min);
            assertTrue(LibDecimalFloatImplementation.eq(back, backE, numerator, 0), "round trip");
        }
    }

    /// Each binary search boundary is `< scale` (strict), so a divisor sitting
    /// exactly on a power-of-ten boundary falls into the higher sub-range. This
    /// exercises the boundary comparisons themselves rather than the interiors.
    function testDivAdjustExponentBoundaries() external pure {
        int256 min = type(int256).min;
        int256[14] memory boundaries =
            [int256(1e5), 1e10, 1e14, 1e19, 1e23, 1e28, 1e33, 1e38, 1e43, 1e48, 1e53, 1e58, 1e63, 1e68];
        for (uint256 i = 0; i < boundaries.length; i++) {
            // A divisor of exactly 10^k divides any 10^m numerator exactly.
            checkDivInverse(boundaries[i], 0, boundaries[i], min);
        }
    }

    /// When the maximized divisor coefficient is full (>= 1e75) but still less
    /// than 1e76, `div` takes the dedicated `scale = 1e75` / `adjustExponent = 75`
    /// branch rather than the binary search.
    function testDivAdjustExponentFullDivisor() external pure {
        int256 min = type(int256).min;
        // 3e75 has 76 digits, so 3e75 / 1e75 == 3 != 0 => "full", but 3e75 < 1e76.
        (int256 q, int256 qe) = LibDecimalFloatImplementation.div(9e75, 0, 3e75, min);
        assertEq(q, 3e75, "full divisor quotient mantissa");
        (int256 back, int256 backE) = LibDecimalFloatImplementation.mul(q, qe, 3e75, min);
        assertTrue(LibDecimalFloatImplementation.eq(back, backE, 9e75, 0), "full divisor round trip");
    }

    /// When the maximized divisor coefficient is already >= 1e76 the whole
    /// scaling block is skipped and the starting `adjustExponent = 76` is used.
    function testDivAdjustExponentLargeDivisor() external pure {
        int256 min = type(int256).min;
        // 3e76 >= 1e76 so the `if (signedCoefficientBAbs < scale)` block is skipped.
        checkDivInverse(3e76, 0, 3e76, min);
    }

    /// The exponent adjustment is first applied to `exponentA`. When `exponentA`
    /// is already at `type(int256).min` the leftover adjustment spills over onto
    /// `exponentB` instead.
    function testDivAdjustExponentSpillsToExponentB() external pure {
        int256 min = type(int256).min;
        // 1e76 is full at any exponent, so fullA holds even at min, avoiding the
        // MaximizeOverflow revert while forcing the spill-to-exponentB path.
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
}
