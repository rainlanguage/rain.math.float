// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, NegativeFixedDecimalConversion, Float} from "src/lib/LibDecimalFloat.sol";
import {FixedDecimalOverflow} from "src/error/ErrDecimalFloat.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatDecimalTest is Test {
    using LibDecimalFloat for Float;

    function toFixedDecimalLossyExternal(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
        pure
        returns (uint256, bool)
    {
        return LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
    }

    function toFixedDecimalLossyExternal(Float float, uint8 decimals) external pure returns (uint256, bool) {
        return float.toFixedDecimalLossy(decimals);
    }

    /// Unpacked, a value past int256.max sheds one digit, lossless iff it is
    /// zero. Packed, every value is the largest Float not above
    /// `value × 10^-decimals` (#332): `value` floored to the fewest digits shed
    /// that fit int224, or int224.max one digit lower where that is larger.
    /// It is lossless iff it is the value, and zero is `FLOAT_ZERO`.
    function testFromFixedDecimalLossyPacked(uint256 value, uint8 decimals) external pure {
        bool past = value > uint256(type(int256).max);
        (int256 signedCoefficient, int256 exponent, bool lossless) =
            LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(signedCoefficient, int256(past ? value / 10 : value), "signedCoefficient");
        assertEq(exponent, (past ? int256(1) : int256(0)) - int256(uint256(decimals)), "exponent");
        assertEq(lossless, !past || value % 10 == 0, "lossless");

        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 int224Max = uint256(int256(type(int224).max));
        uint256 coefficient = value;
        exponent = -int256(uint256(decimals));
        lossless = true;
        while (coefficient > int224Max) {
            lossless = lossless && coefficient % 10 == 0;
            coefficient /= 10;
            exponent++;
        }
        // Past int224, a digit lower holds int224.max, below the value there.
        if (exponent > -int256(uint256(decimals)) && coefficient * 10 < int224Max) {
            coefficient = int224Max;
            exponent--;
        }
        (Float float, bool floatLossless) = LibDecimalFloat.fromFixedDecimalLossyPacked(value, decimals);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 expected = coefficient == 0 ? bytes32(0) : bytes32(uint256(exponent) << 224 | coefficient);
        assertEq(Float.unwrap(float), expected, "float");
        assertEq(floatLossless, lossless, "packed lossless");
    }

    /// Memory version of to behaves same as stack version, and both match the
    /// exact `coefficient × 10^(exponent + decimals)`: a negative value
    /// reverts, a value at or above 2^256 overflows, and anything else is
    /// that value truncated, lossless iff nothing was truncated.
    function testToFixedDecimalLossyPacked(Float float, uint8 decimals) external {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        (bytes memory expectedError, uint256 expectedValue, bool expectedLossless) =
            LibTestExactDecimal.toFixedDecimal(signedCoefficient, exponent, decimals);
        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
            this.toFixedDecimalLossyExternal(signedCoefficient, exponent, decimals);
            vm.expectRevert(expectedError);
            this.toFixedDecimalLossyExternal(float, decimals);
            return;
        }
        (uint256 value, bool lossless) = this.toFixedDecimalLossyExternal(signedCoefficient, exponent, decimals);
        assertEq(value, expectedValue, "value");
        assertEq(lossless, expectedLossless, "lossless");
        (uint256 valueOut, bool losslessOut) = this.toFixedDecimalLossyExternal(float, decimals);
        assertEq(valueOut, expectedValue, "packed value");
        assertEq(losslessOut, expectedLossless, "packed lossless");
    }

    /// Round trip from/to decimal values. Past int256.max the value sheds its
    /// last digit on the way in, losslessly iff that digit is zero, and comes
    /// back without it; any other value comes back exactly.
    function testFixedDecimalRoundTripLossless(uint256 value, uint8 decimals) external pure {
        bool past = value > uint256(type(int256).max);
        (int256 signedCoefficient, int256 exponent, bool lossless0) =
            LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        assertEq(lossless0, !past || value % 10 == 0, "lossless0");

        (uint256 valueOut, bool lossless1) = LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        assertEq(valueOut, past ? value / 10 * 10 : value, "value");
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
            checkFromFixedDecimalLossless(1, i, 1, 0 - int256(uint256(i)));
        }
    }

    function testFromFixedDecimalLossyOneMillion() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            checkFromFixedDecimalLossless(1e6, i, 1e6, 0 - int256(uint256(i)));
        }
    }

    function testFromFixedDecimalLossyComplicated() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            checkFromFixedDecimalLossless(123456789, i, 123456789, 0 - int256(uint256(i)));
        }
    }

    /// The max int256 value will be lossless because there is no packing.
    function testFromFixedDecimalLossyMax() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            checkFromFixedDecimalLossless(uint256(type(int256).max), i, type(int256).max, -int256(uint256(i)));
        }
    }

    function testFromFixedDecimalLossyOverflow() external pure {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            // +2 because this produces a value that actually truncates to
            // something different to the original value.
            checkFromFixedDecimalLossy(uint256(1e77) + 2, i, 1e76, 1 - int256(uint256(i)));
        }
    }

    /// Any conversion where only 0 digits are truncated will be lossless.
    function testFromFixedDecimalLossyTruncateZero(uint256 value, uint8 decimals) external pure {
        uint256 scale = 0;
        while (value > type(uint224).max) {
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
        while (expectedValue > uint256(type(int256).max)) {
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
        (uint256 value, bool lossless) = this.toFixedDecimalLossyExternal(signedCoefficient, exponent, decimals);
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
        // signedCoefficient is bound to the non negative int256 range.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(value, uint256(signedCoefficient), "value");
        assertEq(lossless, true, "lossless");
    }

    /// `exponent + decimals` past int256.max is a value past uint256.max, so
    /// it is `FixedDecimalOverflow` like any other.
    function testToFixedDecimalLossyExponentSumWraps(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
    {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        decimals = uint8(bound(decimals, 1, type(uint8).max));
        exponent = bound(exponent, type(int256).max - int256(uint256(decimals)) + 1, type(int256).max);
        vm.expectRevert(abi.encodeWithSelector(FixedDecimalOverflow.selector, signedCoefficient, exponent, decimals));
        (uint256 value, bool lossless) = this.toFixedDecimalLossyExternal(signedCoefficient, exponent, decimals);
        (value, lossless);
    }

    /// If the final exponent is less than -77 then every value will be 0 when
    /// converted to fixed decimal.
    function testToFixedDecimalLossyUnderflow(int256 signedCoefficient, int256 exponent, uint8 decimals) external pure {
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
        // signedCoefficient is bound to the positive int256 range.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(value, uint256(signedCoefficient) / scale, "value");
        // signedCoefficient is bound to the positive int256 range.
        // forge-lint: disable-next-line(unsafe-typecast)
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
        // finalExponent [1, 77]
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 scale = 10 ** uint256(finalExponent);

        // signedCoefficient is bound to the int256 range.
        // forge-lint: disable-next-line(unsafe-typecast)
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
        // finalExponent [1, 77]
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 scale = 10 ** uint256(finalExponent);

        // signedCoefficient is bound to the int256 range.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 unsignedCoefficient = uint256(signedCoefficient);
        unchecked {
            uint256 c = scale * unsignedCoefficient;
            vm.assume(c / scale != unsignedCoefficient);
        }
        vm.expectRevert(abi.encodeWithSelector(FixedDecimalOverflow.selector, signedCoefficient, exponent, decimals));
        (uint256 value, bool lossless) = this.toFixedDecimalLossyExternal(signedCoefficient, exponent, decimals);
        (value, lossless);
    }
}
