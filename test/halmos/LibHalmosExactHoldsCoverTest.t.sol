// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibHalmosExactHalmosTest} from "./LibHalmosExact.halmos.t.sol";

/// Forge checks on the scaffolding of `LibHalmosExact.halmos.t.sol`. A hold
/// lemma that returns early for a digit count passes halmos with every job
/// green while the lemma that relies on it at that count is no longer proved
/// vacuous, so this holds both to [0, 76]: every digit count reaches its
/// filter at both ends of its class exactly once over the 7 bits, 77 digits
/// at the int256 ends included (`vm.expectCall` counts the nested call).
contract LibHalmosExactHoldsCoverTest is Test, LibHalmosExactHalmosTest {
    /// The 7 bits both hold lemmas split their digit count from.
    uint256 internal constant CASE_BITS = 7;

    function testHintHoldsTakeEveryDigitCount() external {
        for (uint256 j = 0; j <= 76; j++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 low = int256(10 ** j);
            int256 high = j < 76 ? low * 10 - 1 : type(int256).max;
            expectHintsOnce(low, j);
            expectHintsOnce(high, j);
            expectHintsOnce(-low, j);
        }
        expectHintsOnce(type(int256).min, 76);
    }

    /// Over every case index, each hold lemma runs its filter on c once.
    function expectHintsOnce(int256 c, uint256 j) internal {
        vm.expectCall(address(this), abi.encodeCall(this.maximizeHintsOf, (c, j)), 1);
        vm.expectCall(address(this), abi.encodeCall(this.packHintsOf, (c, j)), 1);
        for (uint256 bits = 0; bits < 2 ** CASE_BITS; bits++) {
            this.check_maximizeHintsHold(c, bits);
            this.check_packHintsHold(c, bits);
        }
    }

    /// `divHint` has no filter: the lemma at zero, both sides of the divisor
    /// in both signs and both int256 ends.
    function testDivHintHoldsAtTheDivisor() external {
        int256[9] memory xs = [int256(0), 1, -1, 1e75 - 1, 1e75, -(1e75 - 1), -1e75, type(int256).max, type(int256).min];
        for (uint256 i = 0; i < xs.length; i++) {
            vm.expectCall(address(this), abi.encodeCall(this.divHintOf, (xs[i], int256(1e75))), 1);
            this.check_divHintHolds(xs[i]);
        }
    }
}
