// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";

/// Gas of log10, pow10, pow, sqrt, mul, the conversions and parse on packed inputs, the common shape
/// as values arrive packed, and on each function's worst case. Run with
/// `forge test --mc LibDecimalFloatGasTest -vv`; each line is the gas of the
/// internal call alone.
contract LibDecimalFloatGasTest is Test {
    using LibDecimalFloat for Float;

    function f(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    function logLog10(string memory name, Float a) internal view {
        uint256 before = gasleft();
        a.log10();
        uint256 used = before - gasleft();
        console2.log(string.concat("log10 ", name), used);
    }

    function logPow10(string memory name, Float a) internal view {
        uint256 before = gasleft();
        a.pow10();
        uint256 used = before - gasleft();
        console2.log(string.concat("pow10 ", name), used);
    }

    function logPow(string memory name, Float a, Float b) internal view {
        uint256 before = gasleft();
        a.pow(b);
        uint256 used = before - gasleft();
        console2.log(string.concat("pow ", name), used);
    }

    function logSqrt(string memory name, Float a) internal view {
        uint256 before = gasleft();
        a.sqrt();
        uint256 used = before - gasleft();
        console2.log(string.concat("sqrt ", name), used);
    }

    function logMul(string memory name, Float a, Float b) internal view {
        uint256 before = gasleft();
        a.mul(b);
        uint256 used = before - gasleft();
        console2.log(string.concat("mul ", name), used);
    }

    function testGasLog10() external view {
        logLog10("2", f(2, 0));
        logLog10("1.5", f(15, -1));
        logLog10("0.5", f(5, -1));
        logLog10("1e18 scale 1.234567890123456789", f(1234567890123456789, -18));
        logLog10("41 digits sqrt 2", f(14142135623730950488016887242096980785697, -40));
        logLog10("int224 max", f(type(int224).max, 0));
        logLog10("near 1 1.000001", f(1000001, -6));
        logLog10("power of ten 1e5", f(1, 5));
        logLog10("worst 9.998", f(9998, -3));
        logLog10("worst 9.9989999", f(99989999, -7));
    }

    function testGasPow10() external view {
        logPow10("0.5", f(5, -1));
        logPow10("1.2345", f(12345, -4));
        logPow10("-2.5", f(-25, -1));
        logPow10("integer 3", f(3, 0));
        logPow10("1e18 scale 0.301029995663981195", f(301029995663981195, -18));
        logPow10("41 digits", f(30102999566398119521373889472449302676818, -40));
        logPow10("worst 0.99999999", f(99999999, -8));
        logPow10("worst 41 digits 0.999", f(99999999999999999999999999999999999999999, -41));
    }

    function testGasPow() external view {
        logPow("2^0.5", f(2, 0), f(5, -1));
        logPow("2^1.5", f(2, 0), f(15, -1));
        logPow("2^-0.5", f(2, 0), f(-5, -1));
        logPow("2^3", f(2, 0), f(3, 0));
        logPow("1.0001^365", f(10001, -4), f(365, 0));
        logPow("1e18 scale ^ 3.7", f(1234567890123456789, -18), f(37, -1));
        logPow(
            "41 digits ^ 41 digits",
            f(14142135623730950488016887242096980785697, -40),
            f(30102999566398119521373889472449302676818, -41)
        );
        logPow("worst 1.0000001^2147483647.999", f(10000001, -7), f(2147483647999, -3));
    }

    function testGasSqrt() external view {
        logSqrt("2", f(2, 0));
        logSqrt("4", f(4, 0));
        logSqrt("1e18 scale 1.234567890123456789", f(1234567890123456789, -18));
        logSqrt("41 digits", f(14142135623730950488016887242096980785697, -40));
        logSqrt("int224 max", f(type(int224).max, 0));
        logSqrt("odd exponent 2e-1", f(2, -1));
    }

    function testGasMul() external view {
        logMul("2*3", f(2, 0), f(3, 0));
        logMul("1e18 scale", f(1234567890123456789, -18), f(9876543210987654321, -18));
        logMul(
            "41 digits",
            f(14142135623730950488016887242096980785697, -40),
            f(14142135623730950488016887242096980785697, -40)
        );
        logMul("int224 max", f(type(int224).max, 0), f(type(int224).max, 0));
    }

    function logPackLossless(string memory name, int256 signedCoefficient, int256 exponent) internal view {
        uint256 before = gasleft();
        LibDecimalFloat.packLossless(signedCoefficient, exponent);
        uint256 used = before - gasleft();
        console2.log(string.concat("packLossless ", name), used);
    }

    function logFromFixed(string memory name, uint256 value, uint8 decimals) internal view {
        uint256 before = gasleft();
        LibDecimalFloat.fromFixedDecimalLosslessPacked(value, decimals);
        uint256 used = before - gasleft();
        console2.log(string.concat("fromFixedDecimalLosslessPacked ", name), used);
    }

    function logToFixed(string memory name, Float a, uint8 decimals) internal view {
        uint256 before = gasleft();
        a.toFixedDecimalLossy(decimals);
        uint256 used = before - gasleft();
        console2.log(string.concat("toFixedDecimalLossy ", name), used);
    }

    function logParse(string memory s) internal view {
        uint256 before = gasleft();
        LibParseDecimalFloat.parseDecimalFloat(s);
        uint256 used = before - gasleft();
        console2.log(string.concat("parseDecimalFloat ", s), used);
    }

    function testGasConversions() external view {
        logPackLossless("1", 1, 0);
        logPackLossless("1e18 scale", 1234567890123456789, -18);
        logPackLossless("int256 multiple of 1e9", 1e76, -9);
        logFromFixed("1e18", 1e18, 18);
        logFromFixed("1.234567890123456789", 1234567890123456789, 18);
        logFromFixed("int224 max", uint256(int256(type(int224).max)), 6);
        logToFixed("1 to 18", f(1, 0), 18);
        logToFixed("1.234567890123456789 to 6", f(1234567890123456789, -18), 6);
        logToFixed("1e18 scale to 18", f(1234567890123456789, -18), 18);
    }

    function testGasParse() external view {
        logParse("1");
        logParse("1.5");
        logParse("1.234567890123456789");
        logParse("-1.5e-10");
        logParse("1e18");
    }
}
