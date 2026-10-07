// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {LibBytes, Pointer} from "rain-solmem-0.1.28/src/lib/LibBytes.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {ParseEmptyDecimalString, ParseDecimalOverflow} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {
    MalformedExponentDigits,
    ParseDecimalPrecisionLoss,
    MalformedDecimalPoint,
    ParseDecimalFloatExcessCharacters
} from "src/error/ErrParse.sol";
import {ExponentOverflow, CoefficientOverflow} from "src/error/ErrDecimalFloat.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibParseDecimalFloatTest is Test {
    using LibBytes for bytes;
    using Strings for uint256;
    using LibDecimalFloat for Float;

    function parseDecimalFloatInlineExternal(string memory data)
        external
        pure
        returns (bytes4 errorSelector, uint256 cursorAfter, int256 signedCoefficient, int256 exponent)
    {
        uint256 cursor = Pointer.unwrap(bytes(data).dataPointer());
        uint256 start = cursor;
        (errorSelector, cursorAfter, signedCoefficient, exponent) =
            LibParseDecimalFloat.parseDecimalFloatInline(cursor, Pointer.unwrap(bytes(data).endDataPointer()));
        // Pragmatically the length of the inline movement is more useful than
        // the raw cursor because the external function has different memory
        // positions than the caller.
        cursorAfter -= start;
    }

    function parseDecimalFloatExternal(string memory data) external pure returns (bytes4 errorSelector, Float float) {
        (errorSelector, float) = LibParseDecimalFloat.parseDecimalFloat(data);
    }

    /// A return and a revert are tagged apart, so equal outcomes are equal bytes.
    function parseOutcome(string memory s) internal view returns (bytes memory) {
        try this.parseDecimalFloatExternal(s) returns (bytes4 err, Float float) {
            return abi.encode("return", err, float);
        } catch (bytes memory revertData) {
            return abi.encode("revert", revertData);
        }
    }

    /// The wrapper's outcome for `data`, tagged as `parseOutcome` tags it, from
    /// the inline parse with overflow decided by the exact oracle.
    function expectedParseOutcome(string memory data) internal view returns (bytes memory) {
        // The inline parse reports every malformed input as a selector. Its only
        // revert is a zero start pointer, which no memory string has.
        (bytes4 errorSelector, uint256 cursorMove, int256 signedCoefficient, int256 exponent) =
            this.parseDecimalFloatInlineExternal(data);
        // Inline parsing doesn't treat a partially consumed string as an
        // error, but the external parsing does, so we have to special case
        // that check.
        if (errorSelector != bytes4(0)) {
            return abi.encode("return", errorSelector, Float.wrap(0));
        } else if (cursorMove != bytes(data).length) {
            return abi.encode("return", ParseDecimalFloatExcessCharacters.selector, Float.wrap(0));
        } else if (
            signedCoefficient != 0
                && LibTestExactDecimal.overflows(
                    LibTestExactDecimal.u512(LibTestExactDecimal.abs(signedCoefficient)),
                    exponent,
                    signedCoefficient < 0
                )
        ) {
            // The parsed value is beyond the largest Float of its sign.
            return abi.encode("revert", abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
        }
        (Float packed, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        if (!lossless) {
            return abi.encode("return", ParseDecimalPrecisionLoss.selector, Float.wrap(0));
        }
        // A lossless pack may still have shed trailing zeros, to fit the
        // coefficient in int224 or to lift the exponent to int32.min, so the
        // representation can differ from the inline parse. The VALUE cannot.
        (int256 packedCoefficient, int256 packedExponent) = packed.unpack();
        assertTrue(
            LibDecimalFloatImplementation.eq(signedCoefficient, exponent, packedCoefficient, packedExponent),
            "lossless pack changed the value"
        );
        return abi.encode("return", bytes4(0), packed);
    }

    /// Check that the packed version matches the inline version.
    function testParsePacked(string memory data) external view {
        assertEq(parseOutcome(data), expectedParseOutcome(data), "parse outcome");
    }

    function checkParseDecimalFloat(
        string memory data,
        int256 expectedSignedCoefficient,
        int256 expectedExponent,
        uint256 expectedCursorAfter
    ) internal pure {
        uint256 cursor = Pointer.unwrap(bytes(data).dataPointer());
        (bytes4 errorSelector, uint256 cursorAfter, int256 signedCoefficient, int256 exponent) =
            LibParseDecimalFloat.parseDecimalFloatInline(cursor, Pointer.unwrap(bytes(data).endDataPointer()));
        assertEq(errorSelector, bytes4(0));
        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
        assertEq(cursorAfter - cursor, expectedCursorAfter);
    }

    function checkParseDecimalFloatFail(string memory data, bytes4 expectedErrorSelector, uint256 expectedCursorAfter)
        internal
        pure
    {
        uint256 cursor = Pointer.unwrap(bytes(data).dataPointer());
        (bytes4 errorSelector, uint256 cursorAfter,,) =
            LibParseDecimalFloat.parseDecimalFloatInline(cursor, Pointer.unwrap(bytes(data).endDataPointer()));
        assertEq(errorSelector, expectedErrorSelector);
        assertEq(cursorAfter - cursor, expectedCursorAfter);
    }

    /// Fuzz and round trip.
    function testParseLiteralDecimalFloatFuzz(uint256 value, uint8 leadingZerosCount, bool isNeg) external pure {
        value = bound(value, 0, uint256(type(int256).max) + (isNeg ? 1 : 0));
        string memory str = value.toString();

        string memory leadingZeros = new string(leadingZerosCount);
        for (uint8 i = 0; i < leadingZerosCount; i++) {
            bytes(leadingZeros)[i] = "0";
        }

        string memory input = string(abi.encodePacked((isNeg ? "-" : ""), leadingZeros, str));

        checkParseDecimalFloat(
            input,
            // value is bound to the int256 range so won't truncate when cast.
            // forge-lint: disable-next-line(unsafe-typecast)
            isNeg ? (value == (uint256(type(int256).max) + 1) ? type(int256).min : -int256(value)) : int256(value),
            0,
            bytes(input).length
        );
    }

    /// Check some specific examples.
    function testParseLiteralDecimalFloatSpecific() external pure {
        checkParseDecimalFloat("0", 0, 0, 1);
        checkParseDecimalFloat("1", 1, 0, 1);
        checkParseDecimalFloat("10", 10, 0, 2);
        checkParseDecimalFloat("100", 100, 0, 3);
        checkParseDecimalFloat("1000", 1000, 0, 4);
        checkParseDecimalFloat("2", 2, 0, 1);
    }

    /// Check some specific examples with leading zeros.
    function testParseLiteralDecimalFloatLeadingZeros() external pure {
        checkParseDecimalFloat("0000", 0, 0, 4);
        checkParseDecimalFloat("0001", 1, 0, 4);
        checkParseDecimalFloat("0010", 10, 0, 4);
        checkParseDecimalFloat("0100", 100, 0, 4);
        checkParseDecimalFloat("1000", 1000, 0, 4);
        checkParseDecimalFloat("0002", 2, 0, 4);
        checkParseDecimalFloat(
            "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            1,
            0,
            128
        );
    }

    /// Check some examples of decimals.
    function testParseLiteralDecimalFloatDecimals() external pure {
        checkParseDecimalFloat("0.1", 1, -1, 3);
        checkParseDecimalFloat("0.01", 1, -2, 4);
        checkParseDecimalFloat("0.001", 1, -3, 5);
        checkParseDecimalFloat("0.0001", 1, -4, 6);
        checkParseDecimalFloat("0.00001", 1, -5, 7);
        checkParseDecimalFloat("0.000001", 1, -6, 8);
        checkParseDecimalFloat("0.0000001", 1, -7, 9);
        checkParseDecimalFloat("0.00000001", 1, -8, 10);
        checkParseDecimalFloat("0.000000001", 1, -9, 11);
        checkParseDecimalFloat("0.0000000001", 1, -10, 12);
        checkParseDecimalFloat("0.00000000001", 1, -11, 13);
        checkParseDecimalFloat("0.000000000001", 1, -12, 14);
        checkParseDecimalFloat("0.0000000000001", 1, -13, 15);
        checkParseDecimalFloat("0.00000000000001", 1, -14, 16);
        checkParseDecimalFloat("0.000000000000001", 1, -15, 17);
        checkParseDecimalFloat("0.0000000000000001", 1, -16, 18);
        checkParseDecimalFloat("0.00000000000000001", 1, -17, 19);
        checkParseDecimalFloat("0.000000000000000001", 1, -18, 20);
        checkParseDecimalFloat("0.0000000000000000001", 1, -19, 21);
        checkParseDecimalFloat("0.00000000000000000001", 1, -20, 22);
        checkParseDecimalFloat("0.000000000000000000001", 1, -21, 23);
        checkParseDecimalFloat("0.0000000000000000000001", 1, -22, 24);
        checkParseDecimalFloat(
            "0.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            1,
            -127,
            129
        );
        checkParseDecimalFloat(
            "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            1,
            -127,
            254
        );

        checkParseDecimalFloat("1.1", 11, -1, 3);
        checkParseDecimalFloat("1.01", 101, -2, 4);
        checkParseDecimalFloat("1.001", 1001, -3, 5);
        checkParseDecimalFloat("1.0001", 10001, -4, 6);
        checkParseDecimalFloat("1.0001", 10001, -4, 6);

        checkParseDecimalFloat("10.1", 101, -1, 4);
        checkParseDecimalFloat("10.01", 1001, -2, 5);
        checkParseDecimalFloat("10.001", 10001, -3, 6);
        checkParseDecimalFloat("10.0001", 100001, -4, 7);

        checkParseDecimalFloat("100.1", 1001, -1, 5);
        checkParseDecimalFloat("100.01", 10001, -2, 6);
        // some trailing zeros
        checkParseDecimalFloat("100.001000", 100001, -3, 10);
        checkParseDecimalFloat(
            "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100.0001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            1000001,
            -4,
            260
        );
    }

    /// Check some examples of exponents.
    function testParseLiteralDecimalFloatExponents() external pure {
        checkParseDecimalFloat("0e0", 0, 0, 3);
        // A capital E.
        checkParseDecimalFloat("0E0", 0, 0, 3);
        checkParseDecimalFloat("0e1", 0, 0, 3);
        checkParseDecimalFloat("0e2", 0, 0, 3);
        checkParseDecimalFloat("0e-1", 0, 0, 4);
        checkParseDecimalFloat("0e-2", 0, 0, 4);

        checkParseDecimalFloat("1e1", 1, 1, 3);
        checkParseDecimalFloat("1e2", 1, 2, 3);
        checkParseDecimalFloat("1e3", 1, 3, 3);
        checkParseDecimalFloat("1e4", 1, 4, 3);
        checkParseDecimalFloat("1e5", 1, 5, 3);
        checkParseDecimalFloat("1e6", 1, 6, 3);
        checkParseDecimalFloat("1e7", 1, 7, 3);
        checkParseDecimalFloat("1e8", 1, 8, 3);
        checkParseDecimalFloat("1e9", 1, 9, 3);
        checkParseDecimalFloat("1e10", 1, 10, 4);
        checkParseDecimalFloat("1e11", 1, 11, 4);
        checkParseDecimalFloat("1e12", 1, 12, 4);
        checkParseDecimalFloat("1e13", 1, 13, 4);
        checkParseDecimalFloat("1e14", 1, 14, 4);
        checkParseDecimalFloat("1e15", 1, 15, 4);
        checkParseDecimalFloat("1e16", 1, 16, 4);
        checkParseDecimalFloat("1e17", 1, 17, 4);
        checkParseDecimalFloat("1e18", 1, 18, 4);
        checkParseDecimalFloat("1e19", 1, 19, 4);
        checkParseDecimalFloat("1e20", 1, 20, 4);
        checkParseDecimalFloat("1e21", 1, 21, 4);
        checkParseDecimalFloat("1e22", 1, 22, 4);
        checkParseDecimalFloat("1e23", 1, 23, 4);
        checkParseDecimalFloat("1e24", 1, 24, 4);
        checkParseDecimalFloat("1e25", 1, 25, 4);
        checkParseDecimalFloat("1e26", 1, 26, 4);
        checkParseDecimalFloat("1e260", 1, 260, 5);

        checkParseDecimalFloat("1e0", 1, 0, 3);
        // A capital E.
        checkParseDecimalFloat("1E0", 1, 0, 3);
        checkParseDecimalFloat("1e-0", 1, 0, 4);
        // A capital E.
        checkParseDecimalFloat("1E-0", 1, 0, 4);

        checkParseDecimalFloat("1e-1", 1, -1, 4);
        checkParseDecimalFloat("1e-2", 1, -2, 4);
        checkParseDecimalFloat("1e-3", 1, -3, 4);
        checkParseDecimalFloat("1e-4", 1, -4, 4);
        checkParseDecimalFloat("1e-5", 1, -5, 4);
        checkParseDecimalFloat("1e-6", 1, -6, 4);
        checkParseDecimalFloat("1e-7", 1, -7, 4);
        checkParseDecimalFloat("1e-8", 1, -8, 4);

        checkParseDecimalFloat("1e-9912873918273981273918273918739182", 1, -9912873918273981273918273918739182, 37);
        checkParseDecimalFloat("1e9912873918273981273918273918739182", 1, 9912873918273981273918273918739182, 36);
        checkParseDecimalFloat(
            "1e57896044618658097711785492504343953926634992332820282019728792003956564819967", 1, type(int256).max, 79
        );
        checkParseDecimalFloat(
            "57896044618658097711785492504343953926634992332820282019728792003956564819967e57896044618658097711785492504343953926634992332820282019728792003956564819967",
            type(int256).max,
            type(int256).max,
            155
        );
        checkParseDecimalFloat(
            "1e-57896044618658097711785492504343953926634992332820282019728792003956564819968", 1, type(int256).min, 80
        );
        checkParseDecimalFloat(
            "-57896044618658097711785492504343953926634992332820282019728792003956564819968e-57896044618658097711785492504343953926634992332820282019728792003956564819968",
            type(int256).min,
            type(int256).min,
            157
        );

        checkParseDecimalFloat("0.0e0", 0, 0, 5);
        checkParseDecimalFloat("0.0e1", 0, 0, 5);
        checkParseDecimalFloat("1.1e1", 11, 0, 5);
        checkParseDecimalFloat("1.1e-1", 11, -2, 6);

        // Some negatives.
        checkParseDecimalFloat("-1.1e-1", -11, -2, 7);
        checkParseDecimalFloat("-10.01e-1", -1001, -3, 9);
        checkParseDecimalFloat("-0.1", -1, -1, 4);
    }

    /// Test some unrelated data after the decimal.
    function testParseLiteralDecimalFloatUnrelated() external pure {
        checkParseDecimalFloat("0.0hello", 0, 0, 3);
        checkParseDecimalFloat("0.0e0hello", 0, 0, 5);
        checkParseDecimalFloat("0.0e1hello", 0, 0, 5);
        checkParseDecimalFloat("1.1e1hello", 11, 0, 5);
        checkParseDecimalFloat("1.1e-1hello", 11, -2, 6);
        checkParseDecimalFloat("-1.1e-1hello", -11, -2, 7);
        checkParseDecimalFloat("1.2.3", 12, -1, 3);
        checkParseDecimalFloat("1.2.3e4", 12, -1, 3);
        checkParseDecimalFloat("-1.2.3", -12, -1, 4);
        checkParseDecimalFloat("1.2e3.4", 12, 2, 5);
    }

    /// issue found in fuzzing round trip with formatter 1.
    function testParseFormatterRoundTripBug0() external pure {
        checkParseDecimalFloat(
            "1.3479973333575319897333507543509815336818572211270286240551805124605e49",
            13479973333575319897333507543509815336818572211270286240551805124605,
            -18,
            72
        );
    }

    /// An empty string should fail.
    function testParseDecimalFloatEmpty() external pure {
        checkParseDecimalFloatFail("", ParseEmptyDecimalString.selector, 0);
    }

    /// A non decimal string should revert.
    function testParseDecimalFloatNonDecimal() external pure {
        checkParseDecimalFloatFail("hello", ParseEmptyDecimalString.selector, 0);
    }

    /// e without a number should revert.
    function testParseDecimalFloatExponentRevert() external pure {
        checkParseDecimalFloatFail("e", ParseEmptyDecimalString.selector, 0);
    }

    /// e with a left digit but not right should revert.
    function testParseDecimalFloatExponentRevert2() external pure {
        checkParseDecimalFloatFail("1e", MalformedExponentDigits.selector, 2);
    }

    /// e with a left digit but not right should revert. Add a negative sign.
    function testParseDecimalFloatExponentRevert3() external pure {
        checkParseDecimalFloatFail("1e-", MalformedExponentDigits.selector, 3);
    }

    /// e with a right digit but not left should revert.
    function testParseDecimalFloatExponentRevert4() external pure {
        checkParseDecimalFloatFail("e1", ParseEmptyDecimalString.selector, 0);
    }

    /// e with a right digit but not left should revert.
    /// two digits.
    function testParseLiteralDecimalFloatExponentRevert5() external pure {
        checkParseDecimalFloatFail("e10", ParseEmptyDecimalString.selector, 0);
    }

    /// e with a right digit but not left should revert.
    /// two digits with negative sign.
    function testParseLiteralDecimalFloatExponentRevert6() external pure {
        checkParseDecimalFloatFail("e-10", ParseEmptyDecimalString.selector, 0);
    }

    /// Dot without digits should revert.
    function testParseLiteralDecimalFloatDotRevert() external pure {
        checkParseDecimalFloatFail(".", ParseEmptyDecimalString.selector, 0);
    }

    /// Dot without leading digits should revert.
    function testParseLiteralDecimalFloatDotRevert2() external pure {
        checkParseDecimalFloatFail(".1", ParseEmptyDecimalString.selector, 0);
    }

    /// Dot without trailing digits should revert.
    function testParseLiteralDecimalFloatDotRevert3() external pure {
        checkParseDecimalFloatFail("1.", MalformedDecimalPoint.selector, 2);
    }

    /// Dot e is an error.
    function testParseLiteralDecimalFloatDotE() external pure {
        checkParseDecimalFloatFail(".e", ParseEmptyDecimalString.selector, 0);
    }

    /// Dot e0 is an error.
    function testParseLiteralDecimalFloatDotE0() external pure {
        checkParseDecimalFloatFail(".e0", ParseEmptyDecimalString.selector, 0);
    }

    /// e dot is an error.
    function testParseLiteralDecimalFloatEDot() external pure {
        checkParseDecimalFloatFail("e.", ParseEmptyDecimalString.selector, 0);
    }

    /// Explicit positive exponent sign is accepted and equivalent to no sign.
    function testParseLiteralDecimalFloatPositiveExponentSign() external pure {
        checkParseDecimalFloat("1e+2", 1, 2, 4);
        checkParseDecimalFloat("1.0e+2", 1, 2, 6);
        checkParseDecimalFloat("1E+2", 1, 2, 4);
        checkParseDecimalFloat("0e+0", 0, 0, 4);
        checkParseDecimalFloat("0e+1", 0, 0, 4);
        checkParseDecimalFloat("1e+0", 1, 0, 4);
        checkParseDecimalFloat("1e+260", 1, 260, 6);
        checkParseDecimalFloat("-1e+2", -1, 2, 5);
        checkParseDecimalFloat("1.1e+1", 11, 0, 6);
    }

    /// Positive sign with no digits is still an error.
    function testParseLiteralDecimalFloatPositiveENoDigits() external pure {
        checkParseDecimalFloatFail("1e+", MalformedExponentDigits.selector, 3);
        checkParseDecimalFloatFail("0.0e+", MalformedExponentDigits.selector, 5);
    }

    /// An exponent takes one sign. A `+` after a `-` must not be skipped, or
    /// `1e-+2` parses as `1e2` with the `-` silently dropped.
    function testParseLiteralDecimalFloatExponentSignAfterNegativeSign() external pure {
        checkParseDecimalFloatFail("1e-+2", MalformedExponentDigits.selector, 3);
    }

    function testParseLiteralDecimalFloatExponentNegativeSignAfterPositiveSign() external pure {
        checkParseDecimalFloatFail("1e+-2", MalformedExponentDigits.selector, 3);
    }

    /// A coefficient takes at most one `-`.
    function testParseLiteralDecimalFloatRepeatedNegativeSign() external pure {
        checkParseDecimalFloatFail("--5", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail("---5", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail("--5.5e2", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail("-.5", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail("-", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloat("-5", -5, 0, 2);
    }

    /// An exponent takes at most one `-`.
    function testParseLiteralDecimalFloatRepeatedExponentNegativeSign() external pure {
        checkParseDecimalFloatFail("1e--2", MalformedExponentDigits.selector, 3);
        checkParseDecimalFloatFail("1e---2", MalformedExponentDigits.selector, 3);
        checkParseDecimalFloatFail("1.5e--2", MalformedExponentDigits.selector, 5);
        checkParseDecimalFloat("1e-2", 1, -2, 4);
    }

    /// Repeated signs are rejected for any digits that follow them.
    function testParseLiteralDecimalFloatRepeatedNegativeSignFuzz(uint256 value, uint8 extra) external pure {
        string memory digits = value.toString();
        bytes memory dashes = new bytes(uint256(extra) + 2);
        for (uint256 i = 0; i < dashes.length; i++) {
            dashes[i] = "-";
        }
        checkParseDecimalFloatFail(string(abi.encodePacked(dashes, digits)), ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail(string(abi.encodePacked("1e", dashes, digits)), MalformedExponentDigits.selector, 3);
    }

    /// Negative e with no digits is an error.
    function testParseLiteralDecimalFloatNegativeE() external pure {
        checkParseDecimalFloatFail("0.0e-", MalformedExponentDigits.selector, 5);
    }

    /// Negative frac is an error.
    function testParseLiteralDecimalFloatNegativeFrac() external pure {
        checkParseDecimalFloatFail("0.-1", MalformedDecimalPoint.selector, 2);
    }

    /// Exponent overflow when fractional exponent + e-notation exponent wraps.
    /// (A10-1/p1)
    function testParseExponentOverflowFracPlusEValue() external pure {
        // exponent = -1 (from ".1") + int256.min (from e-notation) wraps.
        // "0.1e-" = 5 chars + 77 digits = 82
        checkParseDecimalFloatFail(
            "0.1e-57896044618658097711785492504343953926634992332820282019728792003956564819968",
            ExponentOverflow.selector,
            82
        );
        // exponent = -1 (from ".1") + int256.max (from e-notation) does NOT
        // overflow — it's a valid large positive exponent.
        // "0.1e" = 4 chars + 77 digits = 81
        checkParseDecimalFloat(
            "0.1e57896044618658097711785492504343953926634992332820282019728792003956564819967",
            1,
            type(int256).max - 1,
            81
        );
    }

    /// ParseDecimalPrecisionLoss from the wrapper when packLossy returns
    /// lossless=false. The inline parse succeeds but the coefficient exceeds
    /// int224, so packLossy normalizes it lossily. (A10-8)
    function testParseDecimalFloatPrecisionLossFromPackLossy() external view {
        // 68 nines exceeds int224.max (~1.35e67) so packLossy must divide
        // by 10 to fit, returning lossless=false.
        (bytes4 err,) =
            this.parseDecimalFloatExternal("99999999999999999999999999999999999999999999999999999999999999999999");
        assertEq(err, ParseDecimalPrecisionLoss.selector);
    }

    /// Exponent exceeds int32 range — packLossy reverts with ExponentOverflow
    /// for positive exponents the coefficient cannot lift, returns soft error
    /// for negative. (A10-8)
    function testParseDecimalFloatExponentOverflowFromPackLossy() external {
        // Issue #285: 1e2147483648 is 10e2147483647, which is representable.
        (bytes4 liftedErr, Float lifted) = this.parseDecimalFloatExternal("1e2147483648");
        assertEq(liftedErr, bytes4(0));
        (int256 liftedCoefficient, int256 liftedExponent) = lifted.unpack();
        assertEq(liftedCoefficient, 10);
        assertEq(liftedExponent, int256(type(int32).max));

        // Past int224 headroom, positive exponent overflow reverts.
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), int256(2147483715)));
        this.parseDecimalFloatExternal("1e2147483715");

        // Negative exponent overflow is a very small number that rounds to
        // zero in packLossy, so the wrapper returns ParseDecimalPrecisionLoss
        // rather than reverting.
        (bytes4 err,) = this.parseDecimalFloatExternal("1e-2147483649");
        assertEq(err, ParseDecimalPrecisionLoss.selector);
    }

    /// A literal below the exponent floor whose coefficient carries the
    /// trailing zeros to reach it is a representable value, and parses as
    /// one: `10e-2147483649` is `1e-2147483648`. Only a literal that genuinely
    /// rounds to zero (above) is a precision loss.
    function testParseDecimalFloatBelowFloorWithTrailingZerosParses() external view {
        (bytes4 err, Float float) = this.parseDecimalFloatExternal("10e-2147483649");
        assertEq(err, bytes4(0));
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        assertEq(signedCoefficient, 1);
        assertEq(exponent, int256(type(int32).min));
    }

    /// ParseDecimalFloatExcessCharacters from the wrapper when trailing
    /// non-numeric characters remain after a valid parse. (A10-7)
    function testParseDecimalFloatExcessCharacters() external view {
        (bytes4 err,) = this.parseDecimalFloatExternal("1hello");
        assertEq(err, ParseDecimalFloatExcessCharacters.selector);

        (bytes4 err2,) = this.parseDecimalFloatExternal("1.2.3");
        assertEq(err2, ParseDecimalFloatExcessCharacters.selector);

        (bytes4 err3,) = this.parseDecimalFloatExternal("1e2e3");
        assertEq(err3, ParseDecimalFloatExcessCharacters.selector);
    }

    function zeros(uint256 n) internal pure returns (string memory z) {
        z = new string(n);
        for (uint256 i = 0; i < n; i++) {
            bytes(z)[i] = "0";
        }
    }

    function testParseZeroFractionSmall() external pure {
        checkParseDecimalFloat("1", 1, 0, 1);
        checkParseDecimalFloat("1.0", 1, 0, 3);
        checkParseDecimalFloat("1.000", 1, 0, 5);
        checkParseDecimalFloat("-12.0e-3", -12, -3, 8);
        checkParseDecimalFloat("-0.0", 0, 0, 4);
        checkParseDecimalFloat("0.000e5", 0, 0, 7);
    }

    /// Issue #327: an all-zero fraction is not rescaled into the integer part.
    /// `2` + 67 zeros is past int224, so the wrapper sheds one trailing zero.
    function testParseZeroFractionPastInt224() external view {
        string memory int67 = string.concat("2", zeros(67));
        int256 twoE67 = 2e67;
        string[3] memory fracs = ["", ".0", ".000"];
        for (uint256 i = 0; i < fracs.length; i++) {
            string memory s = string.concat(int67, fracs[i]);
            checkParseDecimalFloat(s, twoE67, 0, bytes(s).length);
            (bytes4 err, Float float) = this.parseDecimalFloatExternal(s);
            assertEq(err, bytes4(0));
            (int256 signedCoefficient, int256 exponent) = float.unpack();
            assertEq(signedCoefficient, 2e66);
            assertEq(exponent, 1);
        }
    }

    /// Issue #327: as above, negative and with an exponent after the fraction.
    function testParseZeroFractionPastInt224NegativeExponent() external view {
        string memory int67 = string.concat("-2", zeros(67));
        int256 negTwoE67 = -2e67;
        string[3] memory fracs = ["", ".0", ".000"];
        for (uint256 i = 0; i < fracs.length; i++) {
            string memory s = string.concat(int67, fracs[i], "e-5");
            checkParseDecimalFloat(s, negTwoE67, -5, bytes(s).length);
            (bytes4 err, Float float) = this.parseDecimalFloatExternal(s);
            assertEq(err, bytes4(0));
            (int256 signedCoefficient, int256 exponent) = float.unpack();
            assertEq(signedCoefficient, -2e66);
            assertEq(exponent, -4);
        }
    }

    /// Issue #327: 68 nines with a zero fraction and a huge exponent overflows
    /// the exponent exactly as it does without the fraction.
    function testParseZeroFractionNinesExponentOverflow() external view {
        string memory nines = "99999999999999999999999999999999999999999999999999999999999999999999";
        int256 ninesValue = 99999999999999999999999999999999999999999999999999999999999999999999;
        bytes memory overflow =
            abi.encode("revert", abi.encodeWithSelector(ExponentOverflow.selector, ninesValue, int256(2200000000)));
        string[3] memory fracs = ["", ".0", ".000"];
        for (uint256 i = 0; i < fracs.length; i++) {
            string memory s = string.concat(nines, fracs[i], "e2200000000");
            checkParseDecimalFloat(s, ninesValue, 2200000000, bytes(s).length);
            bytes memory expected = expectedParseOutcome(s);
            assertEq(expected, overflow, "oracle overflow");
            assertEq(parseOutcome(s), expected, "parse outcome");
        }
    }

    /// Issue #327: `s` and `s` + `.` + any number of zeros parse identically,
    /// inline and through the wrapper, for any integer part and exponent.
    function testParseZeroFractionEquivalentFuzz(
        uint256 value,
        uint8 digits,
        bool isNeg,
        uint8 leadingZeros,
        uint8 fracZeros,
        bool hasExponent,
        int256 e
    ) external view {
        // Up to 80 digits, so int224, int256 and past-int256 integer parts all
        // come up.
        digits = uint8(bound(digits, 1, 80));
        if (digits < 78) {
            value = bound(value, 0, 10 ** digits - 1);
        }
        fracZeros = uint8(bound(fracZeros, 1, 100));
        string memory intPart = string.concat(isNeg ? "-" : "", zeros(leadingZeros), value.toString());
        string memory exponentPart = hasExponent ? string.concat("e", Strings.toStringSigned(e)) : "";
        string memory bare = string.concat(intPart, exponentPart);
        string memory frac = string.concat(intPart, ".", zeros(fracZeros), exponentPart);

        (bytes4 bareErr, uint256 bareCursor, int256 bareCoefficient, int256 bareExponent) =
            this.parseDecimalFloatInlineExternal(bare);
        (bytes4 fracErr, uint256 fracCursor, int256 fracCoefficient, int256 fracExponent) =
            this.parseDecimalFloatInlineExternal(frac);
        assertEq(fracErr, bareErr, "inline error");
        assertEq(fracCoefficient, bareCoefficient, "inline coefficient");
        assertEq(fracExponent, bareExponent, "inline exponent");
        if (bareErr == bytes4(0)) {
            assertEq(bareCursor, bytes(bare).length, "bare cursor");
            assertEq(fracCursor, bytes(frac).length, "frac cursor");
        }

        bytes memory expected = expectedParseOutcome(bare);
        assertEq(parseOutcome(bare), expected, "bare outcome");
        assertEq(parseOutcome(frac), expected, "frac outcome");
    }

    /// Can't have more than max total precision. Add decimals after the max int.
    function testParseLiteralDecimalFloatPrecisionRevert0() external pure {
        checkParseDecimalFloatFail(
            "57896044618658097711785492504343953926634992332820282019728792003956564819967.1",
            ParseDecimalPrecisionLoss.selector,
            79
        );
    }

    /// Can't have more than max total precision. Have an int that makes it
    /// impossible to fit the max decimals.
    function testParseLiteralDecimalFloatPrecisionRevert1() external pure {
        checkParseDecimalFloatFail(
            "2.5789604461865809771178549250434395392663499233282028201972879200395",
            ParseDecimalPrecisionLoss.selector,
            69
        );
    }
}

contract LibParseDecimalFloatPastInt256Test is Test {
    using LibDecimalFloat for Float;
    using LibBytes for bytes;
    using Strings for uint256;

    string constant INT256_MAX = "57896044618658097711785492504343953926634992332820282019728792003956564819967";
    string constant INT256_MAX_PLUS_ONE =
        "57896044618658097711785492504343953926634992332820282019728792003956564819968";
    string constant INT256_MAX_PLUS_TWO =
        "57896044618658097711785492504343953926634992332820282019728792003956564819969";

    function zeros(uint256 n) internal pure returns (string memory z) {
        z = new string(n);
        for (uint256 i = 0; i < n; i++) {
            bytes(z)[i] = "0";
        }
    }

    function parseInline(string memory data)
        external
        pure
        returns (bytes4 errorSelector, uint256 cursorAfter, int256 signedCoefficient, int256 exponent)
    {
        uint256 start = Pointer.unwrap(bytes(data).dataPointer());
        (errorSelector, cursorAfter, signedCoefficient, exponent) =
            LibParseDecimalFloat.parseDecimalFloatInline(start, Pointer.unwrap(bytes(data).endDataPointer()));
        cursorAfter -= start;
    }

    function parse(string memory data) external pure returns (bytes4 errorSelector, Float float) {
        (errorSelector, float) = LibParseDecimalFloat.parseDecimalFloat(data);
    }

    /// The inline parse and the packed parse both give exactly `c`e`e`.
    function checkExact(string memory s, int256 c, int256 e, int256 packedC, int256 packedE) internal view {
        (bytes4 err, uint256 cursor, int256 inlineC, int256 inlineE) = this.parseInline(s);
        assertEq(err, bytes4(0), "inline error");
        assertEq(cursor, bytes(s).length, "cursor");
        assertEq(inlineC, c, "inline coefficient");
        assertEq(inlineE, e, "inline exponent");
        Float float;
        (err, float) = this.parse(s);
        assertEq(err, bytes4(0), "error");
        (int256 actualC, int256 actualE) = float.unpack();
        assertEq(actualC, packedC, "coefficient");
        assertEq(actualE, packedE, "exponent");
    }

    /// The inline parse gives `c`e`e`, which is no Float.
    function checkLoss(string memory s, int256 c, int256 e) internal view {
        (bytes4 err, uint256 cursor, int256 inlineC, int256 inlineE) = this.parseInline(s);
        assertEq(err, bytes4(0), "inline error");
        assertEq(cursor, bytes(s).length, "cursor");
        assertEq(inlineC, c, "inline coefficient");
        assertEq(inlineE, e, "inline exponent");
        Float float;
        (err, float) = this.parse(s);
        assertEq(err, ParseDecimalPrecisionLoss.selector, "error");
        assertEq(Float.unwrap(float), bytes32(0), "float");
    }

    function checkFail(string memory s, bytes4 selector, uint256 cursorAfter) internal view {
        (bytes4 err, uint256 cursor,,) = this.parseInline(s);
        assertEq(err, selector, "inline error");
        assertEq(cursor, cursorAfter, "cursor");
        Float float;
        (err, float) = this.parse(s);
        assertEq(err, selector, "error");
        assertEq(Float.unwrap(float), bytes32(0), "float");
    }

    /// Issue #341: 1e77 and 1e100 written out are Floats.
    function testParseIntegerPastInt256PowersOfTen() external view {
        checkExact(string.concat("1", zeros(77)), 1, 77, 1, 77);
        checkExact(string.concat("-1", zeros(77)), -1, 77, -1, 77);
        checkExact(string.concat("1", zeros(100)), 1, 100, 1, 100);
        checkExact(string.concat("-1", zeros(100)), -1, 100, -1, 100);
        checkExact(string.concat("000", "1", zeros(100)), 1, 100, 1, 100);
        checkExact(string.concat("-000", "3", zeros(100)), -3, 100, -3, 100);
        checkExact(string.concat("12345", zeros(200)), 12345, 200, 12345, 200);
    }

    /// The fallback starts exactly past int256: 5e76 fits it, 6e76 does not.
    function testParseIntegerPastInt256Boundary() external view {
        checkExact(string.concat("5", zeros(76)), 5e76, 0, 5e66, 10);
        checkExact(string.concat("6", zeros(76)), 6, 76, 6, 76);
        checkExact(string.concat("-6", zeros(76)), -6, 76, -6, 76);
        // int256.min fits int256, one past it does not.
        checkLoss(string.concat("-", INT256_MAX_PLUS_ONE), type(int256).min, 0);
        checkFail(string.concat("-", INT256_MAX_PLUS_TWO), ParseDecimalOverflow.selector, 78);
        checkLoss(INT256_MAX, type(int256).max, 0);
        checkFail(INT256_MAX_PLUS_ONE, ParseDecimalOverflow.selector, 77);
        // Trailing zeros do not help significant digits past int256.
        checkFail(string.concat(INT256_MAX_PLUS_ONE, "0"), ParseDecimalOverflow.selector, 78);
        // Significant digits within int256 but past int224 are no Float.
        checkLoss(string.concat(INT256_MAX, "0000"), type(int256).max, 4);
        checkLoss(string.concat("-", INT256_MAX_PLUS_ONE, "00"), type(int256).min, 2);
    }

    /// The int224 coefficient bounds followed by zeros are exact.
    function testParseIntegerPastInt256Int224Bounds() external view {
        int256 max = type(int224).max;
        int256 min = type(int224).min;
        checkExact(string.concat(Strings.toStringSigned(max), zeros(20)), max, 20, max, 20);
        checkExact(string.concat(Strings.toStringSigned(min), zeros(20)), min, 20, min, 20);
        checkExact(string.concat(Strings.toStringSigned(max), zeros(200)), max, 200, max, 200);
        // One past int224.max is no Float at any exponent.
        checkLoss(string.concat(Strings.toStringSigned(max + 1), zeros(20)), max + 1, 20);
    }

    /// The fraction after an integer part past int256.
    function testParseIntegerPastInt256Fraction() external view {
        string memory e77 = string.concat("1", zeros(77));
        checkExact(string.concat(e77, ".0"), 1, 77, 1, 77);
        checkExact(string.concat(e77, ".", zeros(100)), 1, 77, 1, 77);
        checkExact(string.concat(e77, ".000e-77"), 1, 0, 1, 0);
        checkFail(string.concat(e77, ".5"), ParseDecimalPrecisionLoss.selector, 80);
        checkFail(string.concat(e77, ".0001"), ParseDecimalPrecisionLoss.selector, 83);
        checkFail(string.concat(e77, ".1000"), ParseDecimalPrecisionLoss.selector, 83);
        checkFail(string.concat(e77, "."), MalformedDecimalPoint.selector, 79);
        checkFail(string.concat(e77, ".e1"), MalformedDecimalPoint.selector, 79);
        checkFail(string.concat(e77, ".-1"), MalformedDecimalPoint.selector, 79);
        // Significant digits past int256 report that before the fraction.
        checkFail(string.concat(INT256_MAX_PLUS_ONE, ".5"), ParseDecimalOverflow.selector, 77);
        // What follows is left to the caller.
        (bytes4 err, uint256 cursor, int256 c, int256 e) = this.parseInline(string.concat(e77, ".00x"));
        assertEq(err, bytes4(0));
        assertEq(cursor, 81);
        assertEq(c, 1);
        assertEq(e, 77);
        (err,) = this.parse(string.concat(e77, ".00x"));
        assertEq(err, ParseDecimalFloatExcessCharacters.selector);
    }

    /// The zeros moved into the exponent add to the written exponent.
    function testParseIntegerPastInt256Exponent() external view {
        string memory e80 = string.concat("1", zeros(80));
        checkExact(string.concat(e80, "e-80"), 1, 0, 1, 0);
        checkExact(string.concat(e80, "e2147483567"), 1, 2147483647, 1, type(int32).max);
        checkExact(string.concat(e80, "e-2147483728"), 1, -2147483648, 1, type(int32).min);
        checkExact(string.concat("-", e80, ".0E+3"), -1, 83, -1, 83);
        checkLoss(string.concat(e80, "e-2147483729"), 1, -2147483649);
    }

    /// Issue #341: zero takes an exponent of any size.
    function testParseZeroHugeExponent() external view {
        string[6] memory literals = [
            string.concat("0e", INT256_MAX_PLUS_ONE),
            string.concat("0e-", INT256_MAX_PLUS_TWO),
            string.concat("-0.000E+", INT256_MAX_PLUS_ONE, "000"),
            string.concat("000e", INT256_MAX_PLUS_ONE),
            string.concat("0.0e-", "9", zeros(200)),
            string.concat("0e", INT256_MAX)
        ];
        for (uint256 i = 0; i < literals.length; i++) {
            checkExact(literals[i], 0, 0, 0, 0);
        }
    }

    /// A nonzero coefficient with an exponent past int256 is no Float.
    function testParseNonZeroHugeExponent() external view {
        string memory s = string.concat("1e", INT256_MAX_PLUS_ONE);
        checkFail(s, ParseDecimalOverflow.selector, bytes(s).length);
        s = string.concat("-0.1e-", INT256_MAX_PLUS_TWO);
        checkFail(s, ParseDecimalOverflow.selector, bytes(s).length);
        s = string.concat("1", zeros(80), "e", INT256_MAX_PLUS_ONE);
        checkFail(s, ParseDecimalOverflow.selector, bytes(s).length);
    }

    /// Any int224 followed by any number of zeros parses to exactly its value.
    function testParseIntegerTrailingZerosFuzz(int224 c, uint8 z) external view {
        string memory s = string.concat(Strings.toStringSigned(c), zeros(z));
        (bytes4 err, Float float) = this.parse(s);
        assertEq(err, bytes4(0), "error");
        if (c == 0) {
            assertEq(Float.unwrap(float), bytes32(0), "zero");
        } else {
            assertTrue(float.eq(LibDecimalFloat.packLossless(c, int256(uint256(z)))), "value");
        }
    }
}
