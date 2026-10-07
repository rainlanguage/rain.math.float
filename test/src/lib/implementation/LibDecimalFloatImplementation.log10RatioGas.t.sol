// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// Logs the gas of the relative `log10Ratio` path per input, and of the
/// `log10` inputs that reach it, measured inside the call so ABI overhead is
/// excluded. Run with `-vv` on two trees to compare them.
contract LibDecimalFloatImplementationLog10RatioGasTest is Test {
    function ratioGas(uint256 a, uint256 b) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloatImplementation.log10Ratio(a, b, true);
        g -= gasleft();
    }

    function implGas(int256 signedCoefficient, int256 exponent) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloatImplementation.log10(signedCoefficient, exponent);
        g -= gasleft();
    }

    function floatGas(Float a) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloat.log10(a);
        g -= gasleft();
    }

    function logRatio(string memory name, uint256 a, uint256 b) internal view {
        console2.log(string.concat("ratio ", name), this.ratioGas(a, b));
    }

    function logLog10(string memory name, int256 signedCoefficient, int256 exponent) internal view {
        console2.log(string.concat("impl  ", name), this.implGas(signedCoefficient, exponent));
        Float a = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        console2.log(string.concat("float ", name), this.floatGas(a));
    }

    function testLog10RatioGasRelative() external view {
        logRatio("1e75 + 1", 1e75 + 1, 1e75);
        logRatio("1e75 + 1e10", 1e75 + 1e10, 1e75);
        logRatio("1e75 + 1e30", 1e75 + 1e30, 1e75);
        logRatio("1e75 + 1e50", 1e75 + 1e50, 1e75);
        logRatio("1e75 + 1e60", 1e75 + 1e60, 1e75);
        logRatio("1e75 + 1e68", 1e75 + 1e68, 1e75);
        logRatio("1e75 + 1e70", 1e75 + 1e70, 1e75);
        logRatio("1e75 + 1e71", 1e75 + 1e71, 1e75);
        logRatio("1e75 + 5e71", 1e75 + 5e71, 1e75);
        logRatio("1e75 + 1e72 - 1", 1e75 + 1e72 - 1, 1e75);
        logRatio("1e76 - 1", 1e76 - 1, 1e76);
        logRatio("1e76 - 1e40", 1e76 - 1e40, 1e76);
        logRatio("1e76 - 1e72", 1e76 - 1e72, 1e76);
        logRatio("1e76 - 3e72", 1e76 - 3e72, 1e76);
        logRatio("1e76 - 1e73 + 1", 1e76 - 1e73 + 1, 1e76);
    }

    function testLog10RatioGasLog10() external view {
        logLog10("1.000000000000000000000000000000000000001", 1000000000000000000000000000000000000001, -39);
        logLog10("1.0000000001", 10000000001, -10);
        logLog10("1.0000001", 10000001, -7);
        logLog10("1.0001", 10001, -4);
        logLog10("1.0005", 10005, -4);
        logLog10("1.000999", 1000999, -6);
        logLog10("0.99999", 99999, -5);
        logLog10("0.9999999", 9999999, -7);
        logLog10("0.99999999999999999999", 99999999999999999999, -20);
        logLog10("2 (not relative)", 2, 0);
        logLog10("3.14159 (not relative)", 314159, -5);
        logLog10("10.0005 (not relative)", 100005, -4);
        logLog10("0.9995 (not relative)", 9995, -4);
    }
}
