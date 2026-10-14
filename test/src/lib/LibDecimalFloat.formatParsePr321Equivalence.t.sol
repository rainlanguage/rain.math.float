// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../../src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "../../../src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "../../../src/lib/parse/LibParseDecimalFloat.sol";
import {LibFormatDecimalFloatPr321} from "../../lib/LibFormatDecimalFloatPr321.sol";
import {LibParseDecimalFloatPr321} from "../../lib/LibParseDecimalFloatPr321.sol";
import {UnformatableExponent} from "../../../src/error/ErrFormat.sol";
import {ExponentOverflow} from "../../../src/error/ErrDecimalFloat.sol";
import {
    ParseDecimalPrecisionLoss,
    MalformedExponentDigits,
    MalformedDecimalPoint
} from "../../../src/error/ErrParse.sol";
import {ParseDecimalOverflow} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {LibTestDecimalLiteral, Literal} from "../../lib/LibTestDecimalLiteral.sol";
import {LibExactFloat} from "../../lib/LibExactFloat.sol";

/// Every input returns the same bytes, or reverts with the same bytes, as
/// `toDecimalString`, `parseDecimalFloat` and `parseDecimalFloatInline` before
/// #310's format and parse changes, except a Float formatted that only a guard
/// #376 deleted or the raw exponent cap #449 moved refused, a Float past the
/// cap on its canonical exponent, and a well formed literal that is no Float.
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

    function parseFrozen(string memory text) external pure returns (bytes4, Float) {
        return LibParseDecimalFloatPr321.parseDecimalFloat(text);
    }

    function same(bytes memory baseCall, bytes memory prCall) internal view {
        (bool baseOk, bytes memory baseRet) = address(this).staticcall(baseCall);
        (bool prOk, bytes memory prRet) = address(this).staticcall(prCall);
        assertEq(prOk, baseOk, "success");
        assertEq(prRet, baseRet, "bytes");
    }

    /// Where the base refused a Float only by a guard #376 deleted, or by the
    /// cap on its raw exponent that #449 moved to the canonical exponent, the
    /// library formats it, as the format tests check against the oracle. Past
    /// the cap on the canonical exponent the library reverts with it.
    function checkFormat(Float f) internal view {
        (int256 c, int256 e) = LibDecimalFloat.unpack(f);
        int256 canonical = LibExactFloat.canonicalExponent(c, e);
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        for (uint256 i = 0; i < 2; i++) {
            bool scientific = i == 1;
            bytes memory baseCall = abi.encodeCall(this.baseFormat, (f, scientific));
            bytes memory prCall = abi.encodeCall(this.prFormat, (f, scientific));
            (bool baseOk, bytes memory baseRet) = address(this).staticcall(baseCall);
            bool pastCap = !scientific && c != 0 && (canonical > cap || canonical < -cap);
            if (pastCap) {
                (bool prOk, bytes memory prRet) = address(this).staticcall(prCall);
                assertFalse(prOk, "past the canonical cap");
                assertEq(prRet, abi.encodeWithSelector(UnformatableExponent.selector, canonical), "pr error");
            } else if (!baseOk) {
                assertEq(baseRet, abi.encodeWithSelector(UnformatableExponent.selector, e), "base error");
                (bool prOk,) = address(this).staticcall(prCall);
                assertTrue(prOk, "guard deleted by #376 or #449");
            } else {
                same(baseCall, prCall);
            }
        }
    }

    /// #375 chose the errors of literals that are no Float by value, which
    /// the parse tests check against the rule, so only those are skipped.
    /// An `e` without digits is `MalformedExponentDigits`, and a `.` without
    /// digits `MalformedDecimalPoint`, where it stopped
    /// (SPEC, Parse). The base instead returned `ParseDecimalPrecisionLoss`
    /// or `ParseDecimalOverflow` from a mantissa past its int256 steps before
    /// reading the `e` or `.`; #375 reads the whole literal first. Only that
    /// difference is allowed.
    function checkParse(string memory str) internal view {
        Literal memory lit = LibTestDecimalLiteral.read(bytes(str));
        if (lit.malformed == 0 && !LibTestDecimalLiteral.isFloat(lit)) {
            return;
        }
        bytes memory baseCall = abi.encodeCall(this.baseParse, (str));
        bytes memory prCall = abi.encodeCall(this.prParse, (str));
        if (lit.malformed == MalformedExponentDigits.selector || lit.malformed == MalformedDecimalPoint.selector) {
            (bool baseOk, bytes memory baseRet) = address(this).staticcall(baseCall);
            assertTrue(baseOk, "base success");
            (bytes4 e,,, uint256 cursor,,) = abi.decode(baseRet, (bytes4, Float, bytes4, uint256, int256, int256));
            if ((e == ParseDecimalPrecisionLoss.selector || e == ParseDecimalOverflow.selector) && cursor < lit.cursor)
            {
                assertEq(baseRet, abi.encode(e, Float.wrap(0), e, cursor, int256(0), int256(0)), "base value error");
                (bool prOk, bytes memory prRet) = address(this).staticcall(prCall);
                assertTrue(prOk, "pr success");
                assertEq(
                    prRet,
                    abi.encode(lit.malformed, Float.wrap(0), lit.malformed, lit.cursor, int256(0), int256(0)),
                    "pr malformed"
                );
                return;
            }
        }
        same(baseCall, prCall);
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
        // Truncating to int32 is the point: any exponent a Float can hold.
        // forge-lint: disable-next-line(unsafe-typecast)
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

    /// The string the library formats `c × 10^e` to parses the same. Past the
    /// cap on the canonical exponent, non-scientific mode reverts and the
    /// scientific string is parsed instead.
    function checkFormattedParse(uint256 kind, uint256 d, uint256 x, bool negative, int256 e, bool sci) internal {
        int256 c = kind % 2 == 0 ? ofDigits(d, x, negative) : withTrailingZeros(d, x, negative);
        Float f = LibDecimalFloat.packLossless(c, e);
        int256 canonical = LibExactFloat.canonicalExponent(c, e);
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        if (!sci && (canonical > cap || canonical < -cap)) {
            vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, canonical));
            this.prFormat(f, false);
            sci = true;
        }
        checkParse(LibFormatDecimalFloat.toDecimalString(f, sci));
    }

    /// Formatted floats parse the same, at every int32 exponent.
    function testParsePr321EquivalenceFormatted(uint256 kind, uint256 d, uint256 x, bool negative, int32 e, bool sci)
        external
    {
        checkFormattedParse(kind, d, x, negative, e, sci);
    }

    /// Non-scientific mode reverts past the exponent cap, which is most of
    /// int32, so this samples the exponents it formats.
    function testParsePr321EquivalenceFormattedInsideCap(uint256 kind, uint256 d, uint256 x, bool negative, int256 e)
        external
    {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        checkFormattedParse(kind, d, x, negative, bound(e, -cap, cap), false);
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
        // Below the int32 floor with trailing zeros to shed: exactly a Float.
        checkParse("10e-2147483649");
        checkParse("-10e-2147483649");
        checkParse("1000e-2147483651");
        checkParse("1.0e-2147483648");
        // Lifted by the full 67 digits of int224 headroom: exactly a Float.
        checkParse("1e2147483714");
        checkParse("-1e2147483714");
        // Coefficients past int224 that shed only zeros through the 1e5 and
        // 1e8 shortcuts: exactly a Float.
        checkParse("1000000000000000000000000000000000000000000000000000000000000000000000000");
        checkParse("-1230000000000000000000000000000000000000000000000000000000000000000000000");
        checkParse("1000000000000000000000000000000000000000000000000000000000000000000000000000");
    }

    /// floor(int256.max / 10) * 10 + 8 is int256.max + 1, then `e` without
    /// digits: the base stopped after `.8` at 78 with
    /// `ParseDecimalPrecisionLoss`; the literal is a malformed exponent,
    /// `MalformedExponentDigits` after the `e` at 79.
    function testParsePr321EquivalenceMalformedExponentAfterValueError() external view {
        string memory str = "5789604461865809771178549250434395392663499233282028201972879200395656481996.8e";
        bytes4 loss = ParseDecimalPrecisionLoss.selector;
        bytes4 malformed = MalformedExponentDigits.selector;
        (bool baseOk, bytes memory baseRet) = address(this).staticcall(abi.encodeCall(this.baseParse, (str)));
        assertTrue(baseOk, "base success");
        (bool prOk, bytes memory prRet) = address(this).staticcall(abi.encodeCall(this.prParse, (str)));
        assertTrue(prOk, "pr success");
        assertEq(baseRet, abi.encode(loss, Float.wrap(0), loss, uint256(78), int256(0), int256(0)));
        assertEq(prRet, abi.encode(malformed, Float.wrap(0), malformed, uint256(79), int256(0), int256(0)));
        checkParse(str);
    }

    /// 80 nines, past uint256, then `e` without digits: the base stopped
    /// after the integer digits at 80 with `ParseDecimalOverflow`; the
    /// literal is a malformed exponent, `MalformedExponentDigits` after the
    /// `e` at 81.
    function testParsePr321EquivalenceMalformedExponentAfterOverflow() external view {
        string memory str = "99999999999999999999999999999999999999999999999999999999999999999999999999999999e";
        bytes4 overflow = ParseDecimalOverflow.selector;
        bytes4 malformed = MalformedExponentDigits.selector;
        (bool baseOk, bytes memory baseRet) = address(this).staticcall(abi.encodeCall(this.baseParse, (str)));
        assertTrue(baseOk, "base success");
        (bool prOk, bytes memory prRet) = address(this).staticcall(abi.encodeCall(this.prParse, (str)));
        assertTrue(prOk, "pr success");
        assertEq(baseRet, abi.encode(overflow, Float.wrap(0), overflow, uint256(80), int256(0), int256(0)));
        assertEq(prRet, abi.encode(malformed, Float.wrap(0), malformed, uint256(81), int256(0), int256(0)));
        checkParse(str);
    }

    /// 80 nines, past uint256, then `.` without digits: the base stopped
    /// after the integer digits at 80 with `ParseDecimalOverflow`; the
    /// literal is a malformed decimal point, `MalformedDecimalPoint` after the
    /// `.` at 81.
    function testParsePr321EquivalenceMalformedDecimalPointAfterOverflow() external view {
        string memory str = "99999999999999999999999999999999999999999999999999999999999999999999999999999999.";
        bytes4 overflow = ParseDecimalOverflow.selector;
        bytes4 malformed = MalformedDecimalPoint.selector;
        (bool baseOk, bytes memory baseRet) = address(this).staticcall(abi.encodeCall(this.baseParse, (str)));
        assertTrue(baseOk, "base success");
        (bool prOk, bytes memory prRet) = address(this).staticcall(abi.encodeCall(this.prParse, (str)));
        assertTrue(prOk, "pr success");
        assertEq(baseRet, abi.encode(overflow, Float.wrap(0), overflow, uint256(80), int256(0), int256(0)));
        assertEq(prRet, abi.encode(malformed, Float.wrap(0), malformed, uint256(81), int256(0), int256(0)));
        checkParse(str);
    }

    /// Exponents at the int256 bounds, from the fraction and from an integer
    /// part past int256, and exponent digits past int256.
    function testParsePr321EquivalenceExponentBounds() external view {
        string memory min = vm.toString(type(int256).min);
        string memory max = vm.toString(type(int256).max);
        string memory past = string.concat("1", vm.toString(type(uint256).max), "0");
        checkParse(string.concat("1.5e", min));
        checkParse(string.concat("1.50000e", min));
        checkParse(string.concat("1e", min));
        checkParse(string.concat("1.5e", max));
        checkParse(string.concat("1e", max));
        checkParse(
            string.concat("100000000000000000000000000000000000000000000000000000000000000000000000000000000e", max)
        );
        checkParse(
            string.concat("100000000000000000000000000000000000000000000000000000000000000000000000000000000.000e", max)
        );
        checkParse(
            string.concat("100000000000000000000000000000000000000000000000000000000000000000000000000000000.0010")
        );
        checkParse(string.concat("0.0e", past));
        checkParse(string.concat("1.0e", past));
        checkParse(past);
    }

    /// `checkParse` skips literals that are no Float, so this pins the copy's
    /// own lossy and overflow paths as its NatSpec states them: a literal
    /// that is not exactly a Float is `ParseDecimalPrecisionLoss` with a zero
    /// Float, and one past every Float reverts `ExponentOverflow` from packing.
    function testParsePr321BaseNonFloatLiterals() external {
        string[5] memory lossy = [
            "13479973333575319897333507543509815336818572211270286240551805124608",
            "13479973333575319897333507543509815336818572211270286240551805124608e2147483647",
            "1e-2147483649",
            "11e-2147483649",
            "1e-2147483716"
        ];
        for (uint256 i = 0; i < lossy.length; i++) {
            (bytes4 errorSelector, Float parsed) = this.parseFrozen(lossy[i]);
            assertEq(errorSelector, ParseDecimalPrecisionLoss.selector, lossy[i]);
            assertEq(Float.unwrap(parsed), bytes32(0), lossy[i]);
        }
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(2), int256(2147483714)));
        this.parseFrozen("2e2147483714");
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(-2), int256(2147483714)));
        this.parseFrozen("-2e2147483714");
    }

    /// 2^223 is one past int224.max, so the frozen packer's nearest-bound
    /// path reports precision loss at a representable exponent and at the
    /// ceiling, where the bound exponent is still int32.max.
    function testFrozenNearestBoundErrors() external pure {
        string memory digits = Strings.toString(uint256(1) << 223);
        string[2] memory texts = [digits, string.concat(digits, "e2147483647")];
        for (uint256 i = 0; i < texts.length; i++) {
            (bytes4 error, Float result) = LibParseDecimalFloatPr321.parseDecimalFloat(texts[i]);
            assertEq(error, ParseDecimalPrecisionLoss.selector);
            assertEq(Float.unwrap(result), bytes32(0));
        }
    }

    /// 2^223 at int32.max + 1: one shed puts the nearest bound at
    /// int32.max + 1 too, so the copy skips it and the lift reverts, as a shed
    /// coefficient has no headroom.
    function testFrozenNearestBoundPastCeiling() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1) << 223, int256(2147483648)));
        this.parseFrozen(string.concat(Strings.toString(uint256(1) << 223), "e2147483648"));
    }

    /// Below the int32 floor the frozen packer sheds exactly the shortfall in
    /// digits, for one, seven and 67 digits, and an underflow to zero is loss.
    /// Expected bits follow the Float representation, not the live packer.
    function testFrozenFloorPacking() external pure {
        string[4] memory texts = [
            "10e-2147483649",
            "100e-2147483649",
            "10000000e-2147483655",
            string.concat(Strings.toString(10 ** 67), "e-2147483715")
        ];
        uint256[4] memory coefficients = [uint256(1), 10, 1, 1];
        // The exponent's two's complement bits, as the top 32 bits of a Float.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 floorExponent = uint256(uint32(type(int32).min)) << 224;
        for (uint256 i = 0; i < texts.length; i++) {
            (bytes4 error, Float result) = LibParseDecimalFloatPr321.parseDecimalFloat(texts[i]);
            assertEq(error, bytes4(0));
            assertEq(Float.unwrap(result), bytes32(coefficients[i] | floorExponent));
        }
        (bytes4 underflowError, Float underflowResult) = LibParseDecimalFloatPr321.parseDecimalFloat("1e-2147483649");
        assertEq(underflowError, ParseDecimalPrecisionLoss.selector);
        assertEq(Float.unwrap(underflowResult), bytes32(0));
    }

    /// One past the ceiling, lifting by ten: `int224.max / 10 + 1` of either
    /// sign overflows int224 and reverts with the original inputs, while one
    /// less lifts exactly to int32.max.
    function testFrozenCeilingHeadroom() external {
        int256 firstOverflow = int256(type(int224).max) / 10 + 1;
        int256 exponent = int256(type(int32).max) + 1;
        for (uint256 i = 0; i < 2; i++) {
            int256 coefficient = i == 0 ? firstOverflow : -firstOverflow;
            string memory text = string.concat(Strings.toStringSigned(coefficient), "e2147483648");
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, coefficient, exponent));
            this.parseFrozen(text);
            coefficient = i == 0 ? firstOverflow - 1 : -(firstOverflow - 1);
            text = string.concat(Strings.toStringSigned(coefficient), "e2147483648");
            (bytes4 error, Float result) = LibParseDecimalFloatPr321.parseDecimalFloat(text);
            assertEq(error, bytes4(0));
            // The lifted coefficient's two's complement bits, masked to the
            // low 224 as a Float packs a negative coefficient.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 packedCoefficient = uint256(coefficient * 10) & uint256(type(uint224).max);
            uint256 packedExponent = uint256(uint32(type(int32).max)) << 224;
            assertEq(Float.unwrap(result), bytes32(packedCoefficient | packedExponent));
        }
    }

    /// The copied `maximize` against the digit-at-a-time exact reference, at
    /// zero, at 1e74 where its fast steps stop and the loop starts, at both
    /// signs of the `int256.max / 10` threshold, and at the int256 exponent
    /// floor where the shift wraps into a shortfall.
    function testFrozenMaximizeOracle() external pure {
        int256 tenLimit = type(int256).max / 10;
        int256[9] memory coefficients =
            [int256(0), 1, -1, 1e74, -1e74, tenLimit, tenLimit + 1, -tenLimit, -tenLimit - 1];
        int256[2] memory exponents = [int256(0), type(int256).min];
        for (uint256 i = 0; i < coefficients.length; i++) {
            for (uint256 j = 0; j < exponents.length; j++) {
                (int256 expectedCoefficient, int256 expectedExponent, int256 expectedShortfall) =
                    LibExactFloat.maximize(coefficients[i], exponents[j]);
                (int256 coefficient, int256 exponent, int256 shortfall) =
                    LibFormatDecimalFloatPr321.maximize(coefficients[i], exponents[j]);
                assertEq(coefficient, expectedCoefficient);
                assertEq(exponent, expectedExponent);
                assertEq(shortfall, expectedShortfall);
            }
        }
    }
}
