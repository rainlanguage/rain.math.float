// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";

import {F} from "test/src/concrete/TestUtilsLib.sol";

contract DecimalFloatFormatTest is Test {
    using LibDecimalFloat for Float;

    function formatExternal(Float a, uint256 sigFigsLimit) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(a, sigFigsLimit);
    }

    function testFormatDeployed(Float a, uint256 sigFigsLimit) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.formatExternal(a, sigFigsLimit) returns (string memory str) {
            string memory deployedStr = deployed.format(a, sigFigsLimit);

            assertEq(str, deployedStr);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.format(a, sigFigsLimit);
        }
    }

    function checkFormatExternal(
        Float float,
        string memory expectedStr
    ) internal pure {
        (string memory result) = LibFormatDecimalFloat.toDecimalString(float);
        assertEq(result, expectedStr);
    }

    function testFormatExternalIntegers() external pure {
        checkFormatExternal(F(0x00), "0");
        checkFormatExternal(F(0x01), "1");
        checkFormatExternal(F(0x0A), "10");
        checkFormatExternal(F(0x64), "100");
        checkFormatExternal(F(0x03E8), "1000");
        checkFormatExternal(F(0x02), "2");
    }

    function testFormatExternalDecimals() external pure {
        checkFormatExternal(F(0xffffffff00000000000000000000000000000000000000000000000000000001), "0.1");
        checkFormatExternal(F(0xfffffffe00000000000000000000000000000000000000000000000000000001), "0.01");
        checkFormatExternal(F(0xfffffffd00000000000000000000000000000000000000000000000000000001), "0.001");
        checkFormatExternal(F(0xfffffffc00000000000000000000000000000000000000000000000000000002), "0.0002");
        checkFormatExternal(F(0xfffffffc00000000000000000000000000000000000000000000000000003e3b), "1.5931");
    }

    function testFormatExternalNegativeIntegers() external pure {
        checkFormatExternal(F(0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff), "-1");
        checkFormatExternal(F(0x00000000fffffffffffffffffffffffffffffffffffffffffffffffffffffffe), "-2");
        checkFormatExternal(F(0x00000000fffffffffffffffffffffffffffffffffffffffffffffffffffffff6), "-10");
        checkFormatExternal(F(0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffff9c), "-100");
    }


    function testFormatExternalNegativeDecimals() external pure {
        checkFormatExternal(F(0xfffffffeffffffffffffffffffffffffffffffffffffffffffffffffffffffff), "-0.01");
        checkFormatExternal(F(0xfffffffdffffffffffffffffffffffffffffffffffffffffffffffffffffffff), "-0.001");
        checkFormatExternal(F(0xfffffffcfffffffffffffffffffffffffffffffffffffffffffffffffffffffd), "-0.0003");
    }
}
