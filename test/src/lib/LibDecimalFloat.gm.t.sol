// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibDecimalFloat, Float} from "../../../src/lib/LibDecimalFloat.sol";
import {LibExactFloat, U512} from "../../lib/LibExactFloat.sol";

contract LibDecimalFloatGmTest is Test {
    using LibDecimalFloat for Float;

    function f(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    function checkGm(Float a, Float b, Float expected) internal pure {
        assertEq(Float.unwrap(a.gm(b)), Float.unwrap(expected), "gm");
    }

    function gmExternal(Float a, Float b) external pure returns (Float) {
        return a.gm(b);
    }

    /// Roots correctly rounded at 41 digits, as `sqrt` of the product.
    function testGmValues() external pure {
        checkGm(f(1, 0), f(1, 0), f(1, 0));
        checkGm(f(1, 0), f(2, 0), f(14142135623730950488016887242096980785697, -40));
        checkGm(f(2, 0), f(2, 0), f(2, 0));
        checkGm(f(2e40, -40), f(2, 0), f(2e40, -40));
        checkGm(f(2, 0), f(3, 0), f(24494897427831780981972840747058913919659, -40));
        checkGm(f(2, 0), f(4, 0), f(28284271247461900976033774484193961571393, -40));
        checkGm(f(4, 0), f(5, -1), f(14142135623730950488016887242096980785697, -40));
        checkGm(f(2, 0), f(8, 0), f(4e40, -40));
        checkGm(f(1, -2), f(1, 2), f(1e40, -40));
    }

    /// A product of exactly 1e76 is past `sqrt`'s coefficient range.
    function testGmProductAtCoefficientCeiling() external pure {
        checkGm(f(1e38, 0), f(1e38, 0), f(1e38, 0));
        checkGm(f(1e38, 0), f(-1e38, 0), f(-1e38, 0));
        checkGm(f(1e37, 0), f(1e39, 0), f(1e40, -2));
    }

    /// A 76-digit product's last digit decides the rounding: `N - r^2 - r` is
    /// 185494 for `N = 1e6 a b`, so the root rounds up.
    function testGmRoundsOn76DigitProduct() external pure {
        checkGm(
            f(2500000142500000000000000000000003162277750000000000000000000000001, 0),
            f(1000000057, 0),
            f(50000002850000000000000000000000031622778, -3)
        );
    }

    /// A root rounding onto the larger input takes that input's representation.
    function testGmRootRoundedOntoLargerInput() external pure {
        Float a = f(19999999999999999999999999999999999999999999999999999, -52);
        checkGm(a, f(2, 0), f(2, 0));
        checkGm(f(2, 0), a, f(2, 0));
        checkGm(a.minus(), f(2, 0), f(-2, 0));
    }

    /// Equal magnitudes encoded differently give the same bytes in either
    /// order: the smaller coefficient's when the root is at or below them, the
    /// larger's when it rounds above.
    function testGmEqualMagnitudesDifferentEncodings() external pure {
        Float one = f(1, 0);
        Float oneScaled = f(10, -1);
        checkGm(one, oneScaled, one);
        checkGm(oneScaled, one, one);
        checkGm(one.minus(), oneScaled, one.minus());
        checkGm(oneScaled, one.minus(), one.minus());
        checkGm(one, oneScaled.minus(), one.minus());
        checkGm(oneScaled.minus(), one, one.minus());
        checkGm(one.minus(), oneScaled.minus(), one);
        checkGm(oneScaled.minus(), one.minus(), one);

        Float near = f(19999999999999999999999999999999999999999999999999999, -52);
        Float nearScaled = f(199999999999999999999999999999999999999999999999999990, -53);
        checkGm(near, nearScaled, nearScaled);
        checkGm(nearScaled, near, nearScaled);
        checkGm(near.minus(), nearScaled, nearScaled.minus());
        checkGm(nearScaled, near.minus(), nearScaled.minus());
        checkGm(near, nearScaled.minus(), nearScaled.minus());
        checkGm(nearScaled.minus(), near, nearScaled.minus());
        checkGm(near.minus(), nearScaled.minus(), nearScaled);
        checkGm(nearScaled.minus(), near.minus(), nearScaled);
    }

    /// Negative iff exactly one input is negative.
    function testGmSigns() external pure {
        checkGm(f(-1, 0), f(1, 0), f(-1, 0));
        checkGm(f(1, 0), f(-1, 0), f(-1, 0));
        checkGm(f(-1, 0), f(-1, 0), f(1, 0));
        checkGm(f(-2, 0), f(3, 0), f(-24494897427831780981972840747058913919659, -40));
        checkGm(f(2, 0), f(-3, 0), f(-24494897427831780981972840747058913919659, -40));
        checkGm(f(-2, 0), f(-3, 0), f(24494897427831780981972840747058913919659, -40));
    }

    /// A zero input, at any exponent and with any other input, is
    /// `FLOAT_ZERO`, whatever the other's sign.
    function testGmZero(uint32 exponent, Float other) external pure {
        Float zero = Float.wrap(bytes32(uint256(exponent) << 224));
        checkGm(zero, other, LibDecimalFloat.FLOAT_ZERO);
        checkGm(other, zero, LibDecimalFloat.FLOAT_ZERO);
    }

    function testGmZeroExamples() external pure {
        checkGm(f(0, 0), f(0, 0), LibDecimalFloat.FLOAT_ZERO);
        checkGm(f(0, 0), f(1, 0), LibDecimalFloat.FLOAT_ZERO);
        checkGm(f(1, 0), f(0, 0), LibDecimalFloat.FLOAT_ZERO);
        checkGm(f(0, 0), f(-1, 0), LibDecimalFloat.FLOAT_ZERO);
        checkGm(f(-1, 0), f(0, 0), LibDecimalFloat.FLOAT_ZERO);
    }

    /// The mean lies between the inputs' magnitudes, so the largest and
    /// smallest Floats are their own means, and a product past every Float
    /// has one.
    function testGmLimits() external pure {
        Float max = LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE;
        Float minPositive = LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE;
        Float minNegative = LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE;
        checkGm(max, max, max);
        checkGm(max.minus(), max.minus(), max);
        checkGm(max, max.minus(), max.minus());
        checkGm(minNegative, minNegative, max);
        checkGm(minNegative, max, minNegative);
        checkGm(minPositive, minPositive, minPositive);
        checkGm(minPositive.minus(), minPositive, minPositive.minus());
        checkGm(minPositive, f(4, type(int32).min), f(2, type(int32).min));
        checkGm(minPositive, f(2, type(int32).min), minPositive);
        checkGm(f(1, 2e9), f(1, 2e9), f(1, 2e9));
        checkGm(f(1, -2e9), f(1, -2e9), f(1, -2e9));
        checkGm(max, minPositive, f(11610328735042483669965322070309339564089, -7));
        assertTrue(f(1, type(int32).max).gm(f(1, type(int32).max - 2)).eq(f(1, type(int32).max - 1)), "1e(max - 1)");
    }

    /// No pair of Floats reverts, and the mean is symmetric.
    function testGmNeverRevertsSymmetric(Float a, Float b) external view {
        Float ab = this.gmExternal(a, b);
        assertEq(Float.unwrap(ab), Float.unwrap(this.gmExternal(b, a)), "symmetric");
    }

    /// The mean of a value with itself, or with its negation, is its
    /// magnitude, signed.
    function testGmSelf(Float a) external pure {
        checkGm(a, a, a.abs());
        checkGm(a.minus(), a.minus(), a.minus().abs());
        if (!a.isZero()) {
            checkGm(a.abs(), a.abs().minus(), a.abs().minus());
            checkGm(a.abs().minus(), a.abs(), a.abs().minus());
        }
    }

    function checkSignAndBetween(Float a, Float b) internal pure {
        Float result = a.gm(b);
        if (a.isZero() || b.isZero()) {
            assertEq(Float.unwrap(result), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "zero");
            return;
        }
        bool negative = a.lt(LibDecimalFloat.FLOAT_ZERO) != b.lt(LibDecimalFloat.FLOAT_ZERO);
        assertEq(result.lt(LibDecimalFloat.FLOAT_ZERO), negative, "sign");
        assertFalse(result.isZero(), "non-zero");
        Float magnitude = result.abs();
        assertTrue(magnitude.lte(a.abs().max(b.abs())), "at most the larger");
        assertTrue(magnitude.gte(a.abs().min(b.abs())), "at least the smaller");
    }

    function testGmSignAndBetween(Float a, Float b) external pure {
        checkSignAndBetween(a, b);
    }

    /// `r^2` against `|a b|` in exact integers: within `2ε + ε^2` relative
    /// for `ε = (5e-41 + 6e-76) / (1 - 5e-41)`, the NatSpec bound on `r / g`
    /// above one, which is the wider side. That is checked as
    /// `1e-40 + 1.21e-75`, over it by under 1e-77, after both sides are
    /// scaled to at least 120 digits so the ceiling of the bound adds under
    /// 1e-119 more. The int32 floor's shedding is outside it: both exponents
    /// are at least `int32.min + 40`, so the true mean is at least
    /// 1e-2147483608.
    function checkBound(Float a, Float b) internal pure {
        (int256 coefficientA, int256 exponentA) = a.unpack();
        (int256 coefficientB, int256 exponentB) = b.unpack();
        vm.assume(coefficientA != 0 && coefficientB != 0);
        (int256 coefficientR, int256 exponentR) = a.gm(b).unpack();
        U512 memory square = LibExactFloat.mul(LibExactFloat.abs(coefficientR), LibExactFloat.abs(coefficientR));
        U512 memory product = LibExactFloat.mul(LibExactFloat.abs(coefficientA), LibExactFloat.abs(coefficientB));
        int256 exponentSquare = 2 * exponentR;
        int256 exponentProduct = exponentA + exponentB;
        if (exponentSquare > exponentProduct) {
            // forge-lint: disable-next-line(unsafe-typecast)
            square = LibExactFloat.mulPow10(square, uint256(exponentSquare - exponentProduct));
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            product = LibExactFloat.mulPow10(product, uint256(exponentProduct - exponentSquare));
        }
        int256 digits = LibExactFloat.digits(product);
        if (digits < 120) {
            // forge-lint: disable-next-line(unsafe-typecast)
            square = LibExactFloat.mulPow10(square, uint256(120 - digits));
            // forge-lint: disable-next-line(unsafe-typecast)
            product = LibExactFloat.mulPow10(product, uint256(120 - digits));
        }
        U512 memory limit = LibExactFloat.add(
            LibExactFloat.add(divPow10(product, 40), divPow10(LibExactFloat.mulSmall(product, 121), 77)),
            LibExactFloat.u512(2)
        );
        assertLe(LibExactFloat.cmp(square, LibExactFloat.add(product, limit)), 0, "square above");
        assertGe(LibExactFloat.cmp(LibExactFloat.add(square, limit), product), 0, "square below");
    }

    /// `x / 10^k`, floored. With `x.hi = 10 q + s` and `2^256 = 10 M + 6`,
    /// `x / 10` is `q 2^256 + s M + (6 s + x.lo) / 10`, the last two under
    /// 2^256.
    function divPow10(U512 memory x, uint256 k) internal pure returns (U512 memory) {
        for (uint256 i = 0; i < k; i++) {
            uint256 s = x.hi % 10;
            x = U512(x.hi / 10, s * (type(uint256).max / 10) + x.lo / 10 + (x.lo % 10 + 6 * s) / 10);
        }
        return x;
    }

    function testGmBound(Float a, Float b) external pure {
        (int256 coefficientA, int256 exponentA) = a.unpack();
        (int256 coefficientB, int256 exponentB) = b.unpack();
        exponentA = bound(exponentA, int256(type(int32).min) + 40, type(int32).max);
        exponentB = bound(exponentB, int256(type(int32).min) + 40, type(int32).max);
        checkBound(f(coefficientA, exponentA), f(coefficientB, exponentB));
    }

    /// Products past every Float, both exponents at the top.
    function testGmBoundTop(int224 coefficientA, int224 coefficientB, uint8 offsetA, uint8 offsetB) external pure {
        checkBound(
            f(coefficientA, int256(type(int32).max) - int256(uint256(offsetA))),
            f(coefficientB, int256(type(int32).max) - int256(uint256(offsetB)))
        );
    }

    /// Products below every Float, both exponents near the bottom.
    function testGmBoundBottom(int224 coefficientA, int224 coefficientB, uint8 offsetA, uint8 offsetB) external pure {
        checkBound(
            f(coefficientA, int256(type(int32).min) + 40 + int256(uint256(offsetA))),
            f(coefficientB, int256(type(int32).min) + 40 + int256(uint256(offsetB)))
        );
    }

    /// Coefficients at the int224 ends, where the clamp and the product's
    /// truncation act.
    function testGmBoundCoefficientEnds(uint8 deltaA, uint8 deltaB, bool negA, bool negB, int32 exponentA, int32 e)
        external
        pure
    {
        int256 coefficientA =
            negA ? type(int224).min + int256(uint256(deltaA)) : type(int224).max - int256(uint256(deltaA));
        int256 coefficientB =
            negB ? type(int224).min + int256(uint256(deltaB)) : type(int224).max - int256(uint256(deltaB));
        exponentA = int32(bound(exponentA, int256(type(int32).min) + 40, type(int32).max));
        int256 exponentB = bound(e, int256(type(int32).min) + 40, type(int32).max);
        checkBound(f(coefficientA, exponentA), f(coefficientB, exponentB));
        checkSignAndBetween(f(coefficientA, exponentA), f(coefficientB, exponentB));
    }
}
