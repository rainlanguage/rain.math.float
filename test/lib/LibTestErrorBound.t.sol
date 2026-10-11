// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestErrorBound} from "test/lib/LibTestErrorBound.sol";

/// Each bound and monotonicity limit at values worked by hand.
contract LibTestErrorBoundTest is Test {
    using LibDecimalFloat for Float;

    /// 1e-2147483648 over |t|, and zero once that is below the smallest Float.
    function testFloorValues() external pure {
        assertTrue(LibTestErrorBound.floor(1, -2147483600).eq(LibDecimalFloat.packLossless(1, -48)), "1e-48");
        assertTrue(LibTestErrorBound.floor(-5, -2147483640).eq(LibDecimalFloat.packLossless(2, -9)), "2e-9");
        assertTrue(LibTestErrorBound.floor(4, -2147483648).eq(LibDecimalFloat.packLossless(25, -2)), "0.25");
        assertTrue(LibTestErrorBound.floor(1, 0).eq(LibDecimalFloat.packLossless(1, type(int32).min)), "smallest");
        assertTrue(LibTestErrorBound.floor(1, 1).isZero(), "below the smallest Float");
    }

    /// For high = 1, low = 1 + d and both errors E = 1e-5, the limit is
    /// E low + E high, so low - high is within it iff d (1 - E) <= 2E, up to
    /// the floor's 3e-2147483648: d = 2.00002e-5 is, d = 2.00003e-5 is not.
    function testMonotoneRelativeLimit() external pure {
        Float high = LibDecimalFloat.FLOAT_ONE;
        Float error = LibDecimalFloat.packLossless(1, -5);
        assertTrue(
            LibTestErrorBound.monotoneRelative(LibDecimalFloat.packLossless(10000200002, -10), high, error, error),
            "within"
        );
        assertFalse(
            LibTestErrorBound.monotoneRelative(LibDecimalFloat.packLossless(10000200003, -10), high, error, error),
            "past"
        );
        assertTrue(LibTestErrorBound.monotoneRelative(high, high, error, error), "equal");
    }

    /// With no error the limit is the floor's 3e-2147483648 alone, met
    /// exactly by a spread of 3 units and passed by 4.
    function testMonotoneRelativeFloorTerm() external pure {
        Float high = LibDecimalFloat.packLossless(1, type(int32).min);
        Float zero = LibDecimalFloat.FLOAT_ZERO;
        assertTrue(
            LibTestErrorBound.monotoneRelative(LibDecimalFloat.packLossless(4, type(int32).min), high, zero, zero),
            "at the floor term"
        );
        assertFalse(
            LibTestErrorBound.monotoneRelative(LibDecimalFloat.packLossless(5, type(int32).min), high, zero, zero),
            "past the floor term"
        );
    }

    /// Each error scales the other operand, for low = 2 and high = 1: a
    /// highError of 0.5 gives a limit of 0.5 low = 1, a lowError of 1 gives
    /// 1 high = 1, both meeting the spread of 1, and a lowError of 0.5 gives
    /// 0.5 high, under it.
    function testMonotoneRelativeCrossedErrors() external pure {
        Float low = LibDecimalFloat.packLossless(2, 0);
        Float high = LibDecimalFloat.FLOAT_ONE;
        Float half = LibDecimalFloat.FLOAT_HALF;
        Float zero = LibDecimalFloat.FLOAT_ZERO;
        assertTrue(LibTestErrorBound.monotoneRelative(low, high, zero, half), "highError scales low");
        assertTrue(
            LibTestErrorBound.monotoneRelative(low, high, LibDecimalFloat.FLOAT_ONE, zero), "lowError scales high"
        );
        assertFalse(LibTestErrorBound.monotoneRelative(low, high, half, zero), "lowError does not scale low");
    }

    /// low - high against lowError + highError, inclusive.
    function testMonotoneAbsoluteLimit() external pure {
        Float error = LibDecimalFloat.packLossless(1, -3);
        Float high = LibDecimalFloat.FLOAT_ONE;
        assertTrue(LibTestErrorBound.monotoneAbsolute(LibDecimalFloat.packLossless(1002, -3), high, error, error), "at");
        assertFalse(
            LibTestErrorBound.monotoneAbsolute(LibDecimalFloat.packLossless(1003, -3), high, error, error), "past"
        );
        assertTrue(LibTestErrorBound.monotoneAbsolute(high, LibDecimalFloat.packLossless(5, 0), error, error), "below");
    }

    /// 5.00000033006e-41 plus N min(K1, K2 d), N the integer part of |b| and
    /// d = max(|a|, 1/|a|) - 1.
    function testPowValues() external pure {
        // d 1: K1, 2 1.7273e-76.
        assertTrue(
            LibTestErrorBound.pow(LibDecimalFloat.FLOAT_TWO, LibDecimalFloat.packLossless(25, -1))
                .eq(LibDecimalFloat.packLossless(5000000330060000000000000000000000034546, -80)),
            "2^2.5"
        );
        // 1/a has d 1: K1 for b < 0, 123 1.1728e-75.
        assertTrue(
            LibTestErrorBound.pow(LibDecimalFloat.FLOAT_HALF, LibDecimalFloat.packLossless(-1239, -1))
                .eq(LibDecimalFloat.packLossless(5000000330060000000000000000000014425440, -80)),
            "0.5^-123.9"
        );
        // d 1e-66: K2 d, 1e67 1.5e-104 and 1e67 3.4786e-104.
        Float nearOne = LibDecimalFloat.packLossless(1e66 + 1, -66);
        assertTrue(
            LibTestErrorBound.pow(nearOne, LibDecimalFloat.packLossless(1, 67))
                .eq(LibDecimalFloat.packLossless(1500500000033006, -52)),
            "(1 + 1e-66)^1e67"
        );
        assertTrue(
            LibTestErrorBound.pow(nearOne, LibDecimalFloat.packLossless(-1, 67))
                .eq(LibDecimalFloat.packLossless(3479100000033006, -52)),
            "(1 + 1e-66)^-1e67"
        );
        // N 0.
        assertTrue(
            LibTestErrorBound.pow(LibDecimalFloat.FLOAT_TWO, LibDecimalFloat.FLOAT_HALF)
                .eq(LibDecimalFloat.packLossless(500000033006, -52)),
            "2^0.5"
        );
    }

    /// log10 2 = 0.30103..., so half a unit of its 41st digit is 5e-42, plus
    /// 1.0044e-50.
    function testLog10Value() external pure {
        assertTrue(LibTestErrorBound.log10(2, 0).eq(LibDecimalFloat.packLossless(5000000010044, -54)), "log10 2");
    }

    /// plus sums and times multiplies.
    function testPlusTimes() external pure {
        Float a = LibDecimalFloat.packLossless(3, -2);
        Float b = LibDecimalFloat.packLossless(7, -5);
        assertTrue(LibTestErrorBound.plus(a, b).eq(LibDecimalFloat.packLossless(3007, -5)), "plus");
        assertTrue(LibTestErrorBound.times(a, b).eq(LibDecimalFloat.packLossless(21, -7)), "times");
    }
}
