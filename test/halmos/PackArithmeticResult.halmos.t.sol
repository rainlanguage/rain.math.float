// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, ExponentUnderflow} from "src/error/ErrDecimalFloat.sol";
import {LibHalmosExact} from "test/halmos/LibHalmosExact.sol";

/// Lemma PACK of the add/sub proof (see `AddSubRoundOnce.halmos.t.sol`).
///
/// `packArithmeticResult(c, e)` is the Float closest to c 10^e that does not
/// exceed it in magnitude, reverting `ExponentUnderflow` when that is zero for
/// a nonzero c and `ExponentOverflow` when it is no Float. Checked for every
/// int256 c and every e in [int32.min - 127, int32.max + 117], which holds every
/// exponent `LibDecimalFloatImplementation.add` returns for two Floats
/// ([int32.min - 76, int32.max - 7]: maximizing lowers an exponent by 8 to 76
/// digits, a carry raises it by one).
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
    function truncGrid(int256 c, int256 e) internal pure returns (uint256 m, int256 f, uint256 status) {
        if (c == 0) {
            return (0, 0, 0);
        }
        uint256 x = LibHalmosExact.abs(c);
        uint256 l = c > 0 ? 2 ** 223 - 1 : 2 ** 223;
        unchecked {
            // k: digits to shed so floor(x / 10^k) <= l. x < 2^256 < 2^223 10^10,
            // so k <= 10.
            uint256 k = 0;
            for (uint256 i = 0; i < 10; i++) {
                if (x / 10 ** k > l) {
                    k++;
                }
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
                uint256 q = x / 10 ** k;
                if (f0 - 1 >= FMIN && l > q * 10) {
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

    function checkPack(int256 c, int256 e) internal view {
        (uint256 m, int256 f, uint256 status) = truncGrid(c, e);
        try this.pack(c, e) returns (Float result) {
            assert(status == 0);
            (int256 rc, int256 re) = LibDecimalFloat.unpack(result);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 expected = c < 0 ? -int256(m) : int256(m);
            assert(LibHalmosExact.eqValue(rc, re, expected, f));
        } catch (bytes memory err) {
            // The selector is the first four bytes of the revert data.
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4 selector = bytes4(err);
            if (status == 1) {
                assert(selector == ExponentUnderflow.selector);
            } else if (status == 2) {
                assert(selector == ExponentOverflow.selector);
            } else {
                assert(false);
            }
        }
    }

    /// e in [int32.min + 1, int32.max - 11]: shedding at most 10 digits and
    /// the bound one digit back stay inside int32.
    function check_packMiddle(int256 c, int256 e) external view {
        if (e < FMIN + 1 || e > FMAX - 11) return;
        checkPack(c, e);
    }

    /// e in [int32.min - 127, int32.min], one constant e per path.
    function check_packLow(int256 c, uint256 j) external view {
        j = LibHalmosExact.concrete(j, 7);
        // forge-lint: disable-next-line(unsafe-typecast)
        checkPack(c, FMIN - int256(j));
    }

    /// e in [int32.max - 10, int32.max + 117], one constant e per path.
    function check_packHigh(int256 c, uint256 j) external view {
        j = LibHalmosExact.concrete(j, 7);
        // forge-lint: disable-next-line(unsafe-typecast)
        checkPack(c, FMAX - 10 + int256(j));
    }
}
