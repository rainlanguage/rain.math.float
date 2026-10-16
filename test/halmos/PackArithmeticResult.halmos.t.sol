// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, ExponentUnderflow} from "../../src/error/ErrDecimalFloat.sol";
import {LibHalmosExact} from "./LibHalmosExact.sol";

/// Lemma PACK of the add/sub proof (see `AddSubRoundOnce.halmos.t.sol`).
///
/// `packArithmeticResult(c, e)` is the Float closest to c 10^e that does not
/// exceed it in magnitude, all bits zero for zero, reverting
/// `ExponentUnderflow(c, e)` when that is zero for a nonzero c and
/// `ExponentOverflow(c, e)` when it is no Float. Checked for every int256 c and
/// every int256 e: Below, Low, Middle, High and Above tile the int256
/// exponents, and each splits c by size class (`checkPackClass`), one per
/// path; `PackArithmeticResult.t.sol` checks both tilings at their ends. The
/// halmos workflow, dispatched by hand (it is disabled on the repository),
/// proves every band but `check_packLow` cases 99-780 (#511).
contract PackArithmeticResultHalmosTest {
    int256 internal constant FMIN = type(int32).min;
    int256 internal constant FMAX = type(int32).max;

    function pack(int256 c, int256 e) external pure returns (Float) {
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// The rule, from the Float grid alone: T = max m 10^f over every int224
    /// magnitude m (at most 2^223 - 1 positive, 2^223 negative), every f at
    /// least int32.min with no upper bound, and m 10^f <= |c| 10^e. `status` 1:
    /// T is zero for nonzero c (underflow). 2: T has no exponent at most
    /// int32.max (overflow).
    ///
    /// Let f0 be the least f at least e - 77 with floor(|c| 10^(e - f)) <= L.
    /// Above f0 floor(X / 10^f) 10^f only shrinks, and below f0 - 1 L 10^f
    /// does, so T is the larger of floor(X / 10^f0) 10^f0 and L 10^(f0 - 1),
    /// over those f at least int32.min.
    ///
    /// n is 0 for |c| <= L, else the j of `LibHalmosExact.hasDigits`: c has n + 1
    /// digits. Every branch compares x itself against a constant, so none waits
    /// on a quotient.
    function truncGrid(int256 c, int256 e, uint256 n) internal pure returns (uint256 m, int256 f, uint256 status) {
        if (c == 0) {
            return (0, 0, 0);
        }
        // 0 < |c| < 2^256 < 10^78: at e <= int32.min - 78, |c| 10^e is below
        // 10^int32.min, every nonzero member; at e >= int32.max + 68 it is at
        // least 10^(int32.max + 68) > 2^223 10^int32.max, past every Float.
        if (e <= FMIN - 78) {
            return (0, 0, 1);
        }
        if (e >= FMAX + 68) {
            return (0, 0, 2);
        }
        uint256 x = LibHalmosExact.abs(c);
        uint256 l = c > 0 ? 2 ** 223 - 1 : 2 ** 223;
        unchecked {
            // k: the fewest digits to shed so floor(x / 10^k) <= l, and
            // floor(x / 10^a) <= l iff x < (l + 1) 10^a. x <= l for n = 0, so
            // k is 0. Otherwise floor(x / 10^a) for a = n - 67 has 68 digits and one fewer digit shed has 69, both
            // above l unless the former is at most l; one more digit shed
            // leaves 67, at most l. (l + 1) 10^9 < 2^256.
            uint256 k = 0;
            if (n >= 67) {
                uint256 a = n - 67;
                k = x < (l + 1) * 10 ** a ? a : a + 1;
            }
            if (k == 0) {
                // Lifting keeps the value exactly, so T = |c| 10^e when e is
                // at least the floor.
                if (e >= FMIN) {
                    (m, f) = (x, e);
                } else {
                    (m, f) = (floorAt(x, e), FMIN);
                }
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                int256 f0 = e + int256(k);
                uint256 p = 10 ** k;
                uint256 q = x / p;
                // q 10 < l iff q < floor((l - 1) / 10) + 1, iff x is below
                // that times 10^k.
                if (f0 - 1 >= FMIN && x < ((l - 1) / 10 + 1) * p) {
                    (m, f) = (l, f0 - 1);
                } else if (f0 >= FMIN) {
                    (m, f) = (q, f0);
                } else {
                    (m, f) = (floorAt(x, e), FMIN);
                }
            }
            if (m == 0) {
                return (0, 0, 1);
            }
            if (f > FMAX) {
                // Lower f to the ceiling if m 10^(f - FMAX) is still at most l.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 j = uint256(f - FMAX);
                if (j > 67) {
                    return (0, 0, 2);
                }
                uint256 p = 10 ** j;
                // m 10^j <= l iff m <= floor(l / 10^j).
                if (m > l / p) {
                    return (0, 0, 2);
                }
                (m, f) = (m * p, FMAX);
            }
        }
        return (m, f, 0);
    }

    /// floor(x 10^e / 10^FMIN) for e < FMIN.
    function floorAt(uint256 x, int256 e) internal pure returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 d = uint256(FMIN - e);
        // x < 2^256 < 10^78.
        if (d > 77) {
            return 0;
        }
        return x / 10 ** d;
    }

    function checkPack(int256 c, int256 e, uint256 n) internal view {
        (uint256 m, int256 f, uint256 status) = truncGrid(c, e, n);
        try this.pack(c, e) returns (Float result) {
            assert(status == 0);
            (int256 rc, int256 re) = LibDecimalFloat.unpack(result);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 expected = c < 0 ? -int256(m) : int256(m);
            assert(LibHalmosExact.eqValue(rc, re, expected, f));
            if (m == 0) {
                assert(Float.unwrap(result) == bytes32(0));
            }
        } catch (bytes memory err) {
            assert(status != 0);
            assert(err.length == 68);
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4 selector = bytes4(err);
            int256 errC;
            int256 errE;
            assembly ("memory-safe") {
                errC := mload(add(err, 36))
                errE := mload(add(err, 68))
            }
            assert(selector == (status == 1 ? ExponentUnderflow.selector : ExponentOverflow.selector));
            assert(errC == c && errE == e);
        }
    }

    /// c's size class i, constant per path: 0 for |c| at most l (c fits
    /// int224, zero included), else 67 + i digits (n = 66 + i) with |c| above
    /// l. Every int256 has exactly one, as |c| > l >= 10^67 has at least 68
    /// digits and |c| <= 2^255 < 10^77 at most 77. Shedding classes take
    /// `packHints`, which `LibHalmosExact.halmos.t.sol` proves true for every
    /// c of that digit count.
    function checkPackClass(int256 c, int256 e, uint256 i) internal view {
        uint256 x = LibHalmosExact.abs(c);
        uint256 l = c > 0 ? 2 ** 223 - 1 : 2 ** 223;
        if (i == 0) {
            if (x > l) return;
            checkPack(c, e, 0);
        } else {
            uint256 n = 66 + i;
            if (x <= l || !LibHalmosExact.hasDigits(c, n) || !LibHalmosExact.packHints(c, n)) return;
            checkPack(c, e, n);
        }
    }

    /// e in [int256.min, int32.min - 78].
    function check_packBelow(int256 c, int256 e, uint256 iBits) external view {
        uint256 i = LibHalmosExact.concrete(iBits, 4);
        if (i > 10 || e > FMIN - 78) return;
        checkPackClass(c, e, i);
    }

    /// e in [int32.min - 77, int32.min], one constant e per path: case
    /// 11 j + i for e = int32.min - j.
    /// The halmos workflow, dispatched by hand, proves cases 0-98 and 781-857.
    /// Cases 99-780 (e in [int32.min - 70, int32.min - 9]) cost about 25s each
    /// under the 5-minute limit, more slices than a matrix carries, so they are
    /// out: see #511.
    function check_packLow(int256 c, uint256 jBits, uint256 iBits) external view {
        uint256 j = LibHalmosExact.concrete(jBits, 7);
        if (j > 77 || !LibHalmosExact.overlapsSlice(j * 11, j * 11 + 10)) return;
        uint256 i = LibHalmosExact.concrete(iBits, 4);
        if (i > 10 || !LibHalmosExact.inSlice(j * 11 + i)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        checkPackClass(c, FMIN - int256(j), i);
    }

    /// e in [int32.min + 1, int32.max - 11]: shedding at most 10 digits and
    /// the bound one digit back stay inside int32. Case i.
    function check_packMiddle(int256 c, int256 e, uint256 iBits) external view {
        uint256 i = LibHalmosExact.concrete(iBits, 4);
        if (i > 10 || !LibHalmosExact.inSlice(i)) return;
        if (e < FMIN + 1 || e > FMAX - 11) return;
        checkPackClass(c, e, i);
    }

    /// e in [int32.max - 10, int32.max + 67], one constant e per path: case
    /// 11 j + i for e = int32.max - 10 + j.
    function check_packHigh(int256 c, uint256 jBits, uint256 iBits) external view {
        uint256 j = LibHalmosExact.concrete(jBits, 7);
        if (j > 77 || !LibHalmosExact.overlapsSlice(j * 11, j * 11 + 10)) return;
        uint256 i = LibHalmosExact.concrete(iBits, 4);
        if (i > 10 || !LibHalmosExact.inSlice(j * 11 + i)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        checkPackClass(c, FMAX - 10 + int256(j), i);
    }

    /// e in [int32.max + 68, int256.max].
    function check_packAbove(int256 c, int256 e, uint256 iBits) external view {
        uint256 i = LibHalmosExact.concrete(iBits, 4);
        if (i > 10 || e < FMAX + 68) return;
        checkPackClass(c, e, i);
    }
}
