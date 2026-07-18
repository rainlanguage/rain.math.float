// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    DivisionByZero
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatImplementationInvTest is Test {
    function invExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        return (signedCoefficient, exponent);
    }

    /// Compare reference. The exponent stays far enough inside the domain
    /// that the inverse's exponent cannot leave it.
    function testInvReference(int256 signedCoefficient, int256 exponent) external pure {
        vm.assume(signedCoefficient != 0);
        exponent = bound(exponent, EXPONENT_MIN + 153, EXPONENT_MAX - 153);

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
        vm.expectRevert(abi.encodeWithSelector(DivisionByZero.selector, 1e76, -76));
        this.invExternal(0, 0);
    }

    /// Inverting a value at the top of the exponent domain produces an
    /// exponent below `EXPONENT_MIN`, which reverts `ExponentOverflow` on the
    /// result rather than returning an out-of-domain exponent.
    function testInvAtDomainEdgeReverts() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, 1e76, EXPONENT_MIN - 76));
        this.invExternal(1, EXPONENT_MAX);
    }
}
