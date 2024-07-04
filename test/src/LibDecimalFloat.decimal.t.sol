// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {
    LibDecimalFloat,
    ExponentOverflow,
    NORMALIZED_MAX,
    NORMALIZED_MIN,
    NegativeFixedDecimalConversion
} from "src/lib/LibDecimalFloat.sol";

import {Test, console2, stdError} from "forge-std/Test.sol";

contract LibDecimalFloatDecimalTest is Test {
    function toFixedDecimalLossyExternal(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
        pure
        returns (uint256, bool)
    {
        return LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
    }

    /// Round trip from/to decimal values without precision loss
    function testFixedDecimalRoundTripLossless(uint256 value, uint8 decimals) external pure {
        value = bound(value, 0, uint256(NORMALIZED_MAX));

        (int256 signedCoefficient, int256 exponent, bool lossless0) =
            LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        assertEq(lossless0, true, "lossless0");

        (uint256 valueOut, bool lossless1) = LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        assertEq(value, valueOut, "value");
        assertEq(lossless1, true, "lossless1");
    }

    function checkFromFixedDecimalLossless(
        uint256 value,
        uint8 decimals,
        int256 expectedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 signedCoefficient, int256 exponent, bool lossless) =
            LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        assertEq(signedCoefficient, expectedCoefficient, "signedCoefficient");
        assertEq(exponent, expectedExponent, "exponent");
        assertEq(lossless, true, "lossless");
    }

    function checkFromFixedDecimalLossy(
        uint256 value,
        uint8 decimals,
        int256 expectedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 signedCoefficient, int256 exponent, bool lossless) =
            LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        assertEq(signedCoefficient, expectedCoefficient, "signedCoefficient");
        assertEq(exponent, expectedExponent, "exponent");
        assertEq(lossless, false, "lossless");
    }

    function checkToFixedDecimalLossless(
        int256 signedCoefficient,
        int256 exponent,
        uint8 decimals,
        uint256 expectedValue
    ) internal pure {
        (uint256 value, bool lossless) = LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        assertEq(value, expectedValue, "value");
        assertEq(lossless, true, "lossless");
    }

    function testFromFixedDecimalLossyOne() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            checkFromFixedDecimalLossless(1, i, 1e37, -37 - int256(uint256(i)));
        }
    }

    function testFromFixedDecimalLossyOneMillion() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            checkFromFixedDecimalLossless(1e6, i, 1e37, -37 + 6 - int256(uint256(i)));
        }
    }

    function testFromFixedDecimalLossyComplicated() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            checkFromFixedDecimalLossless(123456789, i, 1.23456789e37, -37 + 8 - int256(uint256(i)));
        }
    }

    /// The max normalized value will be lossless.
    function testFromFixedDecimalLossyNormalizedMax() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            checkFromFixedDecimalLossless(
                uint256(NORMALIZED_MAX), i, 99999999999999999999999999999999999999, -int256(uint256(i))
            );
        }
    }

    /// The max normalized value + 1 will be lossless because the least
    /// significant digit is 0.
    function testFromFixedDecimalLossyNormalizedMaxPlusOne() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            checkFromFixedDecimalLossless(uint256(NORMALIZED_MAX) + 1, i, 1e37, 1 - int256(uint256(i)));
        }
    }

    function testFromFixedDecimalLossyOverflow() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            // +2 because this produces a value that actually truncates to
            // something different to the original value.
            checkFromFixedDecimalLossy(uint256(NORMALIZED_MAX) + 2, i, 1e37, 1 - int256(uint256(i)));
        }
    }

    /// Any conversion where only 0 digits are truncated will be lossless.
    function testFromFixedDecimalLossyTruncateZero(uint256 value, uint8 decimals) external pure {
        uint256 scale = 0;
        while (value > uint256(NORMALIZED_MAX)) {
            value /= 10;
            scale++;
        }
        value *= 10 ** scale;

        (int256 signedCoefficient, int256 exponent, bool lossless) =
            LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        (signedCoefficient, exponent);
        assertEq(lossless, true, "lossless");

        // We can round trip cleanly as it is lossless.
        (uint256 valueOut, bool lossless1) = LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        assertEq(value, valueOut, "value");
        assertEq(lossless1, true, "lossless1");
    }

    /// Lossy conversion can round trip up to the limits of a normalized value.
    function testFromFixedDecimalLossyTruncateOne(uint256 value, uint8 decimals) external pure {
        uint256 scale = 0;

        // Truncate the value down here so that we can check it against the
        // lossy round trip.
        uint256 expectedValue = value;
        bool expectedLossless = true;
        while (expectedValue > uint256(NORMALIZED_MAX)) {
            uint256 nextValue = expectedValue / 10;
            if (nextValue * 10 != expectedValue) {
                expectedLossless = false;
            }
            expectedValue = nextValue;
            scale++;
        }
        expectedValue = expectedValue * 10 ** scale;

        // We can round trip in a lossy way.
        (int256 signedCoefficient, int256 exponent, bool lossless) =
            LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        (signedCoefficient, exponent);
        assertEq(lossless, expectedLossless, "lossless");

        // The return trip is lossless because we already truncated the value
        // (potentially) in the first step.
        (uint256 valueOut, bool lossless1) = LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        assertEq(expectedValue, valueOut, "value");
        assertEq(lossless1, true, "lossless1");
    }

    /// Converting a negative number back to a fixed point uint256 will revert.
    function testToFixedDecimalLossyNegative(int256 signedCoefficient, int256 exponent, uint8 decimals) external {
        signedCoefficient = bound(signedCoefficient, type(int256).min, -1);
        vm.expectRevert(abi.encodeWithSelector(NegativeFixedDecimalConversion.selector, signedCoefficient, exponent));
        (uint256 value, bool lossless) = LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        (value, lossless);
    }

    /// Converting any exponent and decimals for `0` is `0`.
    function testToFixedDecimalLossyZero(int256 exponent, uint8 decimals) external pure {
        (uint256 value, bool lossless) = LibDecimalFloat.toFixedDecimalLossy(0, exponent, decimals);
        assertEq(value, 0, "value");
        assertEq(lossless, true, "lossless");
    }

    /// If the exponent and decimals already match the conversion to decimal
    /// is simply identity on the coefficient.
    function testToFixedDecimalLossyIdentity(int256 signedCoefficient, uint8 decimals) external pure {
        signedCoefficient = bound(signedCoefficient, 0, type(int256).max);
        (uint256 value, bool lossless) =
            LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, -int256(uint256(decimals)), decimals);
        assertEq(value, uint256(signedCoefficient), "value");
        assertEq(lossless, true, "lossless");
    }

    /// Technically the exponent + decimals can overflow internally. This is
    /// an extreme edge case that is not expected to be hit by any real world
    /// use case. It MAY be attempted by an attacker for some reason, so we
    /// should revert on the overflow.
    function testToFixedDecimalLossyExponentOverflow(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
    {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        decimals = uint8(bound(decimals, 1, type(uint8).max));
        exponent = bound(exponent, type(int256).max - int256(uint256(decimals)) + 1, type(int256).max);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector));
        (uint256 value, bool lossless) = this.toFixedDecimalLossyExternal(signedCoefficient, exponent, decimals);
        (value, lossless);
    }

    /// If the final exponent is less than -77 then every value will be 0 when
    /// converted to fixed decimal.
    function testToFixedDecimalLossyUnderflow(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
        pure
    {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, type(int256).min, -78 - int256(uint256(decimals)));
        (uint256 value, bool lossless) = LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        assertEq(value, 0, "value");
        assertEq(lossless, false, "lossless");
    }

    /// If the final exponent is [-77, 0] then the value will be truncated
    /// according to the scale.
    function testToFixedDecimalLossyTruncate(int256 signedCoefficient, int256 exponent, uint8 decimals) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -77 - int256(uint256(decimals)), -int256(uint256(decimals)));
        (uint256 value, bool lossless) = LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        uint256 scale = 10 ** uint256(-(exponent + int256(uint256(decimals))));
        assertEq(value, uint256(signedCoefficient) / scale, "value");
        assertEq(lossless, value * scale == uint256(signedCoefficient), "lossless");
    }

    /// Some examples of lossless truncations.
    function testToFixedDecimalLossyTruncateLossless() external pure {
        checkToFixedDecimalLossless(123456789e37, -37, 0, 123456789);
        checkToFixedDecimalLossless(123456789e37, -37, 1, 1234567890);
        checkToFixedDecimalLossless(123456789e37, -37, 2, 12345678900);
        checkToFixedDecimalLossless(123456789e37, -37, 3, 123456789000);
        checkToFixedDecimalLossless(1e38, -38, 0, 1);
        checkToFixedDecimalLossless(1e38, -37, 0, 10);
    }

    /// If the final exponent is positive and does not overflow then the value
    /// will be scaled up losslessly.
    function testToFixedDecimalLosslessScaleUp(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
        pure
    {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        decimals = uint8(bound(decimals, 0, 77));
        exponent = int256(bound(exponent, 1 - int256(uint256(decimals)), 77 - int256(uint256(decimals))));

        int256 finalExponent = exponent + int256(uint256(decimals));
        uint256 scale = 10 ** uint256(finalExponent);

        uint256 unsignedCoefficient = uint256(signedCoefficient);
        unchecked {
            uint256 c = scale * unsignedCoefficient;
            vm.assume(c / scale == unsignedCoefficient);
        }

        checkToFixedDecimalLossless(signedCoefficient, exponent, decimals, unsignedCoefficient * scale);
    }

    /// If the final exponent is positive and too large it will overflow.
    function testToFixedDecimalLossyScaleUpOverflow(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
    {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = int256(bound(exponent, 1 - int256(uint256(decimals)), 77 - int256(uint256(decimals))));

        int256 finalExponent = exponent + int256(uint256(decimals));
        uint256 scale = 10 ** uint256(finalExponent);

        uint256 unsignedCoefficient = uint256(signedCoefficient);
        unchecked {
            uint256 c = scale * unsignedCoefficient;
            vm.assume(c / scale != unsignedCoefficient);
        }
        vm.expectRevert(stdError.arithmeticError);
        checkToFixedDecimalLossless(signedCoefficient, exponent, decimals, unsignedCoefficient * scale);
    }
}
