// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    MulDivOverflow
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationInvTest is Test {
    function invExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        return (signedCoefficient, exponent);
    }

    /// Compare reference.
    function testInvReference(int256 signedCoefficient, int256 exponent) external pure {
        vm.assume(signedCoefficient != 0);
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);

        (int256 outputSignedCoefficient, int256 outputExponent) =
            LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        (int256 referenceSignedCoefficient, int256 referenceExponent) =
            LibDecimalFloatSlow.invSlow(signedCoefficient, exponent);

        assertEq(outputSignedCoefficient, referenceSignedCoefficient, "coefficient");
        assertEq(outputExponent, referenceExponent, "exponent");
    }

    function testInvGas0() external pure {
        (int256 outputSignedCoefficient, int256 outputExponent) = LibDecimalFloatImplementation.inv(3e37, -37);
        (outputSignedCoefficient, outputExponent);
    }

    function testInvSlowGas0() external pure {
        (int256 outputSignedCoefficient, int256 outputExponent) = LibDecimalFloatSlow.invSlow(3e37, -37);
        (outputSignedCoefficient, outputExponent);
    }

    function testInv0() external {
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, 1e76, 1e75, 0));
        this.invExternal(0, 0);
    }
}
