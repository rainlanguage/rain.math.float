// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest, console2} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

/// Gas of every packing operation on packed inputs whose result fits, and on
/// the results that shed digits or take the int224 bound. Run with
/// `forge test --mc LibDecimalFloatOpsGasTest -vv`; each line is the gas of
/// the call through an internal function pointer alone.
contract LibDecimalFloatOpsGasTest is LogTest {
    using LibDecimalFloat for Float;

    function f(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    function log2(string memory name, function(Float, Float) internal pure returns (Float) op, Float a, Float b)
        internal
        view
    {
        uint256 before = gasleft();
        op(a, b);
        uint256 used = before - gasleft();
        console2.log(name, used);
    }

    function log1(string memory name, function(Float) internal pure returns (Float) op, Float a) internal view {
        uint256 before = gasleft();
        op(a);
        uint256 used = before - gasleft();
        console2.log(name, used);
    }

    function logT(string memory name, function(Float, address) internal view returns (Float) op, Float a) internal {
        address tables = logTables();
        uint256 before = gasleft();
        op(a, tables);
        uint256 used = before - gasleft();
        console2.log(name, used);
    }

    function testGasBinary() external view {
        Float a = f(15, -1);
        Float b = f(1234567890123456789, -18);
        Float max = f(type(int224).max, 0);
        Float min = f(type(int224).min, 0);
        Float one = f(1, 0);
        Float negOne = f(-1, 0);

        log2("add packed", LibDecimalFloat.add, a, b);
        log2("add shed", LibDecimalFloat.add, max, max);
        log2("add bound", LibDecimalFloat.add, max, one);
        log2("sub packed", LibDecimalFloat.sub, a, b);
        log2("sub shed", LibDecimalFloat.sub, max, min);
        log2("sub bound", LibDecimalFloat.sub, LibDecimalFloat.FLOAT_ZERO, min);
        log2("mul packed", LibDecimalFloat.mul, a, b);
        log2("mul shed", LibDecimalFloat.mul, max, max);
        log2("mul bound", LibDecimalFloat.mul, min, negOne);
        log2("div packed", LibDecimalFloat.div, a, b);
        log2("div shed", LibDecimalFloat.div, one, f(3, 0));
        log2("div bound", LibDecimalFloat.div, min, negOne);
        log2("min packed", LibDecimalFloat.min, a, b);
        log2("max packed", LibDecimalFloat.max, a, b);
    }

    function testGasUnary() external view {
        Float a = f(15, -1);
        Float negA = f(-15, -1);
        Float min = f(type(int224).min, 0);

        log1("minus packed", LibDecimalFloat.minus, a);
        log1("minus bound", LibDecimalFloat.minus, min);
        log1("abs positive", LibDecimalFloat.abs, a);
        log1("abs negative", LibDecimalFloat.abs, negA);
        log1("abs bound", LibDecimalFloat.abs, min);
        log1("inv packed", LibDecimalFloat.inv, a);
        log1("inv shed", LibDecimalFloat.inv, f(3, 0));
        log1("integer packed", LibDecimalFloat.integer, a);
        log1("frac packed", LibDecimalFloat.frac, a);
        log1("floor packed", LibDecimalFloat.floor, negA);
        log1("ceil packed", LibDecimalFloat.ceil, a);
        log1("canonicalize packed", LibDecimalFloat.canonicalize, a);
    }

    function logPack(string memory name, int256 signedCoefficient, int256 exponent) internal view {
        uint256 before = gasleft();
        LibDecimalFloat.packLossy(signedCoefficient, exponent);
        uint256 used = before - gasleft();
        console2.log(name, used);
    }

    function testGasPack() external view {
        int256 two223 = int256(1) << 223;
        logPack("packLossy fits", 15, -1);
        logPack("packLossy shed", two223 + 2, 0);
        logPack("packLossy shed 1e73", (two223 + 2) * 1e6 + 7, 0);
        logPack("packLossy shed 1e76", (two223 + 2) * 1e9 + 7, 0);
        logPack("packLossy bound 1e76", two223 * 1e9 + 7, 0);
        logPack("packLossy bound", two223, 0);
        logPack("packLossy bound negative", -two223 - 1, 0);
        logPack("packLossy bound below floor", two223, int256(type(int32).min) - 1);
    }

    function testGasTables() external {
        Float a = f(15, -1);
        logT("log10 packed", LibDecimalFloat.log10, a);
        logT("pow10 packed", LibDecimalFloat.pow10, a);
        logT("sqrt packed", LibDecimalFloat.sqrt, f(2, 0));
    }
}
