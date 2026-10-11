// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatImplementationSeriesSolidity} from "test/lib/LibDecimalFloatImplementationSeriesSolidity.sol";
import {LibDecimalFloatImplementationSeriesMain} from "test/lib/LibDecimalFloatImplementationSeriesMain.sol";

/// The plain-Solidity copy of `log10Ratio` and `exp10Fixed` returns exactly
/// what the library returns, so its gas rows compare one algorithm and
/// isolate what the assembly saves. Main is the loop before unrolling.
/// `GAS|function|case|main|solidity|assembly|assembly - solidity`.
contract LibDecimalFloatImplementationSeriesSolidityTest is Test {
    function log10RatioAsm(uint256 a, uint256 b, bool relative)
        external
        view
        returns (uint256 gas, int256 signedCoefficient, int256 exponent)
    {
        gas = gasleft();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.log10Ratio(a, b, relative);
        gas -= gasleft();
    }

    function log10RatioSol(uint256 a, uint256 b, bool relative)
        external
        view
        returns (uint256 gas, int256 signedCoefficient, int256 exponent)
    {
        gas = gasleft();
        (signedCoefficient, exponent) = LibDecimalFloatImplementationSeriesSolidity.log10Ratio(a, b, relative);
        gas -= gasleft();
    }

    function log10RatioMain(uint256 a, uint256 b, bool relative)
        external
        view
        returns (uint256 gas, int256 signedCoefficient, int256 exponent)
    {
        gas = gasleft();
        (signedCoefficient, exponent) = LibDecimalFloatImplementationSeriesMain.log10Ratio(a, b, relative);
        gas -= gasleft();
    }

    function exp10FixedMain(uint256 x) external view returns (uint256 gas, uint256 result) {
        gas = gasleft();
        result = LibDecimalFloatImplementationSeriesMain.exp10Fixed(x);
        gas -= gasleft();
    }

    function exp10FixedAsm(uint256 x) external view returns (uint256 gas, uint256 result) {
        gas = gasleft();
        result = LibDecimalFloatImplementation.exp10Fixed(x);
        gas -= gasleft();
    }

    function exp10FixedSol(uint256 x) external view returns (uint256 gas, uint256 result) {
        gas = gasleft();
        result = LibDecimalFloatImplementationSeriesSolidity.exp10Fixed(x);
        gas -= gasleft();
    }

    function checkRatio(uint256 a, uint256 b, bool relative) internal view {
        try this.log10RatioAsm(a, b, relative) returns (uint256, int256 asmCoefficient, int256 asmExponent) {
            (, int256 solCoefficient, int256 solExponent) = this.log10RatioSol(a, b, relative);
            assertEq(solCoefficient, asmCoefficient, "coefficient");
            assertEq(solExponent, asmExponent, "exponent");
        } catch (bytes memory err) {
            try this.log10RatioSol(a, b, relative) {
                revert("solidity copy did not revert");
            } catch (bytes memory solErr) {
                assertEq(solErr, err, "revert");
            }
        }
    }

    function checkRatio(uint256 a, uint256 b) internal view {
        checkRatio(a, b, true);
        checkRatio(a, b, false);
    }

    function checkExp10(uint256 x) internal view {
        (, uint256 asmResult) = this.exp10FixedAsm(x);
        (, uint256 solResult) = this.exp10FixedSol(x);
        assertEq(solResult, asmResult);
    }

    /// Any a and b at most 1e76, either mode, including relative sums below
    /// 1e50 that revert.
    function testLog10RatioSolidityEquivalence(uint256 a, uint256 b, bool relative) external view {
        a = bound(a, 0, 1e76);
        b = bound(b, 0, 1e76);
        checkRatio(a, b, relative);
    }

    /// z = |a - b| / (a + b) up to 5.1e-4, a and b in [1e75 / 1.002, 1e76].
    function testLog10RatioSolidityEquivalenceSeriesDomain(uint256 b, uint256 d, bool below) external view {
        b = bound(b, 1e75, 9.9e75);
        d = bound(d, 0, b / 1e6 * (below ? 1019 : 1020));
        checkRatio(below ? b - d : b + d, b);
    }

    /// The reduced gap `log10Reduce` leaves, a within 10^(2^-16) of 1e75.
    function testLog10RatioSolidityEquivalenceReduced(uint256 a) external view {
        a = bound(a, 1e75 - 2, 1000035135277461856608582335861556633189962147970549360011398536055919590052);
        checkRatio(a, 1e75);
    }

    /// z = u 1e25 + v at each end of v.
    function testLog10RatioSolidityEquivalenceZSquaredSplit(uint256 u) external view {
        u = bound(u, 0, 4.99e21);
        checkRatio(1e75 + u * 1e25, 1e75);
        checkRatio(1e75 + u * 1e25 + 1e25 - 1, 1e75);
    }

    function testLog10RatioSolidityEquivalenceExamples() external view {
        checkRatio(500255e70, 499745e70);
        checkRatio(499745e70, 500255e70);
        checkRatio(1001e72 - 1, 1e75);
        checkRatio(9999e72, 1e76);
        checkRatio(1e75 + 1, 1e75);
        checkRatio(1e75, 1e75);
        checkRatio(0, 1e76);
        checkRatio(1e76, 0);
        checkRatio(0, 0);
    }

    function testExp10FixedSolidityEquivalence(uint256 x) external view {
        checkExp10(bound(x, 0, 1e50 - 1));
    }

    /// Every binary digit set, every one clear, each alone, and the inputs
    /// whose final and ln 10 Horner multiplies borrow.
    function testExp10FixedSolidityEquivalenceExamples() external view {
        uint256[10] memory xs = [
            uint256(0),
            1e50 - 1,
            1.52587890625e45 - 1,
            1e50 - 1.52587890625e45,
            5e49 + 87015477053855611590102368556,
            5e49 + 129156888290026095774709585062,
            5e49 + 430189686290292988458280452418,
            858803594111162378152345370348828441692620967,
            724330556364502386237515770486668923888293239,
            432154281105992271870088449799288377367521809
        ];
        for (uint256 i = 0; i < xs.length; i++) {
            checkExp10(xs[i]);
        }
        uint256 step = 5e49;
        for (uint256 i = 0; i < 16; i++) {
            checkExp10(step);
            checkExp10(step + 1.52587890625e45 - 1);
            step /= 2;
        }
    }

    function row(string memory fn, string memory label, uint256 mainGas, uint256 solGas, uint256 asmGas) internal pure {
        console2.log(
            string.concat(
                "GAS|",
                fn,
                "|",
                label,
                "|",
                vm.toString(mainGas),
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
    }

    /// The arguments `log10Unrounded` passes `log10Ratio` for a coefficient in
    /// [1.001e75, 9.999e75).
    function benchReduced(string memory label, uint256 coefficient) internal view {
        (uint256 reduced,) = LibDecimalFloatImplementation.log10Reduce(coefficient);
        benchRatio(label, reduced, 1e75, false);
    }

    function benchRatio(string memory label, uint256 a, uint256 b, bool relative) internal view {
        (uint256 solGas, int256 solCoefficient, int256 solExponent) = this.log10RatioSol(a, b, relative);
        (uint256 asmGas, int256 asmCoefficient, int256 asmExponent) = this.log10RatioAsm(a, b, relative);
        assertEq(solCoefficient, asmCoefficient, label);
        assertEq(solExponent, asmExponent, label);
        (uint256 mainGas, int256 mainCoefficient, int256 mainExponent) = this.log10RatioMain(a, b, relative);
        assertEq(mainCoefficient, asmCoefficient, label);
        assertEq(mainExponent, asmExponent, label);
        row("log10Ratio", label, mainGas, solGas, asmGas);
    }

    function benchExp10(string memory label, uint256 x) internal view {
        (uint256 solGas, uint256 solResult) = this.exp10FixedSol(x);
        (uint256 asmGas, uint256 asmResult) = this.exp10FixedAsm(x);
        assertEq(solResult, asmResult, label);
        (uint256 mainGas, uint256 mainResult) = this.exp10FixedMain(x);
        assertEq(mainResult, asmResult, label);
        row("exp10Fixed", label, mainGas, solGas, asmGas);
    }

    /// The `log10Ratio` and `exp10Fixed` calls behind the log10 and pow10 gas
    /// bench inputs.
    function testSeriesSolidityGas() external view {
        benchReduced("log10 1.5 (log10 packed)", 1.5e75);
        benchReduced("log10 2", 2e75);
        benchReduced("log10 worst 9.998", 9.998e75);
        benchRatio("log10 1.0001 (relative)", 1.0001e75, 1e75, true);
        benchRatio("log10 0.9999 (relative)", 9.999e75, 1e76, true);
        benchRatio("log10 10.001 (near 10, not relative)", 1.0001e75, 1e75, false);
        benchExp10("pow10 1.5 (pow10 packed)", 5e49);
        benchExp10("pow10 1.2345", 2.345e49);
        benchExp10("pow10 worst 0.99999999", 9.9999999e49);
    }
}
