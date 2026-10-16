// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibHalmosExactHalmosTest} from "./LibHalmosExact.halmos.t.sol";
import {SeriesSolidityEquivalenceHalmosTest} from "./SeriesSolidityEquivalence.halmos.t.sol";

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
    function testDivHintHoldsAtTheDivisor() external view {
        int256[9] memory xs = [int256(0), 1, -1, 1e75 - 1, 1e75, -(1e75 - 1), -1e75, type(int256).max, type(int256).min];
        for (uint256 i = 0; i < xs.length; i++) {
            this.check_divHintHolds(xs[i]);
        }
    }
}

/// The hint filters reporting false.
contract LibHalmosExactHoldsFalseTest is Test, LibHalmosExactHalmosTest {
    function maximizeHintsOf(int256, uint256) external pure override returns (bool) {
        return false;
    }

    function packHintsOf(int256, uint256) external pure override returns (bool) {
        return false;
    }

    function testMaximizeHoldRejectsAFalseFilter() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeHintsHold(1, 0);
    }

    function testPackHoldRejectsAFalseFilter() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packHintsHold(1, 0);
    }
}

/// Forge checks on `SeriesSolidityEquivalence.halmos.t.sol`, whose lemmas
/// have no filter and are not in the CI matrix (#515, #516): each at the ends
/// of its input.
contract SeriesSolidityEquivalenceCoverTest is SeriesSolidityEquivalenceHalmosTest {
    /// `exp10Fixed` at zero, one below `POW_FIXED_ONE`, at it (both revert
    /// `Exp10FixedOutOfRange`) and at uint256.max.
    function testExp10FixedAtItsEdges() external view {
        this.check_exp10FixedEquivalence(0);
        this.check_exp10FixedEquivalence(1e50 - 1);
        this.check_exp10FixedEquivalence(1e50);
        this.check_exp10FixedEquivalence(type(uint256).max);
    }

    /// `log10Ratio` over every pair of zero, one, `POW_FIXED_ONE` and
    /// uint256.max, both values of relative: equal operands, a zero operand,
    /// and sums that wrap, every one a revert in both. Then ratios inside the
    /// series' range in both orders: 10001 : 10000, and the same ratio at the
    /// 1e50 scale `relative` needs.
    function testLog10RatioAtItsEdges() external view {
        uint256[4] memory xs = [uint256(0), 1, 1e50, type(uint256).max];
        for (uint256 a = 0; a < xs.length; a++) {
            for (uint256 b = 0; b < xs.length; b++) {
                this.check_log10RatioEquivalence(xs[a], xs[b], false);
                this.check_log10RatioEquivalence(xs[a], xs[b], true);
            }
        }
        this.check_log10RatioEquivalence(10001, 10000, false);
        this.check_log10RatioEquivalence(10000, 10001, false);
        this.check_log10RatioEquivalence(1e50 + 1e46, 1e50, true);
        this.check_log10RatioEquivalence(1e50, 1e50 + 1e46, true);
    }
}

/// The Solidity series one above the assembly.
contract SeriesSolidityEquivalenceSolAboveTest is SeriesSolidityEquivalenceHalmosTest {
    function log10RatioSol(uint256 a, uint256 b, bool relative) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.log10Ratio(a, b, relative);
        return (c + 1, e);
    }

    function exp10FixedSol(uint256 x) external pure override returns (uint256) {
        return LibDecimalFloatImplementation.exp10Fixed(x) + 1;
    }

    function testLog10RatioRejectsAChangedCoefficient() external {
        vm.expectRevert(stdError.assertionError);
        this.check_log10RatioEquivalence(10001, 10000, false);
    }

    function testExp10FixedRejectsAChangedResult() external {
        vm.expectRevert(stdError.assertionError);
        this.check_exp10FixedEquivalence(1e49);
    }
}

/// The Solidity series reverting with the bytes the assembly returns: the two
/// outcomes differ only in the success flag.
contract SeriesSolidityEquivalenceSolRevertsTest is SeriesSolidityEquivalenceHalmosTest {
    function log10RatioSol(uint256 a, uint256 b, bool relative) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.log10Ratio(a, b, relative);
        bytes memory data = abi.encode(c, e);
        assembly ("memory-safe") {
            revert(add(data, 0x20), mload(data))
        }
    }

    function exp10FixedSol(uint256 x) external pure override returns (uint256) {
        uint256 result = LibDecimalFloatImplementation.exp10Fixed(x);
        assembly ("memory-safe") {
            mstore(0, result)
            revert(0, 0x20)
        }
    }

    function testLog10RatioRejectsADifferentOutcome() external {
        vm.expectRevert(stdError.assertionError);
        this.check_log10RatioEquivalence(10001, 10000, false);
    }

    function testExp10FixedRejectsADifferentOutcome() external {
        vm.expectRevert(stdError.assertionError);
        this.check_exp10FixedEquivalence(1e49);
    }
}

/// The Solidity series returning nothing where the assembly returns a word.
contract SeriesSolidityEquivalenceSolEmptyTest is SeriesSolidityEquivalenceHalmosTest {
    function log10RatioSol(uint256, uint256, bool) external pure override returns (int256, int256) {
        assembly ("memory-safe") {
            return(0, 0)
        }
    }

    function exp10FixedSol(uint256) external pure override returns (uint256) {
        assembly ("memory-safe") {
            return(0, 0)
        }
    }

    function testLog10RatioRejectsAShorterEncoding() external {
        vm.expectRevert(stdError.assertionError);
        this.check_log10RatioEquivalence(10001, 10000, false);
    }

    function testExp10FixedRejectsAShorterEncoding() external {
        vm.expectRevert(stdError.assertionError);
        this.check_exp10FixedEquivalence(1e49);
    }
}
