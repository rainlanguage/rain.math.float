// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibHalmosExact} from "./LibHalmosExact.sol";

/// Forge checks on the slice filters of `LibHalmosExact`. The CI slices of a
/// lemma (`.github/workflows/halmos.yaml`) tile its cases as closed ranges, so
/// both ends of [HALMOS_SLICE_LO, HALMOS_SLICE_HI] must be in the slice: a
/// filter that dropped an end would leave the last case of every slice
/// unproved with every job green.
contract LibHalmosExactSliceTest is Test {
    function testSliceBoundsInclusive() external {
        vm.setEnv("HALMOS_SLICE_LO", "75");
        vm.setEnv("HALMOS_SLICE_HI", "76");
        assertFalse(LibHalmosExact.inSlice(74));
        assertTrue(LibHalmosExact.inSlice(75));
        assertTrue(LibHalmosExact.inSlice(76));
        assertFalse(LibHalmosExact.inSlice(77));
        assertFalse(LibHalmosExact.overlapsSlice(70, 74));
        assertTrue(LibHalmosExact.overlapsSlice(70, 75));
        assertTrue(LibHalmosExact.overlapsSlice(76, 80));
        assertFalse(LibHalmosExact.overlapsSlice(77, 80));
        vm.setEnv("HALMOS_SLICE_LO", "0");
        vm.setEnv("HALMOS_SLICE_HI", vm.toString(type(uint256).max));
    }
}
