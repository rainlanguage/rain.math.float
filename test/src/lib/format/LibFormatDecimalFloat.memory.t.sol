// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";

/// `toDecimalString` builds its string with assembly. It must leave memory
/// allocated before the call untouched, allocate the whole string, and leave
/// the string's last word zero past its length.
contract LibFormatDecimalFloatMemoryTest is Test {
    function repeat(bytes1 char, uint256 count) internal pure returns (bytes memory out) {
        out = new bytes(count);
        for (uint256 i = 0; i < count; i++) {
            out[i] = char;
        }
    }

    /// The sentinel is the last allocation before the call, so it ends at the
    /// free pointer the formatter starts from.
    function checkMemory(int256 c, int256 e, bool scientific, bytes memory expected) internal pure {
        Float f = LibDecimalFloat.packLossless(c, e);
        bytes32 expectedHash = keccak256(expected);

        bytes memory sentinel = repeat(0xaa, 0x100);
        bytes32 sentinelHash = keccak256(sentinel);

        string memory first = LibFormatDecimalFloat.toDecimalString(f, scientific);
        uint256 freePointer;
        uint256 end;
        bytes32 padding;
        assembly ("memory-safe") {
            freePointer := mload(0x40)
            let length := mload(first)
            end := add(add(first, 0x20), length)
            // The bytes past the length up to the next word boundary, none
            // when the length is a whole number of words.
            if and(length, 0x1f) { padding := shr(mul(8, and(length, 0x1f)), mload(end)) }
        }
        assertEq(keccak256(sentinel), sentinelHash, "memory before the call");
        assertEq(keccak256(bytes(first)), expectedHash, "result");
        assertEq(padding, bytes32(0), "padding");
        // #453: the allocation ends at the string's last word, no spare word.
        assertEq(freePointer, (end + 0x1f) / 0x20 * 0x20, "free pointer");

        // A second string is allocated after the first, not over it.
        string memory second = LibFormatDecimalFloat.toDecimalString(f, scientific);
        assertEq(keccak256(bytes(first)), expectedHash, "first after second");
        assertEq(keccak256(bytes(second)), expectedHash, "second");
    }

    function testFormatMemoryScientific() external pure {
        int256 third = 3333333333333333333333333333333333333333333333333333333333333333333;
        checkMemory(-third, -67, true, bytes.concat("-3.", repeat("3", 66), "e-1"));
    }

    function testFormatMemoryNonScientificFraction() external pure {
        int256 third = 3333333333333333333333333333333333333333333333333333333333333333333;
        checkMemory(-third, -67, false, bytes.concat("-0.", repeat("3", 67)));
    }

    /// Lengths that end on a word boundary, where a spare word would lie
    /// wholly past the string.
    function testFormatMemoryWordAligned() external pure {
        checkMemory(12345678901234567890123456789012, 0, false, "12345678901234567890123456789012");
        checkMemory(1234567890123456789012345678901, -30, true, "1.234567890123456789012345678901");
        checkMemory(1, 63, false, bytes.concat("1", repeat("0", 63)));
        checkMemory(-123456789012345678901234567891, -29, true, "-1.23456789012345678901234567891");
    }

    function testFormatMemoryNonScientificInteger() external pure {
        checkMemory(type(int224).min, 0, false, "-13479973333575319897333507543509815336818572211270286240551805124608");
    }

    /// -15 × 10^2 = -1500. The zero fill writes whole words of `0` past the
    /// last zero, so the padding must be cleared after it.
    function testFormatMemoryNonScientificTrailingZeros() external pure {
        checkMemory(-15, 2, false, "-1500");
    }
}
