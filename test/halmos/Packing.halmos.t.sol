// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, LossyConversionToFloat} from "src/error/ErrDecimalFloat.sol";
import {LibHalmosExact} from "test/halmos/LibHalmosExact.sol";

/// Halmos proofs of SPEC.md's Packing rules for `packLossy`, `packLossless`,
/// `unpack` and `canonicalize`. PACK (`PackArithmeticResult.halmos.t.sol`)
/// proves the packed value is the Float toward zero for e in
/// [int32.min - 127, int32.max + 117]; these lemmas prove the exact bytes, the
/// `lossless` flag and every revert, selector and arguments, for every int256
/// c and e.
///
/// The reference `spec` follows SPEC.md's bullets: zero packs as `FLOAT_ZERO`;
/// a coefficient past int224 sheds k digits toward zero, then takes the int224
/// bound one exponent down when the shed coefficient is at most int224.max / 10
/// and that exponent fits int32; an exponent below int32.min sheds to it,
/// `FLOAT_ZERO` once every digit is gone; one above int32.max lifts the
/// coefficient by ten per step. The revert is `past`, SPEC.md's "past every
/// Float" threshold, not the headroom bullet, so the lemmas also prove the two
/// agree (#509's threshold). `lossless` is the value equality of the result
/// and c 10^e. `packLossless` reverts `ExponentOverflow` exactly when
/// `beyondExtreme` (past the largest Float of the value's sign, #509's band
/// included), otherwise `LossyConversionToFloat` exactly when the value is not
/// the packed Float, and otherwise returns `packLossy`'s Float.
///
/// The packing lemmas partition the int256 exponents, each over every int256
/// c: Below (e < int32.min - 117), Low ([int32.min - 117, int32.min + 10],
/// one constant e per case), Middle ([int32.min + 11, int32.max - 11]), High
/// ([int32.max - 10, int32.max + 117], one constant e per case) and Above
/// (e > int32.max + 117).
///
/// They return when `packHints` is false; `check_packHintsHold` and
/// `check_packFloorHintsHold` prove it true for every input they are given, so
/// the returns exclude nothing.
contract PackingHalmosTest {
    int256 internal constant FMIN = type(int32).min;
    int256 internal constant FMAX = type(int32).max;
    /// int224.max / 10, equal to 2^223 / 10.
    uint256 internal constant TEN_FOLD = uint256(int256(type(int224).max)) / 10;
    uint256 internal constant TWO_223 = 2 ** 223;
    uint256 internal constant STATUS_OK = 0;
    uint256 internal constant STATUS_OVERFLOW = 1;
    /// `FLOAT_ZERO`.
    uint256 internal constant STATUS_ZERO = 2;

    function packLossy(int256 c, int256 e) external pure returns (Float, bool) {
        return LibDecimalFloat.packLossy(c, e);
    }

    function packLossless(int256 c, int256 e) external pure returns (Float) {
        return LibDecimalFloat.packLossless(c, e);
    }

    function unpack(Float f) external pure returns (int256, int256) {
        return LibDecimalFloat.unpack(f);
    }

    function canonicalize(Float f) external pure returns (Float) {
        return LibDecimalFloat.canonicalize(f);
    }

    /// The largest int224 magnitude of c's sign.
    function limit(int256 c) internal pure returns (uint256) {
        return c > 0 ? TWO_223 - 1 : TWO_223;
    }

    /// `c` in the low 224 bits and `e` in the high 32, for nonzero c.
    function encode(int256 c, int256 e) internal pure returns (bytes32) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes32((uint256(uint32(int32(e))) << 224) | uint256(uint224(int224(c))));
    }

    /// Past every Float: |c| 10^e >= (TEN_FOLD + 1) 10^(int32.max + 1).
    function past(int256 c, int256 e) internal pure returns (bool) {
        if (c == 0) {
            return false;
        }
        uint256 x = LibHalmosExact.abs(c);
        // TEN_FOLD + 1 < 10^67, so |c| 10^(int32.max + 68) is past.
        if (e > FMAX + 67) {
            return true;
        }
        if (e > FMAX) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 d = uint256(e - FMAX - 1);
            // x 10^d > TEN_FOLD iff x > floor(TEN_FOLD / 10^d).
            return x > TEN_FOLD / 10 ** d;
        }
        if (e >= FMAX - 9) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 d = uint256(FMAX + 1 - e);
            // (TEN_FOLD + 1) 10^10 < 2^256.
            return x >= (TEN_FOLD + 1) * 10 ** d;
        }
        // x <= 2^255 < (TEN_FOLD + 1) 10^11.
        return false;
    }

    /// c 10^e > (2^223 - 1) 10^int32.max, or c 10^e < -2^223 10^int32.max.
    function beyondExtreme(int256 c, int256 e) internal pure returns (bool) {
        if (c == 0) {
            return false;
        }
        uint256 x = LibHalmosExact.abs(c);
        uint256 l = limit(c);
        // l < 10^68.
        if (e > FMAX + 67) {
            return true;
        }
        if (e > FMAX) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 d = uint256(e - FMAX);
            // x 10^d > l iff x > floor(l / 10^d).
            return x > l / 10 ** d;
        }
        if (e >= FMAX - 9) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 d = uint256(FMAX - e);
            // l 10^9 < 2^256.
            return x > l * 10 ** d;
        }
        // x <= 2^255 < l 10^10.
        return false;
    }

    /// SPEC.md's `packLossy(c, e)`: STATUS_OVERFLOW, or the coefficient rc at
    /// exponent e + d (rc zero for `FLOAT_ZERO`), d constant on every path.
    /// Every branch compares |c| with a constant.
    function spec(int256 c, int256 e) internal pure returns (uint256 status, int256 rc, int256 d) {
        if (c == 0) {
            return (STATUS_ZERO, 0, 0);
        }
        if (past(c, e)) {
            return (STATUS_OVERFLOW, 0, 0);
        }
        // c is nonzero and not past, so e <= int32.max + 67: e + 77 cannot
        // overflow.
        uint256 x = LibHalmosExact.abs(c);
        uint256 l = limit(c);
        // k: digits to shed so floor(x / 10^k) <= l, which is x < (l + 1) 10^k.
        // x < 2^256 < 2^223 10^10, so k <= 10 and every k tested is <= 9.
        uint256 k = 0;
        for (uint256 i = 0; i < 10; i++) {
            if (x >= (l + 1) * 10 ** k) {
                k++;
            }
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 ki = int256(k);
        // |floor(x / 10^k)| <= TEN_FOLD iff x < (TEN_FOLD + 1) 10^k.
        if (k > 0 && x < (TEN_FOLD + 1) * 10 ** k && e + ki - 1 >= FMIN && e + ki - 1 <= FMAX) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return (STATUS_OK, c > 0 ? int256(type(int224).max) : int256(type(int224).min), ki - 1);
        }
        int256 e1 = e + ki;
        if (e1 >= FMIN && e1 <= FMAX) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return (STATUS_OK, c / int256(10 ** k), ki);
        }
        if (e1 > FMAX) {
            // Lifting a shed coefficient, or one without headroom, is past
            // every Float by the headroom bullet, and `past` said it is not.
            assert(k == 0);
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 j = uint256(e1 - FMAX);
            assert(j <= 67);
            uint256 p = 10 ** j;
            assert(x <= l / p);
            // forge-lint: disable-next-line(unsafe-typecast)
            return (STATUS_OK, c * int256(p), -int256(j));
        }
        // Shedding k then s digits is truncating x / 10^(k + s); x < 10^78.
        if (e1 < FMIN - 77) {
            return (STATUS_ZERO, 0, 0);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 shed = k + uint256(FMIN - e1);
        if (shed >= 78 || x < 10 ** shed) {
            return (STATUS_ZERO, 0, 0);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return (STATUS_OK, c / int256(10 ** shed), int256(shed));
    }

    /// rc 10^(e + d) == c 10^e. For d >= 0, rc truncates c / 10^d or is below
    /// it, so the product cannot overflow; for d < 0, rc is c 10^-d in int224.
    function sameValue(int256 rc, int256 d, int256 c) internal pure returns (bool) {
        unchecked {
            if (d >= 0) {
                // forge-lint: disable-next-line(unsafe-typecast)
                return rc * int256(10 ** uint256(d)) == c;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return rc == c * int256(10 ** uint256(-d));
        }
    }

    /// floor(x / 10^n) fits int224 with c's sign, for x = |c|.
    function shedFits(int256 c, uint256 n) internal pure returns (bool) {
        // |c| <= 2^255 < 2^223 10^10.
        if (n >= 10) {
            return true;
        }
        uint256 x = LibHalmosExact.abs(c);
        return c >= 0 ? x < TWO_223 * 10 ** n : x < (TWO_223 + 1) * 10 ** n;
    }

    /// The facts for one chain t = c / 10^n, divided by ten per step.
    function chainHints(int256 c, int256 t, uint256 n, uint256 steps, int256 e, bool floor)
        internal
        pure
        returns (bool)
    {
        uint256 x = LibHalmosExact.abs(c);
        unchecked {
            int256 tenFold = type(int224).max / 10;
            for (uint256 i = 0; i < steps; i++) {
                // forge-lint: disable-next-line(unsafe-typecast)
                if ((int224(t) == t) != shedFits(c, n)) return false;
                // forge-lint: disable-next-line(unsafe-typecast)
                if ((uint256(t + tenFold) <= uint256(tenFold + tenFold)) != (x < (TEN_FOLD + 1) * 10 ** n)) {
                    return false;
                }
                // forge-lint: disable-next-line(unsafe-typecast)
                int256 ni = int256(n);
                if (floor && e < FMIN - ni && e >= FMIN - ni - 67) {
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint256 s = uint256(FMIN - ni - e);
                    // forge-lint: disable-next-line(unsafe-typecast)
                    if ((t / int256(10 ** s) == 0) != (n + s >= 78 || x < 10 ** (n + s))) return false;
                }
                t /= 10;
                n++;
            }
        }
        return true;
    }

    /// True for every int256 c and e. `packLossy` sheds digits from c, c / 1e5
    /// or c / 1e8 (by whether c / 1e72 and c / 1e75 are zero), one per step,
    /// at most 5, 3 and 2 steps, and below the int32 floor divides the result
    /// by 10^s. Halmos branches on division as an uninterpreted function, so
    /// these facts give the branch solver each test on such a quotient
    /// t = trunc(c / 10^n) as the same test on |c|: t fits int224, |t| <=
    /// int224.max / 10, and (with `floor`) t / 10^s is zero.
    function packHints(int256 c, int256 e, bool floor) internal pure returns (bool) {
        if (!LibHalmosExact.divHint(c, 1e72) || !LibHalmosExact.divHint(c, 1e75)) return false;
        unchecked {
            return chainHints(c, c, 0, 6, e, floor) && chainHints(c, c / 1e5, 5, 4, e, floor)
                && chainHints(c, c / 1e8, 8, 3, e, floor);
        }
    }

    /// `err` is exactly `selector` with arguments (c, e).
    function isError(bytes memory err, bytes4 selector, int256 c, int256 e) internal pure returns (bool) {
        if (err.length != 68) {
            return false;
        }
        int256 a;
        int256 b;
        assembly ("memory-safe") {
            a := mload(add(err, 36))
            b := mload(add(err, 68))
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(err) == selector && a == c && b == e;
    }

    function checkPacking(int256 c, int256 e, bool floor) internal view {
        if (!packHints(c, e, floor)) return;
        (uint256 status, int256 rc, int256 d) = spec(c, e);
        // FLOAT_ZERO is all bits zero, and equals the value only for c zero.
        bytes32 expected;
        bool exact = c == 0;
        if (status == STATUS_OK) {
            expected = encode(rc, e + d);
            exact = sameValue(rc, d, c);
        }

        try this.packLossy(c, e) returns (Float f, bool lossless) {
            assert(status != STATUS_OVERFLOW);
            assert(Float.unwrap(f) == expected);
            assert(lossless == exact);
        } catch (bytes memory err) {
            assert(status == STATUS_OVERFLOW);
            assert(isError(err, ExponentOverflow.selector, c, e));
        }

        bool beyond = beyondExtreme(c, e);
        try this.packLossless(c, e) returns (Float f) {
            assert(!beyond);
            assert(status != STATUS_OVERFLOW && exact);
            assert(Float.unwrap(f) == expected);
        } catch (bytes memory err) {
            if (beyond) {
                assert(isError(err, ExponentOverflow.selector, c, e));
            } else {
                assert(status != STATUS_OVERFLOW && !exact);
                assert(isError(err, LossyConversionToFloat.selector, c, e));
            }
        }
    }

    function check_packingBelow(int256 c, int256 e) external view {
        if (e >= FMIN - 117) return;
        checkPacking(c, e, false);
    }

    /// Case j is e = int32.min - 117 + j.
    function check_packingLow(int256 c, uint256 j) external view {
        j = LibHalmosExact.concrete(j, 7);
        if (!LibHalmosExact.inSlice(j)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        checkPacking(c, FMIN - 117 + int256(j), true);
    }

    function check_packingMiddle(int256 c, int256 e) external view {
        if (e < FMIN + 11 || e > FMAX - 11) return;
        checkPacking(c, e, false);
    }

    /// Case j is e = int32.max - 10 + j.
    function check_packingHigh(int256 c, uint256 j) external view {
        j = LibHalmosExact.concrete(j, 7);
        if (!LibHalmosExact.inSlice(j)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        checkPacking(c, FMAX - 10 + int256(j), false);
    }

    function check_packingAbove(int256 c, int256 e) external view {
        if (e <= FMAX + 117) return;
        checkPacking(c, e, false);
    }

    function check_packHintsHold(int256 c) external pure {
        assert(packHints(c, 0, false));
    }

    /// Case j is e = int32.min - 117 + j, as `check_packingLow`.
    function check_packFloorHintsHold(int256 c, uint256 j) external view {
        j = LibHalmosExact.concrete(j, 7);
        if (!LibHalmosExact.inSlice(j)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        assert(packHints(c, FMIN - 117 + int256(j), true));
    }

    /// `unpack` sign-extends the low 224 bits and the high 32, for every
    /// bytes32, and never reverts.
    function check_unpack(bytes32 b) external view {
        try this.unpack(Float.wrap(b)) returns (int256 c, int256 e) {
            // forge-lint: disable-next-line(unsafe-typecast)
            assert(c == int256(int224(uint224(uint256(b)))));
            // forge-lint: disable-next-line(unsafe-typecast)
            assert(e == int256(int32(uint32(uint256(b) >> 224))));
        } catch {
            assert(false);
        }
    }

    /// `canonicalize` of a Float with zero coefficient, any exponent, is
    /// `FLOAT_ZERO`.
    function check_canonicalizeZero(bytes32 b) external view {
        // forge-lint: disable-next-line(unsafe-typecast)
        if (int224(uint224(uint256(b))) != 0) return;
        try this.canonicalize(Float.wrap(b)) returns (Float r) {
            assert(Float.unwrap(r) == 0);
        } catch {
            assert(false);
        }
    }

    /// For c 10^e with c nonzero: the canonical form is c 10^t at e - t for the
    /// largest t with c 10^t in int224 and e - t >= int32.min: every
    /// representative of c 10^e at a lower exponent is c times a power of
    /// ten. So it is `eq` to the input, and is its own canonical form. Never
    /// reverts. Case j is the digit count of |c| less one; every nonzero int224
    /// has |c| in [1, 2^223] < 10^68, so cases [0, 67] cover every input.
    function check_canonicalize(bytes32 b, uint256 j) external view {
        j = LibHalmosExact.concrete(j, 7);
        if (j > 67 || !LibHalmosExact.inSlice(j)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 c = int224(uint224(uint256(b)));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 e = int32(uint32(uint256(b) >> 224));
        uint256 x = LibHalmosExact.abs(c);
        if (x < 10 ** j || (j < 67 && x >= 10 ** (j + 1))) return;
        uint256 l = limit(c);
        uint256 t = 0;
        // x >= 1 and l < 10^68, so t <= 67.
        for (uint256 u = 1; u <= 67; u++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            if (x <= l / 10 ** u && e - int256(u) >= FMIN) {
                t = u;
            } else {
                break;
            }
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 expected = encode(c * int256(10 ** t), e - int256(t));
        try this.canonicalize(Float.wrap(b)) returns (Float r) {
            assert(Float.unwrap(r) == expected);
            try this.canonicalize(r) returns (Float r2) {
                assert(Float.unwrap(r2) == expected);
            } catch {
                assert(false);
            }
        } catch {
            assert(false);
        }
    }
}
