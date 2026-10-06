// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatGasMain} from "test/lib/LibDecimalFloatGasMain.sol";

/// Every input returns the same bytes, or reverts with the same bytes, as main
/// before the #310 gas changes.
contract LibDecimalFloatGasMainEquivalenceTest is Test {
    function mainMaximize(int256 c, int256 e) external pure returns (int256, int256, int256) {
        return LibDecimalFloatGasMain.maximize(c, e);
    }

    function prMaximize(int256 c, int256 e) external pure returns (int256, int256, int256) {
        return LibDecimalFloatImplementation.maximize(c, e);
    }

    function mainMul(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatGasMain.mul(a, ea, b, eb);
    }

    function prMul(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.mul(a, ea, b, eb);
    }

    function mainPackLossy(int256 c, int256 e) external pure returns (Float, bool) {
        return LibDecimalFloatGasMain.packLossy(c, e);
    }

    function prPackLossy(int256 c, int256 e) external pure returns (Float, bool) {
        return LibDecimalFloat.packLossy(c, e);
    }

    function mainPackLossless(int256 c, int256 e) external pure returns (Float) {
        return LibDecimalFloatGasMain.packLossless(c, e);
    }

    function prPackLossless(int256 c, int256 e) external pure returns (Float) {
        return LibDecimalFloat.packLossless(c, e);
    }

    function mainPackArithmeticResult(int256 c, int256 e) external pure returns (Float) {
        return LibDecimalFloatGasMain.packArithmeticResult(c, e);
    }

    function prPackArithmeticResult(int256 c, int256 e) external pure returns (Float) {
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    function same(bytes memory mainCall, bytes memory prCall) internal view {
        (bool mainOk, bytes memory mainRet) = address(this).staticcall(mainCall);
        (bool prOk, bytes memory prRet) = address(this).staticcall(prCall);
        assertEq(prOk, mainOk, "success");
        assertEq(prRet, mainRet, "bytes");
    }

    function checkMaximize(int256 c, int256 e) internal view {
        same(abi.encodeCall(this.mainMaximize, (c, e)), abi.encodeCall(this.prMaximize, (c, e)));
    }

    function checkMul(int256 a, int256 ea, int256 b, int256 eb) internal view {
        same(abi.encodeCall(this.mainMul, (a, ea, b, eb)), abi.encodeCall(this.prMul, (a, ea, b, eb)));
    }

    function checkPack(int256 c, int256 e) internal view {
        same(abi.encodeCall(this.mainPackLossy, (c, e)), abi.encodeCall(this.prPackLossy, (c, e)));
        same(abi.encodeCall(this.mainPackLossless, (c, e)), abi.encodeCall(this.prPackLossless, (c, e)));
        same(
            abi.encodeCall(this.mainPackArithmeticResult, (c, e)), abi.encodeCall(this.prPackArithmeticResult, (c, e))
        );
    }

    /// A coefficient of `d` digits in [1, 77], either sign, `x` choosing where
    /// in the digit count it falls.
    function ofDigits(uint256 d, uint256 x, bool negative) internal pure returns (int256 c) {
        d = bound(d, 1, 77);
        uint256 lo = 10 ** (d - 1);
        uint256 hi = d == 77 ? uint256(type(int256).max) : 10 ** d - 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        c = int256(bound(x, lo, hi));
        if (negative) c = -c;
    }

    /// Sweeps the edges every changed branch turns on: powers of ten, the
    /// int224 and int256 bounds scaled by powers of ten, and their neighbours.
    function edge(uint256 kind, uint256 k, int256 delta, bool negative) internal pure returns (int256 c) {
        kind = bound(kind, 0, 3);
        k = bound(k, 0, 76);
        delta = bound(delta, -2, 2);
        uint256 base;
        if (kind == 0) {
            base = 10 ** k;
        } else if (kind == 1) {
            base = (uint256(1) << 223) * 10 ** bound(k, 0, 9);
        } else if (kind == 2) {
            base = ((uint256(1) << 223) + 1) * 10 ** bound(k, 0, 9);
        } else {
            base = uint256(type(int256).max) / 10 ** bound(k, 0, 76);
        }
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            c = int256(base) + delta;
            if (negative) c = -c;
        }
    }

    function exponentOf(uint256 kind, int256 x) internal pure returns (int256) {
        kind = bound(kind, 0, 5);
        if (kind == 0) return bound(x, -100, 100);
        if (kind == 1) return bound(x, type(int32).min - int256(100), type(int32).min + int256(100));
        if (kind == 2) return bound(x, type(int32).max - int256(100), type(int32).max + int256(100));
        if (kind == 3) return type(int256).min + bound(x, 0, 200);
        if (kind == 4) return type(int256).max - bound(x, 0, 200);
        return x;
    }

    function coefficientOf(uint256 kind, uint256 d, uint256 x, int256 raw, bool negative)
        internal
        pure
        returns (int256)
    {
        kind = bound(kind, 0, 2);
        if (kind == 0) return ofDigits(d, x, negative);
        if (kind == 1) return edge(d, x, raw, negative);
        return raw;
    }

    function testGasMainMaximize(uint256 ck, uint256 d, uint256 x, int256 raw, bool neg, uint256 ek, int256 e)
        external
        view
    {
        checkMaximize(coefficientOf(ck, d, x, raw, neg), exponentOf(ek, e));
    }

    /// One seed picks a coefficient's shape and its exponent's.
    function operand(uint256 seed, int256 raw, int256 e) internal pure returns (int256, int256) {
        return (
            coefficientOf(seed % 3, seed >> 8, uint256(keccak256(abi.encode(seed))), raw, (seed >> 16) & 1 == 1),
            exponentOf(seed >> 24, e)
        );
    }

    function testGasMainMul(uint256 seedA, int256 rawA, int256 ea, uint256 seedB, int256 rawB, int256 eb)
        external
        view
    {
        (int256 a, int256 exponentA) = operand(seedA, rawA, ea);
        (int256 b, int256 exponentB) = operand(seedB, rawB, eb);
        checkMul(a, exponentA, b, exponentB);
    }

    /// Packed operands, the shape every public `mul` passes.
    function testGasMainMulPacked(int224 a, int32 ea, int224 b, int32 eb) external view {
        checkMul(a, ea, b, eb);
    }

    function testGasMainPack(uint256 ck, uint256 d, uint256 x, int256 raw, bool neg, uint256 ek, int256 e)
        external
        view
    {
        checkPack(coefficientOf(ck, d, x, raw, neg), exponentOf(ek, e));
    }

    /// Every digit count at both ends, both signs, against exponents near
    /// each bound.
    function testGasMainDigitCounts() external view {
        int256[6] memory exponents =
            [int256(0), -18, type(int32).min, type(int32).max, type(int256).min + 40, type(int256).max];
        for (uint256 d = 1; d <= 77; d++) {
            int256 lo = ofDigits(d, 0, false);
            int256 hi = ofDigits(d, type(uint256).max, false);
            for (uint256 i = 0; i < exponents.length; i++) {
                int256 e = exponents[i];
                checkMaximize(lo, e);
                checkMaximize(hi, e);
                checkMaximize(-lo, e);
                checkMaximize(-hi, e);
                checkPack(lo, e);
                checkPack(hi, e);
                checkPack(-lo, e);
                checkPack(-hi, e);
                checkMul(hi, e, hi, -18);
                checkMul(-hi, e, lo, 5);
                checkMul(lo, -1, -lo, e);
            }
        }
        checkMaximize(type(int256).min, 0);
        checkPack(type(int256).min, 0);
        checkMul(type(int256).min, 0, type(int256).min, 0);
        checkMul(type(int256).min, 0, -1, 0);
    }

    /// Both sides of the times-ten bound in `maximize`.
    function testGasMainTimesTenBound() external view {
        int256 m = type(int256).max / 10;
        for (int256 delta = -2; delta <= 2; delta++) {
            checkMaximize(m + delta, 0);
            checkMaximize(-m + delta, 0);
            checkMaximize((m + delta) / 10, 0);
            checkMaximize((-m + delta) / 10, 0);
        }
    }
}
