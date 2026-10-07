// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestErrorBound} from "test/lib/LibTestErrorBound.sol";

/// The floor term and the relative monotonicity limit at values worked by
/// hand.
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
}
