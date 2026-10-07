// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {LibFormatDecimalFloatPr321} from "test/lib/LibFormatDecimalFloatPr321.sol";
import {LibParseDecimalFloatPr321} from "test/lib/LibParseDecimalFloatPr321.sol";

/// Every input returns the same bytes, or reverts with the same bytes, as
/// `toDecimalString`, `parseDecimalFloat` and `parseDecimalFloatInline` before
/// #310's format and parse changes.
contract LibDecimalFloatFormatParsePr321EquivalenceTest is Test {
    function baseFormat(Float f, bool scientific) external pure returns (string memory) {
        return LibFormatDecimalFloatPr321.toDecimalString(f, scientific);
    }

    function prFormat(Float f, bool scientific) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(f, scientific);
    }

    /// Both parse entry points, with the inline cursor relative to the start.
    function baseParse(string memory str) external pure returns (bytes4, Float, bytes4, uint256, int256, int256) {
        (bytes4 e, Float f) = LibParseDecimalFloatPr321.parseDecimalFloat(str);
        uint256 start;
        assembly ("memory-safe") {
            start := add(str, 0x20)
        }
        (bytes4 ie, uint256 cursor, int256 c, int256 x) =
            LibParseDecimalFloatPr321.parseDecimalFloatInline(start, start + bytes(str).length);
        return (e, f, ie, cursor - start, c, x);
    }

    function prParse(string memory str) external pure returns (bytes4, Float, bytes4, uint256, int256, int256) {
        (bytes4 e, Float f) = LibParseDecimalFloat.parseDecimalFloat(str);
        uint256 start;
        assembly ("memory-safe") {
            start := add(str, 0x20)
        }
        (bytes4 ie, uint256 cursor, int256 c, int256 x) =
            LibParseDecimalFloat.parseDecimalFloatInline(start, start + bytes(str).length);
        return (e, f, ie, cursor - start, c, x);
    }

    function same(bytes memory baseCall, bytes memory prCall) internal view {
        (bool baseOk, bytes memory baseRet) = address(this).staticcall(baseCall);
        (bool prOk, bytes memory prRet) = address(this).staticcall(prCall);
        assertEq(prOk, baseOk, "success");
        assertEq(prRet, baseRet, "bytes");
    }

    function checkFormat(Float f) internal view {
        same(abi.encodeCall(this.baseFormat, (f, false)), abi.encodeCall(this.prFormat, (f, false)));
        same(abi.encodeCall(this.baseFormat, (f, true)), abi.encodeCall(this.prFormat, (f, true)));
    }

    function checkParse(string memory str) internal view {
        same(abi.encodeCall(this.baseParse, (str)), abi.encodeCall(this.prParse, (str)));
    }

    /// A coefficient of `d` digits in [1, 68], either sign, `x` choosing where
    /// in the digit count it falls, clamped to int224.
    function ofDigits(uint256 d, uint256 x, bool negative) internal pure returns (int256 c) {
        d = bound(d, 1, 68);
        uint256 lo = 10 ** (d - 1);
        uint256 hi = d == 68 ? uint256(int256(type(int224).max)) : 10 ** d - 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        c = int256(bound(x, lo, hi));
        if (negative) c = -c;
    }

    /// A short significand followed by `z` zeros, the shape of every
    /// maximized arithmetic result.
    function withTrailingZeros(uint256 z, uint256 x, bool negative) internal pure returns (int256 c) {
        z = bound(z, 0, 67);
        uint256 v = bound(x, 1, 999) * 10 ** z;
        if (v > uint256(int256(type(int224).max))) v = 10 ** z;
        // forge-lint: disable-next-line(unsafe-typecast)
        c = int256(v);
        if (negative) c = -c;
    }

    function exponentOf(uint256 kind, int256 x) internal pure returns (int256) {
        kind = bound(kind, 0, 4);
        if (kind == 0) return bound(x, -80, 80);
        if (kind == 1) return bound(x, -1100, 1100);
        if (kind == 2) return bound(x, type(int32).min, type(int32).min + int256(100));
        if (kind == 3) return bound(x, type(int32).max - int256(100), type(int32).max);
        return int256(int32(x));
    }

    function testFormatPr321Equivalence(uint256 kind, uint256 d, uint256 x, bool negative, uint256 ek, int256 e)
        external
        view
    {
        int256 c = kind % 2 == 0 ? ofDigits(d, x, negative) : withTrailingZeros(d, x, negative);
        checkFormat(LibDecimalFloat.packLossless(c, exponentOf(ek, e)));
    }

    function testFormatPr321EquivalenceRaw(bytes32 f) external view {
        checkFormat(Float.wrap(f));
    }

    /// Digit counts around each boundary, at both ends, both signs, at every
    /// exponent in [-80, 80] and at the exponent bounds.
    function testFormatPr321EquivalenceDigitCounts() external view {
        uint8[12] memory counts = [1, 2, 3, 9, 17, 18, 19, 33, 34, 66, 67, 68];
        for (uint256 j = 0; j < counts.length; j++) {
            uint256 d = counts[j];
            int256 lo = ofDigits(d, 0, false);
            int256 hi = ofDigits(d, type(uint256).max, false);
            for (int256 e = -80; e <= 80; e++) {
                checkFormat(LibDecimalFloat.packLossless(lo, e));
                checkFormat(LibDecimalFloat.packLossless(-hi, e));
            }
            checkFormat(LibDecimalFloat.packLossless(hi, type(int32).max));
            checkFormat(LibDecimalFloat.packLossless(-lo, type(int32).min));
            checkFormat(LibDecimalFloat.packLossless(lo, 1000));
            checkFormat(LibDecimalFloat.packLossless(-hi, -1000));
        }
        checkFormat(LibDecimalFloat.packLossless(type(int224).min, 0));
    }

    /// Characters a decimal float string is made of, and one that it is not.
    bytes internal constant ALPHABET = "0123456789000000.-+eEx";

    function testParsePr321Equivalence(bytes memory seed) external view {
        bytes memory str = new bytes(seed.length);
        for (uint256 i = 0; i < seed.length; i++) {
            str[i] = ALPHABET[uint8(seed[i]) % ALPHABET.length];
        }
        checkParse(string(str));
    }

    function testParsePr321EquivalenceRaw(string memory str) external view {
        checkParse(str);
    }

    /// Formatted floats parse the same.
    function testParsePr321EquivalenceFormatted(uint256 kind, uint256 d, uint256 x, bool negative, int256 e, bool sci)
        external
        view
    {
        int256 c = kind % 2 == 0 ? ofDigits(d, x, negative) : withTrailingZeros(d, x, negative);
        Float f = LibDecimalFloat.packLossless(c, bound(e, -100, 100));
        try this.baseFormat(f, sci) returns (string memory str) {
            checkParse(str);
        } catch {}
    }

    function testParsePr321EquivalenceExamples() external view {
        checkParse("");
        checkParse("0");
        checkParse("0.0");
        checkParse("0.000");
        checkParse("-0.0");
        checkParse("1.");
        checkParse(".5");
        checkParse("1.50000");
        checkParse("10.0100");
        checkParse("1.0e5");
        checkParse("1.000000000000000000000000000000000000000000000000000000000000000000000001");
        checkParse("1.10000000000000000000000000000000000000000000000000000000000000000000000000000");
        checkParse("-1.5e-10");
        checkParse("1e2147483648");
        checkParse("1.5e");
        checkParse("1.5e+3");
    }
}
