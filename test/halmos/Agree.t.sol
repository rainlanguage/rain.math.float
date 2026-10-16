// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibHalmosExact} from "./LibHalmosExact.sol";
import {AgreeHalmosTest} from "./Agree.halmos.t.sol";

/// Forge checks on the scaffolding of `Agree.halmos.t.sol`. A lemma that
/// returns early on every input, or a case split with a gap, passes halmos
/// with every job green, so these hold the filters and the splits to the
/// header's argument: the filters accept every maximized input, each NEG
/// slice and each SYMNEAR lemma proves exactly the cases its name says, and
/// SYMFAR starts where SYMNEAR stops.
contract AgreeHalmosCoverTest is Test, AgreeHalmosTest {
    /// `maximize` of 1 at 0: 10^76, maximized by MAX.
    int256 internal constant A = 1e76;
    /// `symNear`'s yb for B = 10 yb = A.
    int256 internal constant YB = 1e75;

    /// MAX's statement of maximized, in plain Solidity.
    function plainMaximized(int256 m) internal pure returns (bool) {
        uint256 x = LibHalmosExact.abs(m);
        return m != type(int256).min && x > LibHalmosExact.T10 && x <= 10 * LibHalmosExact.T10 && m % 1e8 == 0;
    }

    function testMaximizedEncodingsAgree(int256 m) external pure {
        assertEq(maximized(m), plainMaximized(m));
    }

    /// Both encodings at the bounds of MAX's statement: the multiples of 10^8
    /// either side of T10, the last one at most 10 T10 and 10 T10 itself (no
    /// multiple of 10^8 above it fits int256), both signs, and the extremes.
    function testMaximizedEncodingsAgreeAtBounds() external pure {
        int256 t10 = int256(LibHalmosExact.T10);
        int256 lowIn = (t10 / 1e8 + 1) * 1e8;
        // forge-lint: disable-next-line(divide-before-multiply)
        int256 highIn = (10 * t10 / 1e8) * 1e8;
        int256[12] memory ms = [
            lowIn - 1e8,
            lowIn,
            highIn,
            10 * t10,
            -(lowIn - 1e8),
            -lowIn,
            -highIn,
            -10 * t10,
            int256(0),
            type(int256).min,
            type(int256).max,
            lowIn + 1
        ];
        bool[12] memory expected = [false, true, true, false, false, true, true, false, false, false, false, false];
        for (uint256 i = 0; i < ms.length; i++) {
            assertEq(plainMaximized(ms[i]), expected[i], vm.toString(ms[i]));
            assertEq(maximized(ms[i]), expected[i], vm.toString(ms[i]));
        }
    }

    /// Every output of `maximize` on a nonzero int224, and its negation, passes
    /// the filter SYMNEAR and SYMFAR return on.
    function testMaximizedOutputIsAdmissible(int224 c, int32 e) external pure {
        vm.assume(c != 0);
        (int256 m,,) = LibDecimalFloatImplementation.maximize(c, e);
        assertTrue(admissible(m));
        assertTrue(admissible(-m));
    }

    /// The same at both ends of every digit count class of [-2^223, 2^223],
    /// the coefficients MINUS hands `Impl.add`.
    function testMaximizedOutputIsAdmissibleAtDigitBounds() external pure {
        for (uint256 j = 0; j < NEG_DIGITS; j++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 low = int256(10 ** j);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 high = j + 1 < NEG_DIGITS ? low * 10 - 1 : int256(2 ** 223);
            assertAdmissibleOutput(low, j);
            assertAdmissibleOutput(high, j);
            assertAdmissibleOutput(-low, j);
            assertAdmissibleOutput(-high, j);
        }
    }

    function assertAdmissibleOutput(int256 c, uint256 j) internal pure {
        assertTrue(LibHalmosExact.hasDigits(c, j), vm.toString(c));
        (int256 m,,) = LibDecimalFloatImplementation.maximize(c, 0);
        assertTrue(admissible(m), vm.toString(c));
        assertTrue(admissible(-m), vm.toString(c));
    }

    /// 10^(NEG_DIGITS - 1) <= 2^223 < 10^NEG_DIGITS.
    function testNegDigitsIsTheDigitCountOfTwo223() external pure {
        assertTrue(10 ** (NEG_DIGITS - 1) <= 2 ** 223);
        assertTrue(2 ** 223 < 10 ** NEG_DIGITS);
    }

    /// The NEG slices from lo = 0 at every NEG_SLICE tile [0, NEG_DIGITS), and
    /// each digit count j, at both ends of its class, reaches `maximize` in
    /// exactly one lemma `check_maximizeNegates<lo>`.
    function testNegSlicesTileDigitCounts() external {
        uint256 next = 0;
        for (uint256 lo = 0; lo < NEG_DIGITS; lo += NEG_SLICE) {
            assertEq(lo, next);
            uint256 hi = negSliceHi(lo);
            assertTrue(hi >= lo && hi < NEG_DIGITS);
            next = hi + 1;
        }
        assertEq(next, NEG_DIGITS);
        for (uint256 j = 0; j < NEG_DIGITS; j++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 low = int256(10 ** j);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 high = j + 1 < NEG_DIGITS ? low * 10 - 1 : int256(2 ** 223);
            expectMaximizedOnce(low, j);
            expectMaximizedOnce(high, j);
        }
    }

    /// Of the NEG lemmas, exactly one runs `maximize` on c and on -c.
    function expectMaximizedOnce(int256 c, uint256 j) internal {
        vm.expectCall(address(this), abi.encodeCall(this.maximize, (c, int256(0))), 1);
        vm.expectCall(address(this), abi.encodeCall(this.maximize, (-c, int256(0))), 1);
        for (uint256 lo = 0; lo < NEG_DIGITS; lo += NEG_SLICE) {
            string memory name = string.concat("check_maximizeNegates", vm.toString(lo), "(int256,int32,uint256)");
            (bool ok,) = address(this).call(abi.encodeWithSelector(selector(name), c, int32(0), j));
            assertTrue(ok, name);
        }
    }

    /// SYMFAR takes exactly the gaps from NEAR_GAPS to 2^40: `check_spreadSymFar`
    /// reaches `Impl.add` at those and returns before it either side.
    function testFarGapBounds() external {
        assertFalse(farGap(NEAR_GAPS - 1));
        assertTrue(farGap(NEAR_GAPS));
        assertTrue(farGap(2 ** 40));
        assertFalse(farGap(2 ** 40 + 1));
        expectFarAdds(NEAR_GAPS - 1, 0);
        expectFarAdds(NEAR_GAPS, 1);
        expectFarAdds(2 ** 40, 1);
        expectFarAdds(2 ** 40 + 1, 0);
    }

    function expectFarAdds(uint256 d, uint64 count) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (A, int256(d), A, int256(0))), count);
        this.check_spreadSymFar(A, A, 0, d);
    }

    /// A lemma `check_spreadSymNear<d>` exists for every d in [0, NEAR_GAPS)
    /// and none at NEAR_GAPS, and each reaches `Impl.add` at the gap its name
    /// says.
    function testEveryNearGapHasALemmaAtItsGap() external {
        for (uint256 d = 0; d < NEAR_GAPS; d++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (A, int256(d), A, int256(0))), 1);
            (bool ok,) = address(this).call(abi.encodeWithSelector(nearSelector(d), A, YB, int256(0)));
            assertTrue(ok, vm.toString(d));
        }
        (bool none,) = address(this).call(abi.encodeWithSelector(nearSelector(NEAR_GAPS), A, YB, int256(0)));
        assertFalse(none);
    }

    function nearSelector(uint256 d) internal pure returns (bytes4) {
        return
            selector(string.concat("check_spreadSymNear", d < 10 ? "0" : "", vm.toString(d), "(int256,int256,int256)"));
    }

    function selector(string memory signature) internal pure returns (bytes4) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(keccak256(bytes(signature)));
    }
}
