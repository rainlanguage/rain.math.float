// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {
    NegativeFixedDecimalConversion,
    FixedDecimalOverflow,
    LossyConversionToFloat,
    LossyConversionFromFloat
} from "src/error/ErrDecimalFloat.sol";
import {LibHalmosExact} from "test/halmos/LibHalmosExact.sol";

/// Halmos proof of SPEC.md "Fixed-decimal conversions" for
/// `fromFixedDecimalLossy`, `fromFixedDecimalLossless`, `toFixedDecimalLossy`
/// and `toFixedDecimalLossless`: values, lossless flags, revert selectors and
/// revert arguments.
///
/// from: every uint256 v and uint8 d in one lemma each.
///
/// to: both overloads, the (int256 c, int256 e) pair and the Float (c in the
/// low 224 bits, e in the high 32). With k = e + d over the integers, the
/// slices LOW (k < -77), MID (k in [-77, 77], one constant k per path) and
/// HIGH (k > 77) partition every (c, e, d), so the three lemmas of each
/// overload cover every input. MID's `j` only names k: the j it returns on
/// (j > 154) name no k, and every (c, e, d) with k in [-77, 77] is reached by
/// e = k - d.
contract FixedDecimalHalmosTest {
    uint256 internal constant OK = 0;
    uint256 internal constant NEGATIVE = 1;
    uint256 internal constant OVERFLOW = 2;
    uint256 internal constant LOSSY = 3;

    uint256 internal constant LOSSY_PAIR = 0;
    uint256 internal constant LOSSLESS_PAIR = 1;
    uint256 internal constant LOSSY_FLOAT = 2;
    uint256 internal constant LOSSLESS_FLOAT = 3;

    function fromLossy(uint256 v, uint8 d) external pure returns (int256, int256, bool) {
        return LibDecimalFloat.fromFixedDecimalLossy(v, d);
    }

    function fromLossless(uint256 v, uint8 d) external pure returns (int256, int256) {
        return LibDecimalFloat.fromFixedDecimalLossless(v, d);
    }

    function toLossyPair(int256 c, int256 e, uint8 d) external pure returns (uint256, bool) {
        return LibDecimalFloat.toFixedDecimalLossy(c, e, d);
    }

    function toLosslessPair(int256 c, int256 e, uint8 d) external pure returns (uint256) {
        return LibDecimalFloat.toFixedDecimalLossless(c, e, d);
    }

    function toLossyFloat(Float f, uint8 d) external pure returns (uint256, bool) {
        return LibDecimalFloat.toFixedDecimalLossy(f, d);
    }

    function toLosslessFloat(Float f, uint8 d) external pure returns (uint256) {
        return LibDecimalFloat.toFixedDecimalLossless(f, d);
    }

    /// Word i of the arguments after the selector.
    function arg(bytes memory err, uint256 i) internal pure returns (uint256 w) {
        assembly ("memory-safe") {
            w := mload(add(err, add(36, mul(32, i))))
        }
    }

    /// err is exactly `selector` followed by `words` argument words.
    function isError(bytes memory err, bytes4 selector, uint256 words) internal pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return err.length == 4 + 32 * words && bytes4(err) == selector;
    }

    /// SPEC: `(v, -d, true)` for v <= int256.max, otherwise
    /// `(v / 10, -d + 1, v % 10 == 0)`.
    function fromRule(uint256 v, uint8 d) internal pure returns (int256 c, int256 e, bool lossless) {
        int256 nd = -int256(uint256(d));
        if (v <= uint256(type(int256).max)) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return (int256(v), nd, true);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return (int256(v / 10), nd + 1, v % 10 == 0);
    }

    /// c 10^(e + d) is v truncated toward zero, and exactly v iff lossless.
    function fromValueHolds(uint256 v, uint8 d, int256 c, int256 e, bool lossless) internal pure returns (bool) {
        if (c < 0) return false;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 x = uint256(c);
        int256 k = e + int256(uint256(d));
        if (k == 0) return x == v && lossless;
        if (k != 1 || x > type(uint256).max / 10) return false;
        // x 10 <= v < x 10 + 10.
        return x * 10 <= v && v - x * 10 < 10 && lossless == (x * 10 == v);
    }

    function check_fromFixedDecimalLossy(uint256 v, uint8 d) external view {
        (int256 sc, int256 se, bool sl) = fromRule(v, d);
        assert(fromValueHolds(v, d, sc, se, sl));
        try this.fromLossy(v, d) returns (int256 c, int256 e, bool lossless) {
            assert(c == sc && e == se && lossless == sl);
        } catch {
            assert(false);
        }
    }

    function check_fromFixedDecimalLossless(uint256 v, uint8 d) external view {
        (int256 sc, int256 se, bool sl) = fromRule(v, d);
        try this.fromLossless(v, d) returns (int256 c, int256 e) {
            assert(sl && c == sc && e == se);
        } catch (bytes memory err) {
            assert(!sl);
            assert(isError(err, LossyConversionToFloat.selector, 2));
            // forge-lint: disable-next-line(unsafe-typecast)
            assert(arg(err, 0) == uint256(sc) && arg(err, 1) == uint256(se));
        }
    }

    /// The Float with c in the low 224 bits and e in the high 32.
    function floatOf(int224 c, int32 e) internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return Float.wrap(bytes32((uint256(uint32(e)) << 224) | uint256(uint224(c))));
    }

    /// Runs `mode`'s overload on (c, e, d) and checks it against the expected
    /// `status`, value `m` and lossy flag. The lossless overloads add LOSSY
    /// for an OK result that is not lossless.
    function checkTo(uint256 mode, int256 c, int256 e, uint8 d, uint256 m, bool lossless, uint256 status)
        internal
        view
    {
        bool isLossless = mode == LOSSLESS_PAIR || mode == LOSSLESS_FLOAT;
        if (isLossless && status == OK && !lossless) {
            status = LOSSY;
        }
        bytes memory err;
        if (mode == LOSSY_PAIR || mode == LOSSY_FLOAT) {
            uint256 rm;
            bool rl;
            bool ok;
            if (mode == LOSSY_PAIR) {
                try this.toLossyPair(c, e, d) returns (uint256 a, bool b) {
                    (rm, rl, ok) = (a, b, true);
                } catch (bytes memory r) {
                    err = r;
                }
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                try this.toLossyFloat(floatOf(int224(c), int32(e)), d) returns (uint256 a, bool b) {
                    (rm, rl, ok) = (a, b, true);
                } catch (bytes memory r) {
                    err = r;
                }
            }
            if (ok) {
                assert(status == OK && rm == m && rl == lossless);
                return;
            }
        } else {
            uint256 rm;
            bool ok;
            if (mode == LOSSLESS_PAIR) {
                try this.toLosslessPair(c, e, d) returns (uint256 a) {
                    (rm, ok) = (a, true);
                } catch (bytes memory r) {
                    err = r;
                }
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                try this.toLosslessFloat(floatOf(int224(c), int32(e)), d) returns (uint256 a) {
                    (rm, ok) = (a, true);
                } catch (bytes memory r) {
                    err = r;
                }
            }
            if (ok) {
                assert(status == OK && rm == m);
                return;
            }
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint256 wc, uint256 we) = (uint256(c), uint256(e));
        if (status == NEGATIVE) {
            assert(isError(err, NegativeFixedDecimalConversion.selector, 2));
            assert(arg(err, 0) == wc && arg(err, 1) == we);
        } else if (status == OVERFLOW) {
            assert(isError(err, FixedDecimalOverflow.selector, 3));
            assert(arg(err, 0) == wc && arg(err, 1) == we && arg(err, 2) == uint256(d));
        } else if (status == LOSSY) {
            assert(isError(err, LossyConversionFromFloat.selector, 2));
            assert(arg(err, 0) == wc && arg(err, 1) == we);
        } else {
            assert(false);
        }
    }

    /// LOW: k < -77. A nonzero |c| 10^k is below 2^255 10^-78 < 1, so it
    /// truncates to 0 and is not exact.
    function checkLow(uint256 mode, int256 c, int256 e, uint8 d) internal view {
        if (e >= -77 - int256(uint256(d))) return;
        if (c < 0) return checkTo(mode, c, e, d, 0, false, NEGATIVE);
        checkTo(mode, c, e, d, 0, c == 0, OK);
    }

    /// HIGH: k > 77. A nonzero c 10^k is at least 10^78 > 2^256.
    function checkHigh(uint256 mode, int256 c, int256 e, uint8 d) internal view {
        if (e <= 77 - int256(uint256(d))) return;
        if (c < 0) return checkTo(mode, c, e, d, 0, false, NEGATIVE);
        if (c == 0) return checkTo(mode, c, e, d, 0, true, OK);
        checkTo(mode, c, e, d, 0, false, OVERFLOW);
    }

    /// MID: k = e + d in [-77, 77], one constant k per path, e = k - d.
    /// c 10^k truncated toward zero, exact iff nothing is dropped; at or above
    /// 2^256 overflows.
    function checkMid(uint256 mode, int256 c, uint8 d, uint256 j) internal view {
        j = LibHalmosExact.concrete(j, 8);
        if (j > 154) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 k = int256(j) - 77;
        int256 e = k - int256(uint256(d));
        if (c < 0) return checkTo(mode, c, e, d, 0, false, NEGATIVE);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 x = uint256(c);
        if (k < 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 p = 10 ** uint256(-k);
            uint256 q = x / p;
            return checkTo(mode, c, e, d, q, q * p == x, OK);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 s = 10 ** uint256(k);
        // c 10^k > uint256.max iff c > floor(uint256.max / 10^k).
        if (x > type(uint256).max / s) return checkTo(mode, c, e, d, 0, false, OVERFLOW);
        checkTo(mode, c, e, d, x * s, true, OK);
    }

    function check_toFixedDecimalLossyPairLow(int256 c, int256 e, uint8 d) external view {
        checkLow(LOSSY_PAIR, c, e, d);
    }

    function check_toFixedDecimalLossyPairMid(int256 c, uint8 d, uint256 j) external view {
        checkMid(LOSSY_PAIR, c, d, j);
    }

    function check_toFixedDecimalLossyPairHigh(int256 c, int256 e, uint8 d) external view {
        checkHigh(LOSSY_PAIR, c, e, d);
    }

    function check_toFixedDecimalLosslessPairLow(int256 c, int256 e, uint8 d) external view {
        checkLow(LOSSLESS_PAIR, c, e, d);
    }

    function check_toFixedDecimalLosslessPairMid(int256 c, uint8 d, uint256 j) external view {
        checkMid(LOSSLESS_PAIR, c, d, j);
    }

    function check_toFixedDecimalLosslessPairHigh(int256 c, int256 e, uint8 d) external view {
        checkHigh(LOSSLESS_PAIR, c, e, d);
    }

    function check_toFixedDecimalLossyFloatLow(int224 c, int32 e, uint8 d) external view {
        checkLow(LOSSY_FLOAT, c, e, d);
    }

    function check_toFixedDecimalLossyFloatMid(int224 c, uint8 d, uint256 j) external view {
        checkMid(LOSSY_FLOAT, c, d, j);
    }

    function check_toFixedDecimalLossyFloatHigh(int224 c, int32 e, uint8 d) external view {
        checkHigh(LOSSY_FLOAT, c, e, d);
    }

    function check_toFixedDecimalLosslessFloatLow(int224 c, int32 e, uint8 d) external view {
        checkLow(LOSSLESS_FLOAT, c, e, d);
    }

    function check_toFixedDecimalLosslessFloatMid(int224 c, uint8 d, uint256 j) external view {
        checkMid(LOSSLESS_FLOAT, c, d, j);
    }

    function check_toFixedDecimalLosslessFloatHigh(int224 c, int32 e, uint8 d) external view {
        checkHigh(LOSSLESS_FLOAT, c, e, d);
    }
}
