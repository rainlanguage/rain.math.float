// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {LibFormatDecimalFloatPr321} from "test/lib/LibFormatDecimalFloatPr321.sol";
import {LibParseDecimalFloatPr321} from "test/lib/LibParseDecimalFloatPr321.sol";

contract FormatParseGas {
    function formatBase(Float f, bool scientific) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        string memory r = LibFormatDecimalFloatPr321.toDecimalString(f, scientific);
        g = s - gasleft();
        h = keccak256(bytes(r));
    }

    function formatPr(Float f, bool scientific) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        string memory r = LibFormatDecimalFloat.toDecimalString(f, scientific);
        g = s - gasleft();
        h = keccak256(bytes(r));
    }

    function parseBase(string memory str) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        (bytes4 e, Float f) = LibParseDecimalFloatPr321.parseDecimalFloat(str);
        g = s - gasleft();
        h = keccak256(abi.encode(e, f));
    }

    function parsePr(string memory str) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        (bytes4 e, Float f) = LibParseDecimalFloat.parseDecimalFloat(str);
        g = s - gasleft();
        h = keccak256(abi.encode(e, f));
    }
}

/// Gas of `toDecimalString` and `parseDecimalFloat` against their copies from
/// before #310's format and parse changes, measured the same way: the library
/// call alone between two `gasleft()` reads. Every row asserts the same result
/// bytes and no more gas. Run with `forge test --mc
/// LibDecimalFloatFormatParseGasTest -vv`; each line is
/// `GAS|op|case|before|after|delta`.
contract LibDecimalFloatFormatParseGasTest is Test {
    FormatParseGas internal immutable B = new FormatParseGas();

    function row(string memory op, string memory label, uint256 baseGas, uint256 prGas) internal pure {
        console2.log(
            string.concat(
                "GAS|",
                op,
                "|",
                label,
                "|",
                vm.toString(baseGas),
                "|",
                vm.toString(prGas),
                "|",
                // Gas amounts are far below int256.max.
                // forge-lint: disable-next-line(unsafe-typecast)
                vm.toString(int256(prGas) - int256(baseGas))
            )
        );
        assertLe(prGas, baseGas, label);
    }

    function fmt(string memory label, int256 c, int256 e, bool scientific) internal view {
        Float f = LibDecimalFloat.packLossless(c, e);
        (uint256 g0, bytes32 h0) = B.formatBase(f, scientific);
        (uint256 g1, bytes32 h1) = B.formatPr(f, scientific);
        assertEq(h1, h0, label);
        row(scientific ? "formatSci" : "format", label, g0, g1);
    }

    function parse(string memory str) internal view {
        (uint256 g0, bytes32 h0) = B.parseBase(str);
        (uint256 g1, bytes32 h1) = B.parsePr(str);
        assertEq(h1, h0, str);
        row("parse", str, g0, g1);
    }

    function testFormatGas() external view {
        int256 amt18 = 1234567890123456789;
        int256 third = 3333333333333333333333333333333333333333333333333333333333333333333;
        int256 i224max = type(int224).max;
        // 3.75 as an add result packs it: 67 digits, 64 of them trailing zeros.
        int256 sum375 = 3750000000000000000000000000000000000000000000000000000000000000000;

        for (uint256 i = 0; i < 2; i++) {
            bool sci = i == 1;
            fmt("1", 1, 0, sci);
            fmt("-1", -1, 0, sci);
            fmt("1.5", 15, -1, sci);
            fmt("100", 1, 2, sci);
            fmt("amt18", amt18, -18, sci);
            fmt("1/3", third, -67, sci);
            fmt("-1/3", -third, -67, sci);
            fmt("3.75 as add result", sum375, -66, sci);
            fmt("1e-50", 1, -50, sci);
            fmt("1e50", 1, 50, sci);
            fmt("int224.max", i224max, 0, sci);
            fmt("int224.min", type(int224).min, 0, sci);
            fmt("int224.max e-1000", i224max, -1000, sci);
            fmt("1e-1000", 1, -1000, sci);
        }
        fmt("1e2147483647", 1, type(int32).max - 76, true);
        fmt("int224.min e(int32.min)", type(int224).min, type(int32).min, true);
    }

    function testParseGas() external view {
        parse("1");
        parse("-1");
        parse("1.5");
        parse("1.50000");
        parse("1.234567890123456789");
        parse("0.000000000000000001");
        parse("1234567890123456789012345");
        parse("123.456000000000000000");
        parse("1.5e10");
        parse("-1.5e-10");
        parse("1.000000000000000000000000000000");
        parse("0.0");
        parse("1.");
    }
}
