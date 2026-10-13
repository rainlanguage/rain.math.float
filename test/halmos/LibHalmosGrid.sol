// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "src/lib/LibDecimalFloat.sol";
import {LibHalmosExact} from "test/halmos/LibHalmosExact.sol";

/// References built from SPEC.md's definitions alone, for the Halmos proofs.
library LibHalmosGrid {
    int256 internal constant FMIN = type(int32).min;
    int256 internal constant FMAX = type(int32).max;
    uint256 internal constant M128 = type(uint128).max;

    /// A Float's parts by the Terms layout: e in the high 32 bits, c in the low
    /// 224, each sign-extended.
    function parts(Float f) internal pure returns (int256 c, int256 e) {
        uint256 x = uint256(Float.unwrap(f));
        // forge-lint: disable-next-line(unsafe-typecast)
        c = int256(int224(uint224(x)));
        // forge-lint: disable-next-line(unsafe-typecast)
        e = int256(int32(uint32(x >> 224)));
    }

    /// The Float with parts (c, e), c an int224 and e an int32.
    function float(int256 c, int256 e) internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return Float.wrap(bytes32((uint256(e) << 224) | uint256(uint224(uint256(c)))));
    }

    function bytesEq(bytes memory x, bytes memory y) internal pure returns (bool) {
        if (x.length != y.length) return false;
        for (uint256 i = 0; i < x.length; i++) {
            if (x[i] != y[i]) return false;
        }
        return true;
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

    /// a b = hi 2^256 + lo, from 128-bit limbs: each limb product is below
    /// 2^256, and mid < 3 2^128.
    function mul512(uint256 a, uint256 b) internal pure returns (uint256 hi, uint256 lo) {
        unchecked {
            uint256 a0 = a & M128;
            uint256 a1 = a >> 128;
            uint256 b0 = b & M128;
            uint256 b1 = b >> 128;
            uint256 p00 = a0 * b0;
            uint256 p01 = a0 * b1;
            uint256 p10 = a1 * b0;
            uint256 mid = (p00 >> 128) + (p01 & M128) + (p10 & M128);
            lo = (p00 & M128) | (mid << 128);
            hi = a1 * b1 + (p01 >> 128) + (p10 >> 128) + (mid >> 128);
        }
    }

    /// (ah, al) <= (bh, bl) as 512-bit numbers.
    function le512(uint256 ah, uint256 al, uint256 bh, uint256 bl) internal pure returns (bool) {
        return ah < bh || (ah == bh && al <= bl);
    }

    /// (ah, al) + b as a 512-bit number; the sum is below 2^512 for every use.
    function add512(uint256 ah, uint256 al, uint256 b) internal pure returns (uint256 h, uint256 l) {
        unchecked {
            l = al + b;
            h = ah + (l < al ? 1 : 0);
        }
    }
}
