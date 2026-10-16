// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// Forge checks on the scaffolding of `AddSubRoundOnce.halmos.t.sol`. A lemma
/// that returns early on more inputs than its header says passes halmos with
/// every job green, so these hold MAX, IDEM, NEAR and FAR to their domains:
/// each reaches the call it checks at both ends of every range it is stated
/// over and not one past them (`vm.expectCall` counts the nested call).
contract AddSubRoundOnceCoverTest is Test, AddSubRoundOnceHalmosTest {
    /// The largest maximized magnitude, the last multiple of 10^8 at most
    /// 10 T10, and the smallest, the first above T10.
    // forge-lint: disable-next-line(unsafe-typecast, divide-before-multiply)
    int256 internal constant HIGH_IN = int256(10 * T10 / 1e8 * 1e8);
    // forge-lint: disable-next-line(unsafe-typecast, divide-before-multiply)
    int256 internal constant LOW_IN = int256((T10 / 1e8 + 1) * 1e8);
    /// NEAR stops at gap 76 and FAR starts at 77.
    uint256 internal constant FIRST_FAR_GAP = 77;
    /// The 7 bits MAX and NEAR split their case index from.
    uint256 internal constant CASE_BITS = 7;

    /// Both maximized magnitudes in both signs: the operands at the edges of
    /// NEAR's and FAR's domain, closed under negation.
    function edges() internal pure returns (int256[4] memory) {
        return [HIGH_IN, -HIGH_IN, LOW_IN, -LOW_IN];
    }

    /// MAX: both ends of every digit count class of [-2^223, 2^223], in both
    /// signs, reach `maximize` in exactly one of the cases the 7 bits give,
    /// and the magnitudes one past 2^223 in none.
    function testMaximizeFloatTakesEveryDigitCount() external {
        for (uint256 j = 0; j <= 67; j++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 low = int256(10 ** j);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 high = j < 67 ? low * 10 - 1 : int256(TWO_223);
            expectMaximizedOnce(low, 1);
            expectMaximizedOnce(high, 1);
            expectMaximizedOnce(-low, 1);
            expectMaximizedOnce(-high, 1);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        expectMaximizedOnce(int256(TWO_223) + 1, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        expectMaximizedOnce(-int256(TWO_223) - 1, 0);
    }

    /// Over every case index, `check_maximizeFloat` runs `maximize` on c
    /// `count` times.
    function expectMaximizedOnce(int256 c, uint64 count) internal {
        vm.expectCall(address(this), abi.encodeCall(this.maximize, (c, int256(0))), count);
        for (uint256 j = 0; j < 2 ** CASE_BITS; j++) {
            this.check_maximizeFloat(c, 0, j);
        }
    }

    /// IDEM reaches `maximize` at both ends of MAX's magnitude range, both
    /// signs, and not one past either end.
    function testIdempotentTakesBothEndsAndSigns() external {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 t10 = int256(T10);
        int256[4] memory ins = [t10 + 1, 10 * t10, -(t10 + 1), -10 * t10];
        int256[4] memory outs = [t10, 10 * t10 + 1, -t10, -(10 * t10 + 1)];
        for (uint256 i = 0; i < ins.length; i++) {
            vm.expectCall(address(this), abi.encodeCall(this.maximize, (ins[i], int256(0))), 1);
            this.check_maximizeIdempotent(ins[i], 0);
            vm.expectCall(address(this), abi.encodeCall(this.maximize, (outs[i], int256(0))), 0);
            this.check_maximizeIdempotent(outs[i], 0);
        }
    }

    /// NEAR takes exactly the gaps in [0, 76] of the 7 bits: each reaches
    /// `Impl.add` in both argument orders at HIGH_IN and HIGH_IN, and no gap
    /// from 77 does.
    function testNearTakesEveryGapToSeventySix() external {
        for (uint256 d = 0; d < 2 ** CASE_BITS; d++) {
            expectNearAdds(HIGH_IN, HIGH_IN, 0, d, d < FIRST_FAR_GAP ? 1 : 0);
            callNear(HIGH_IN, HIGH_IN, 0, d);
        }
    }

    /// NEAR at its first and last gap reaches `Impl.add` in both argument
    /// orders on every pair of edge operands at both ends of the exponent
    /// domain, cancelling pairs (x, -x) at d = 0 included, and in neither one
    /// exponent past either end. NEAR is not in the CI matrix (#512).
    function testNearTakesTheWholeDomain() external {
        int256[4] memory xs = edges();
        int256[2] memory ebs = [FMIN - 76, FMAX - 8];
        uint256[2] memory ds = [uint256(0), FIRST_FAR_GAP - 1];
        for (uint256 g = 0; g < ds.length; g++) {
            for (uint256 k = 0; k < ebs.length; k++) {
                for (uint256 i = 0; i < xs.length; i++) {
                    for (uint256 j = 0; j < xs.length; j++) {
                        expectNearAdds(xs[i], xs[j], ebs[k], ds[g], 1);
                    }
                }
                for (uint256 i = 0; i < xs.length; i++) {
                    for (uint256 j = 0; j < xs.length; j++) {
                        callNear(xs[i], xs[j], ebs[k], ds[g]);
                    }
                }
            }
            expectNearAdds(HIGH_IN, HIGH_IN, FMIN - 77, ds[g], 0);
            callNear(HIGH_IN, HIGH_IN, FMIN - 77, ds[g]);
            expectNearAdds(HIGH_IN, HIGH_IN, FMAX - 7, ds[g], 0);
            callNear(HIGH_IN, HIGH_IN, FMAX - 7, ds[g]);
        }
    }

    /// Each order's add from `check_addNear(a, b / 10, eB, d, swap)` over
    /// both values of swap, `count` times. At d = 0 the swapped add has the
    /// calldata of the unswapped add of the pair (b, a), which `edges` also
    /// holds, so the one expectation stands for both: a call is counted only
    /// by the expectations before it, so a block's pairs are all expected
    /// before any is called.
    function expectNearAdds(int256 a, int256 b, int256 eB, uint256 d, uint64 count) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eA = eB + int256(d);
        if (d == 0) {
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (a, eA, b, eB)), 2 * count);
        } else {
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (a, eA, b, eB)), count);
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (b, eB, a, eA)), count);
        }
    }

    function callNear(int256 a, int256 b, int256 eB, uint256 d) internal view {
        this.check_addNear(a, b / 10, eB, d, false);
        this.check_addNear(a, b / 10, eB, d, true);
    }

    /// NEAR on a cancelling pair at gap 0: `Impl.add` returns the maximized
    /// zero (0, 0), so the lemma takes `checkSum`'s zero path and asserts
    /// nothing about the exponent. rain-marvin's counterexample to the form
    /// that asserted an exponent of eB or eB + 1 first.
    function testNearZeroSum() external view {
        this.check_addNear(1e76, -1e75, 5, 0, false);
        this.check_addNear(-1e76, 1e75, -7, 0, true);
    }

    /// FAR takes exactly the gaps from 77 that keep both exponents in the
    /// maximized range: at its first gap it reaches `Impl.add` in both
    /// argument orders on every pair of edge operands with eB at both ends of
    /// its domain, and in neither at gap 76 or one exponent past either end;
    /// the widest gap, from the lowest eB to the highest eA, is in and one
    /// wider is out.
    function testFarTakesTheWholeDomain() external {
        int256[4] memory xs = edges();
        // forge-lint: disable-next-line(unsafe-typecast)
        int256[2] memory ebs = [FMIN - 76, FMAX - 8 - int256(FIRST_FAR_GAP)];
        for (uint256 k = 0; k < ebs.length; k++) {
            for (uint256 i = 0; i < xs.length; i++) {
                for (uint256 j = 0; j < xs.length; j++) {
                    expectFarAdds(xs[i], xs[j], ebs[k], FIRST_FAR_GAP, 1);
                }
            }
        }
        expectFarAdds(HIGH_IN, HIGH_IN, 0, FIRST_FAR_GAP - 1, 0);
        expectFarAdds(HIGH_IN, HIGH_IN, FMIN - 77, FIRST_FAR_GAP, 0);
        expectFarAdds(HIGH_IN, HIGH_IN, ebs[1] + 1, FIRST_FAR_GAP, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 widest = uint256((FMAX - 8) - (FMIN - 76));
        expectFarAdds(HIGH_IN, HIGH_IN, FMIN - 76, widest, 1);
        expectFarAdds(HIGH_IN, HIGH_IN, FMIN - 76, widest + 1, 0);
    }

    /// `check_addFar(a, b, eB, d, swap)` for both values of swap makes each
    /// order's add `count` times.
    function expectFarAdds(int256 a, int256 b, int256 eB, uint256 d, uint64 count) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eA = eB + int256(d);
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (a, eA, b, eB)), count);
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (b, eB, a, eA)), count);
        this.check_addFar(a, b, eB, d, false);
        this.check_addFar(a, b, eB, d, true);
    }
}
