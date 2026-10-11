// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {ScaleUpOutOfRange} from "src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatImplementationScaleUpTest is Test {
    function scaleUpExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.scaleUp(signedCoefficient, exponent);
    }

    function check(int256 signedCoefficient, int256 exponent, int256 expectedCoefficient, int256 expectedExponent)
        internal
        pure
    {
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.scaleUp(signedCoefficient, exponent);
        assertEq(actualCoefficient, expectedCoefficient, "coefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function checkReverts(int256 signedCoefficient, int256 exponent) internal {
        vm.expectRevert(abi.encodeWithSelector(ScaleUpOutOfRange.selector, signedCoefficient, exponent));
        this.scaleUpExternal(signedCoefficient, exponent);
    }

    /// The coefficient's ends, 1 and 1e76 - 1, and the largest that shifts,
    /// 1e75 - 1.
    function testScaleUpCoefficientEnds() external pure {
        check(1, 0, 1e75, -75);
        check(1e75 - 1, 5, 1e76 - 10, 4);
        check(1e75, 5, 1e75, 5);
        check(1e76 - 1, 0, 1e76 - 1, 0);
    }

    /// #422: a coefficient of zero or below shifted by 78 digits, wrapping
    /// a negative one, and 1e76 or more was returned unscaled. Each reverts
    /// with the input.
    function testScaleUpCoefficientOutOfRange() external {
        int256[6] memory coefficients = [int256(0), -1, -1e75, type(int256).min, 1e76, type(int256).max];
        for (uint256 i = 0; i < coefficients.length; i++) {
            checkReverts(coefficients[i], 7);
        }
    }

    function testScaleUpCoefficientOutOfRangeFuzz(int256 signedCoefficient, int256 exponent, bool high) external {
        signedCoefficient =
            high ? bound(signedCoefficient, 1e76, type(int256).max) : bound(signedCoefficient, type(int256).min, 0);
        checkReverts(signedCoefficient, exponent);
    }

    /// #422: below `type(int256).min + 75` the exponent wrapped. A shift of
    /// t digits needs t of room above int256.min: 1 shifts 75 and 1e74 one.
    function testScaleUpExponentFloorEnds() external {
        int256 min = type(int256).min;
        check(1, min + 75, 1e75, min);
        check(1e74, min + 1, 1e75, min);
        check(1e75, min, 1e75, min);
        check(1e76 - 1, min, 1e76 - 1, min);
        checkReverts(1, min + 74);
        checkReverts(1, min);
        checkReverts(1e74, min);
        checkReverts(1e75 - 1, min);
    }

    /// c in (0, 1e76) is scaled by the t digits that bring it into
    /// [1e75, 1e76), and returned at e - t exactly when that is at least
    /// int256.min; otherwise the input is reverted with.
    function checkRule(int256 signedCoefficient, int256 exponent) internal {
        int256 t = 0;
        int256 scaled = signedCoefficient;
        while (scaled < 1e75) {
            scaled *= 10;
            t++;
        }
        if (exponent >= type(int256).min + t) {
            check(signedCoefficient, exponent, scaled, exponent - t);
        } else {
            checkReverts(signedCoefficient, exponent);
        }
    }

    function testScaleUpFuzz(int256 signedCoefficient, int256 exponent) external {
        checkRule(bound(signedCoefficient, 1, 1e76 - 1), exponent);
    }

    /// As `testScaleUpFuzz`, with the exponent within 80 of the floor.
    function testScaleUpFuzzNearFloor(int256 signedCoefficient, int256 room) external {
        checkRule(bound(signedCoefficient, 1, 1e76 - 1), type(int256).min + bound(room, 0, 80));
    }
}
