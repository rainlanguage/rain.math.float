// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibHalmosExact} from "./LibHalmosExact.sol";

/// Forge checks on the slice filters of `LibHalmosExact`. The CI slices of a
/// lemma (`.github/workflows/halmos.yaml`) tile its cases as closed ranges, so
/// both ends of [HALMOS_SLICE_LO, HALMOS_SLICE_HI] must be in the slice: a
/// filter that dropped an end would leave the last case of every slice
/// unproved with every job green. The bounds are passed in, not set in the
/// process environment, which the sliced lemmas' cover tests read on other
/// threads of the same run.
contract LibHalmosExactSliceTest is Test {
    function testSliceBoundsInclusive() external pure {
        assertFalse(LibHalmosExact.inSliceOf(74, 75, 76));
        assertTrue(LibHalmosExact.inSliceOf(75, 75, 76));
        assertTrue(LibHalmosExact.inSliceOf(76, 75, 76));
        assertFalse(LibHalmosExact.inSliceOf(77, 75, 76));
        assertFalse(LibHalmosExact.overlapsSliceOf(70, 74, 75, 76));
        assertTrue(LibHalmosExact.overlapsSliceOf(70, 75, 75, 76));
        assertTrue(LibHalmosExact.overlapsSliceOf(76, 80, 75, 76));
        assertFalse(LibHalmosExact.overlapsSliceOf(77, 80, 75, 76));
    }

    /// Unset, the slice is every case.
    function testUnsetSliceIsEveryCase() external view {
        assertTrue(LibHalmosExact.inSlice(0));
        assertTrue(LibHalmosExact.inSlice(type(uint256).max));
        assertTrue(LibHalmosExact.overlapsSlice(0, 0));
        assertTrue(LibHalmosExact.overlapsSlice(type(uint256).max, type(uint256).max));
    }
}
