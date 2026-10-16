// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {FormatGas} from "../../concrete/FormatGas.sol";
import {LibDecimalFloat, Float} from "../../../src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "../../../src/lib/format/LibFormatDecimalFloat.sol";

/// Gas of `toDecimalString` against its plain-Solidity copy, measured the same
/// way: the library call alone between two `gasleft()` reads. Every row
/// asserts the same result bytes and no more gas. Run with `forge test --mc
/// LibDecimalFloatFormatGasTest -vv`; each line is
/// `GAS|op|case|solidity|assembly|delta`.
contract LibDecimalFloatFormatGasTest is Test {
    FormatGas internal immutable B = new FormatGas();

    function row(string memory op, string memory label, uint256 solGas, uint256 asmGas) internal pure {
        console2.log(
            string.concat(
                "GAS|",
                op,
                "|",
                label,
                "|",
                vm.toString(solGas),
                "|",
                vm.toString(asmGas),
                "|",
                // Gas amounts are far below int256.max.
                // forge-lint: disable-next-line(unsafe-typecast)
                vm.toString(int256(asmGas) - int256(solGas))
            )
        );
        assertLe(asmGas, solGas, label);
    }

    function fmt(string memory label, int256 c, int256 e, bool scientific) internal view {
        Float f = LibDecimalFloat.packLossless(c, e);
        (uint256 g1, bytes32 h1) = B.formatLive(f, scientific);
        // The same digit-buffer algorithm in plain Solidity, so the
        // assembly's own saving is measured apart from the algorithm's.
        (uint256 g2, bytes32 h2) = B.formatSol(f, scientific);
        assertEq(h2, h1, label);
        row(scientific ? "formatSciSolVsAsm" : "formatSolVsAsm", label, g2, g1);
    }

    /// The plain-Solidity copy returns the same bytes and reverts with the
    /// same data as the library, so its gas rows compare one algorithm. Every
    /// Float, in both modes.
    function testFormatSolidityCopyEquivalence(int224 c, int32 e, bool scientific) external {
        checkSolidityCopy(LibDecimalFloat.packLossless(c, e), scientific);
    }

    /// Non-scientific mode reverts past the exponent cap, which is most of
    /// int32, so this samples the exponents it formats.
    function testFormatSolidityCopyEquivalenceInsideCap(int224 c, int256 e) external {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        checkSolidityCopy(LibDecimalFloat.packLossless(c, bound(e, -cap, cap)), false);
    }

    function checkSolidityCopy(Float f, bool scientific) internal {
        try B.formatLive(f, scientific) returns (uint256, bytes32 h) {
            (, bytes32 hSol) = B.formatSol(f, scientific);
            assertEq(hSol, h);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            B.formatSol(f, scientific);
        }
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
}
