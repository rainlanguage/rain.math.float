// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";

import {F} from "test/src/concrete/TestUtilsLib.sol";

contract DecimalFloatParseTest is Test {
    using LibDecimalFloat for Float;

    function parseExternal(string memory str) external pure returns (bytes4, Float) {
        return LibParseDecimalFloat.parseDecimalFloat(str);
    }

    function testParseDeployed(string memory str) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.parseExternal(str) returns (bytes4 errorSelector, Float parsed) {
            (bytes4 deployedErrorSelector, Float deployedParsed) = deployed.parse(str);

            assertEq(errorSelector, deployedErrorSelector);
            assertEq(Float.unwrap(parsed), Float.unwrap(deployedParsed));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.parse(str);
        }
    }

    function checkParseExternal(
        string memory str,
        Float expectedFloat
    ) internal pure {
        (bytes4 errorSelector, Float float) = LibParseDecimalFloat.parseDecimalFloat(str);

        assertEq(errorSelector, bytes4(0));
        assertEq(Float.unwrap(float), Float.unwrap(expectedFloat));
    }

    function testParseExternalIntegers() external pure {
        checkParseExternal("0", F(0x00));
        checkParseExternal("1", F(0x01));
        checkParseExternal("10", F(0x0A));
        checkParseExternal("100", F(0x64));
        checkParseExternal("1000", F(0x03E8));
        checkParseExternal("2", F(0x02));
    }

    function testParseExternalDecimals() external pure {
        checkParseExternal("1.0", F(0x01));
        checkParseExternal("0.1", F(0xffffffff00000000000000000000000000000000000000000000000000000001));
        checkParseExternal("0.01", F(0xfffffffe00000000000000000000000000000000000000000000000000000001));
        checkParseExternal("0.001", F(0xfffffffd00000000000000000000000000000000000000000000000000000001));
        checkParseExternal("0.0002", F(0xfffffffc00000000000000000000000000000000000000000000000000000002));
        checkParseExternal("1.5931", F(0xfffffffc00000000000000000000000000000000000000000000000000003e3b));
    }

    function testParseExternalNegativeIntegers() external pure {
        checkParseExternal("-0", F(0x00));
        checkParseExternal("-1", F(0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff));
        checkParseExternal("-2", F(0x00000000fffffffffffffffffffffffffffffffffffffffffffffffffffffffe));
        checkParseExternal("-10", F(0x00000000fffffffffffffffffffffffffffffffffffffffffffffffffffffff6));
        checkParseExternal("-100", F(0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffff9c));
    }


    function testParseExternalNegativeDecimals() external pure {
        checkParseExternal("-0.01", F(0xfffffffeffffffffffffffffffffffffffffffffffffffffffffffffffffffff));
        checkParseExternal("-0.001", F(0xfffffffdffffffffffffffffffffffffffffffffffffffffffffffffffffffff));
        checkParseExternal("-0.0003", F(0xfffffffcfffffffffffffffffffffffffffffffffffffffffffffffffffffffd));
    }
}
