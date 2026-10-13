// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    WithTargetExponentOverflow
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibHalmosExact} from "test/halmos/LibHalmosExact.sol";

/// Halmos proof of SPEC.md's `withTargetExponent(c, e, t)` rule (#367, ruled
/// A): shrinking (t >= e) returns c 10^(e - t) truncated toward zero; growing
/// by g = e - t digits returns c 10^g, zero for zero at any g, and reverts
/// `WithTargetExponentOverflow(c, e, t)` iff c 10^g is outside int256.
///
/// Slices, over every int256 c, e and t: SHRINK_NEAR (t - e in [0, 76], one
/// constant per path), SHRINK_FAR (t - e >= 77), GROW_NEAR (e - t in [1, 76],
/// one constant per path) and GROW_FAR (e - t >= 77) partition every
/// (c, e, t). The NEAR lemmas take the gap as `j` and the free end as a
/// parameter; the j they return on name no gap in their range, and the free
/// ends they return on would put the other end outside int256, so they are
/// not inputs.
contract WithTargetExponentHalmosTest {
    function withTargetExponent(int256 c, int256 e, int256 t) external pure returns (int256) {
        return LibDecimalFloatImplementation.withTargetExponent(c, e, t);
    }

    function arg(bytes memory err, uint256 i) internal pure returns (uint256 w) {
        assembly ("memory-safe") {
            w := mload(add(err, add(36, mul(32, i))))
        }
    }

    /// Asserts the call returns `expected`, or, when `overflows`, reverts
    /// exactly `WithTargetExponentOverflow(c, e, t)`.
    function checkWith(int256 c, int256 e, int256 t, int256 expected, bool overflows) internal view {
        try this.withTargetExponent(c, e, t) returns (int256 r) {
            assert(!overflows && r == expected);
        } catch (bytes memory err) {
            assert(overflows);
            // forge-lint: disable-next-line(unsafe-typecast)
            assert(err.length == 100 && bytes4(err) == WithTargetExponentOverflow.selector);
            // forge-lint: disable-next-line(unsafe-typecast)
            assert(arg(err, 0) == uint256(c) && arg(err, 1) == uint256(e) && arg(err, 2) == uint256(t));
        }
    }

    /// |c| 10^-s truncated toward zero, with c's sign.
    function shrunk(int256 c, uint256 s) internal pure returns (int256) {
        uint256 q = LibHalmosExact.abs(c) / 10 ** s;
        // q <= 2^255, and q = 2^255 only for c = int256.min, s = 0, where the
        // wrapped negation is -2^255 again.
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            return c < 0 ? -int256(q) : int256(q);
        }
    }

    /// SHRINK_NEAR: t = e + s, s in [0, 76].
    function check_withTargetExponentShrinkNear(int256 c, int256 e, uint256 j) external view {
        uint256 s = LibHalmosExact.concrete(j, 7);
        if (s > 76) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        if (e > type(int256).max - int256(s)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        checkWith(c, e, e + int256(s), shrunk(c, s), false);
    }

    /// SHRINK_FAR: t - e >= 77. |c| <= 2^255 < 10^77, so the result is 0.
    function check_withTargetExponentShrinkFar(int256 c, int256 e, int256 t) external view {
        if (t <= e) return;
        unchecked {
            // t > e, so the wrapped difference is t - e exactly.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (uint256(t) - uint256(e) < 77) return;
        }
        checkWith(c, e, t, 0, false);
    }

    /// GROW_NEAR: e = t + g, g in [1, 76]. c 10^g fits int256 iff
    /// c <= floor(int256.max / 10^g) for c >= 0 and |c| <= floor(2^255 / 10^g)
    /// for c < 0.
    function check_withTargetExponentGrowNear(int256 c, int256 t, uint256 j) external view {
        uint256 g = LibHalmosExact.concrete(j, 7);
        if (g < 1 || g > 76) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        if (t > type(int256).max - int256(g)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 e = t + int256(g);
        uint256 p = 10 ** g;
        uint256 bound = c < 0 ? 2 ** 255 / p : uint256(type(int256).max) / p;
        bool overflows = LibHalmosExact.abs(c) > bound;
        int256 expected;
        if (!overflows) {
            // |c| 10^g fits int256 here.
            unchecked {
                // forge-lint: disable-next-line(unsafe-typecast)
                expected = c * int256(p);
            }
        }
        checkWith(c, e, t, expected, overflows);
    }

    /// GROW_FAR: e - t >= 77. Nonzero |c| 10^g >= 10^77 > 2^255.
    function check_withTargetExponentGrowFar(int256 c, int256 e, int256 t) external view {
        if (e <= t) return;
        unchecked {
            // e > t, so the wrapped difference is e - t exactly.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (uint256(e) - uint256(t) < 77) return;
        }
        checkWith(c, e, t, 0, c != 0);
    }
}
