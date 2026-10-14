// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibDecimalFloatImplementation,
    LOG10_SKIP_BELOW
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LOG10_RAW_ERROR_E54} from "test/lib/LibTestErrorBound.sol";
import {Log10Zero, Log10Negative, ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {LibExactFloat} from "../../../lib/LibExactFloat.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";

/// @dev log10 of 1448249443771554926630073670106315934706894775468672318138123474693615199258e-75
/// in units of 1e-76, from `bc -l` at scale 130, truncated.
int256 constant LOG10_LOW_REFERENCE = 1608433703718606718793125938541044383025292167608499987887200895753204303698;

/// @dev log10 of 9999453323501747426601859962676171576268035899274424060577868894318634900000e-75
/// in units of 1e-76, from `bc -l` at scale 130, truncated.
int256 constant LOG10_HIGH_REFERENCE = 9999762574923628115885758764340189836032549999999900009999999999999884820384;

/// `log10Unrounded` against the oracle, which is within 1e-67, and its proven
/// `LOG10_RAW_ERROR_E54` units of 1e-54, and where `add` sums the
/// characteristic, exactly the sum's truncation toward zero.
contract LibDecimalFloatImplementationLog10UnroundedTest is Test {
    function log10UnroundedExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
    }

    function abs(int256 value) internal pure returns (int256) {
        return value < 0 ? -value : value;
    }

    /// Whether |actual - oracle| is within the bound terms, exactly.
    function withinOracle(
        int256 signedCoefficient,
        int256 exponent,
        int256 actualCoefficient,
        int256 actualExponent,
        int256[] memory boundCoefficients,
        int256[] memory boundExponents
    ) internal pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibExactFloat.log10(uint256(signedCoefficient), exponent);
        int256[] memory coefficients = new int256[](3);
        int256[] memory exponents = new int256[](3);
        (coefficients[0], exponents[0]) = (actualCoefficient, actualExponent);
        (coefficients[1], exponents[1]) = (-characteristic, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        (coefficients[2], exponents[2]) = (-int256(fraction), -70);
        return LibExactFloat.absSumLte(coefficients, exponents, boundCoefficients, boundExponents);
    }

    /// How far the documented characteristic is above the exponent: the
    /// floor of the log, digits - 1, or one more within a factor 1.001 below
    /// the next power of ten, where 1001 c >= 10^(digits + 3).
    function characteristicRise(int256 signedCoefficient) internal pure returns (int256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 magnitude = uint256(signedCoefficient);
        int256 digits = LibExactFloat.digits(LibExactFloat.u512(magnitude));
        bool roundsUp =
            LibExactFloat.cmpScaled(LibExactFloat.mul(magnitude, 1001), 0, LibExactFloat.u512(1), digits + 3) >= 0;
        return digits - 1 + (roundsUp ? int256(1) : int256(0));
    }

    /// `value / 1e20` rounded toward negative infinity.
    function floorE20(int256 value) internal pure returns (int256) {
        int256 quotient = value / 1e20;
        return value < 0 && value % 1e20 != 0 ? quotient - 1 : quotient;
    }

    /// Whether `(c, e)` is `log10Unrounded` of the input within its proven
    /// bound. For a characteristic k other than zero the result is `add` of
    /// k and a correction 10^-50 within `LOG10_RAW_ERROR_E54` units of 1e-54
    /// of the log less k, below 1e25 by a fixed point sum that is exact, as
    /// `add` is there. The oracle is within 1e-67, so the correction is one of
    /// the integers within both errors of it, and the result is
    /// `LibExactFloat.addPartsWide` of k and that correction, which truncates toward
    /// zero to k's int256 unit and sheds one more digit where the sum passes
    /// int256. Zero k is the correction alone, which may be relative.
    function absoluteOk(int256 signedCoefficient, int256 exponent, int256 c, int256 e) internal pure returns (bool) {
        int256 k = exponent + characteristicRise(signedCoefficient);
        if (k != 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            (int256 characteristic, uint256 fraction) = LibExactFloat.log10(uint256(signedCoefficient), exponent);
            // The oracle's characteristic is within one of k.
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 offset = (characteristic - k) * 1e70 + int256(fraction);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 slack = int256(LOG10_RAW_ERROR_E54) * 1e16 + 1e3;
            // The span is 2.0074e-50, so at most three corrections.
            int256 highCorrection = floorE20(offset + slack);
            for (int256 correction = -floorE20(slack - offset); correction <= highCorrection; correction++) {
                // Exponents 0 and -50 cannot overflow the result exponent.
                (, int256 expectedCoefficient, int256 expectedExponent) =
                    LibExactFloat.addPartsWide(k, 0, correction, -50);
                if (LibExactFloat.cmpParts(c, e, expectedCoefficient, expectedExponent) == 0) {
                    return true;
                }
            }
            return false;
        }
        int256[] memory boundCoefficients = new int256[](2);
        int256[] memory boundExponents = new int256[](2);
        // forge-lint: disable-next-line(unsafe-typecast)
        (boundCoefficients[0], boundExponents[0]) = (int256(LOG10_RAW_ERROR_E54), -54);
        (boundCoefficients[1], boundExponents[1]) = (1, -67);
        return withinOracle(signedCoefficient, exponent, c, e, boundCoefficients, boundExponents);
    }

    function checkAbsolute(int256 signedCoefficient, int256 exponent) internal pure {
        (int256 c, int256 e) = LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        assertTrue(absoluteOk(signedCoefficient, exponent, c, e), "log10Unrounded error");
    }

    /// Within a factor 1.001 of 1 the log is all correction and the error is
    /// under 3.11e-49 of it.
    function checkRelative(int256 signedCoefficient, int256 exponent) internal pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibExactFloat.log10(uint256(signedCoefficient), exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expected = characteristic * 1e70 + int256(fraction);
        int256[] memory boundCoefficients = new int256[](2);
        int256[] memory boundExponents = new int256[](2);
        (boundCoefficients[0], boundExponents[0]) = (abs(expected) * 311, -121);
        (boundCoefficients[1], boundExponents[1]) = (1, -67);
        (int256 c, int256 e) = LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        assertTrue(
            withinOracle(signedCoefficient, exponent, c, e, boundCoefficients, boundExponents),
            "log10Unrounded relative error"
        );
    }

    function checkExact(int256 signedCoefficient, int256 exponent, int256 expected) internal pure {
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        assertEq(actualCoefficient, expected, "coefficient");
        assertEq(actualExponent, 0, "exponent");
    }

    function testLog10UnroundedPowersOfTen() external pure {
        checkExact(1, 0, 0);
        checkExact(1, -1, -1);
        checkExact(10, 5, 6);
        checkExact(1e75, 0, 75);
        checkExact(1e76, -76, 0);
        checkExact(1e76, 1e30, 1e30 + 76);
    }

    /// Within 75 of the floor the shift the exponent cannot take is the
    /// shortfall, and the log is still exact.
    function testLog10UnroundedPowersOfTenAtFloor() external pure {
        int256 min = type(int256).min;
        checkExact(1, min, min);
        checkExact(10, min, min + 1);
        checkExact(1, min + 74, min + 74);
        checkExact(1, min + 75, min + 75);
    }

    function testLog10UnroundedZero() external {
        vm.expectRevert(abi.encodeWithSelector(Log10Zero.selector));
        this.log10UnroundedExternal(0, 5);
    }

    /// The revert carries the input, not its maximized form.
    function testLog10UnroundedNegative() external {
        vm.expectRevert(abi.encodeWithSelector(Log10Negative.selector, int256(-3), int256(7)));
        this.log10UnroundedExternal(-3, 7);
        vm.expectRevert(abi.encodeWithSelector(Log10Negative.selector, int256(-1e70), int256(-2)));
        this.log10UnroundedExternal(-1e70, -2);
    }

    /// Either side of each 1.001 edge, near 1 where the seed is exact and
    /// with a characteristic where it is not. 1.001e75 and `LOG10_SKIP_BELOW`
    /// are within a factor 1.001 of a power of ten, and 1.001e76 too for a
    /// 77 digit coefficient.
    function testLog10UnroundedTableEdges() external pure {
        int256[6] memory edges =
            [int256(1.001e75), 1.001e75 + 1, LOG10_SKIP_BELOW - 1, LOG10_SKIP_BELOW, 1.001e76, 1.001e76 + 1];
        for (uint256 i = 0; i < edges.length; i++) {
            checkAbsolute(edges[i], -75);
            checkAbsolute(edges[i], -76);
            checkAbsolute(edges[i], -70);
            checkAbsolute(edges[i], 3);
        }
        checkRelative(1.001e75, -75);
        checkRelative(1001, -3);
        checkRelative(LOG10_SKIP_BELOW, -76);
        checkRelative(1.001e76, -76);
    }

    /// #484: below 1, from 1 / 1.001 to 0.9999, each 40x to 550x past the
    /// relative bound when it was reduced, and either side of 1 within one
    /// unit of the coefficient.
    function testLog10UnroundedRelativeExamples() external pure {
        checkRelative(9.995e75, -76);
        checkRelative(9.9901e75, -76);
        checkRelative(9.999e75 - 1, -76);
        checkRelative(9995, -4);
        checkRelative(1e75 + 1, -75);
        checkRelative(1e76 - 1, -76);
        checkRelative(1e76 + 1, -76);
    }

    function testLog10UnroundedRelativeAbove(int256 signedCoefficient) external pure {
        signedCoefficient = bound(signedCoefficient, 1e75 + 1, 1.001e75);
        checkRelative(signedCoefficient, -75);
    }

    function testLog10UnroundedRelativeBelow(int256 signedCoefficient) external pure {
        signedCoefficient = bound(signedCoefficient, LOG10_SKIP_BELOW, 1e76 - 1);
        checkRelative(signedCoefficient, -76);
    }

    /// A 77 digit coefficient up to 1.001e76 keeps every digit.
    function testLog10UnroundedRelativeAbove77Digits(int256 signedCoefficient) external pure {
        signedCoefficient = bound(signedCoefficient, 1e76 + 1, 1.001e76);
        checkRelative(signedCoefficient, -76);
    }

    /// 1.000878 has z about 4.39e-4, where the atanh series' z^14 term is
    /// just under 1000 units of 1e-50 and still moves the log by more than its
    /// relative bound.
    function testLog10UnroundedRelativeSeriesTail() external pure {
        checkRelative(1000878e69, -75);
    }

    /// Either side of the 1e25 characteristic where `add` takes over, and
    /// past where the fixed point sum would overflow.
    function testLog10UnroundedLargeCharacteristic() external pure {
        checkAbsolute(2, 1e25 - 1);
        checkAbsolute(2, 1e25);
        checkAbsolute(2, 9e26);
        checkAbsolute(2, -1e25 + 1);
        checkAbsolute(2, -1e25);
        checkAbsolute(2, -9e26);
        checkAbsolute(31415926535, 1e40);
    }

    /// #699: 578960446186580977117854925 is the largest k with k 1e50 in
    /// int256, and 5789604461865809771178549250 the largest with k 1e49, each
    /// 0.0434 under `type(int256).max` at that unit, so log10 3 = 0.47712...
    /// carries and `add` sheds a digit: the sum truncated toward zero to 1e-49
    /// and 1e-48. 57896044618658097711785492 1e51 is 0.5043 under it, so
    /// log10 4 = 0.60206... carries to 1e-50, where the correction is exact.
    /// Each coefficient is k plus log10 3 or log10 4 from `bc -l` at scale
    /// 120, truncated. The first value past the bound on each side is
    /// rejected: one unit less, and above, two units more where two
    /// corrections map to adjacent grid points, else one.
    function testLog10UnroundedAddCarry() external pure {
        int256[2][3] memory inputs = [
            [int256(3), 578960446186580977117854925],
            [int256(3), 5789604461865809771178549250],
            [int256(4), 57896044618658097711785492]
        ];
        int256[2][3] memory expected = [
            [int256(5789604461865809771178549254771212547196624372950279032551153092001288641906), -49],
            [int256(5789604461865809771178549250477121254719662437295027903255115309200128864190), -48],
            [int256(5789604461865809771178549260205999132796239042747778944898605353637976292421), -50]
        ];
        int256[3] memory above = [int256(2), 1, 2];
        for (uint256 i = 0; i < inputs.length; i++) {
            (int256 c, int256 e) = LibDecimalFloatImplementation.log10Unrounded(inputs[i][0], inputs[i][1]);
            assertEq(c, expected[i][0], "coefficient");
            assertEq(e, expected[i][1], "exponent");
            assertTrue(absoluteOk(inputs[i][0], inputs[i][1], c, e), "log10Unrounded error");
            assertFalse(absoluteOk(inputs[i][0], inputs[i][1], c - 1, e), "one unit below");
            for (int256 j = 1; j < above[i]; j++) {
                assertTrue(absoluteOk(inputs[i][0], inputs[i][1], c + j, e), "within bound above");
            }
            assertFalse(absoluteOk(inputs[i][0], inputs[i][1], c + above[i], e), "past bound above");
        }
    }

    /// A characteristic within two of the largest magnitude k with k 10^s in
    /// int256, either sign: for s from 1 to 51 `add` sums it and sheds a
    /// digit where a correction past the gap takes the sum past int256, and
    /// at s = 52, just under 1e25, the fixed point sum takes over.
    function testLog10UnroundedOracleCarryEdge(int256 signedCoefficient, uint256 shift, uint256 below, bool negative)
        external
        pure
    {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        shift = bound(shift, 1, 52);
        below = bound(below, 0, 2);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** shift);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 k = negative ? type(int256).min / scale + int256(below) : type(int256).max / scale - int256(below);
        checkAbsolute(signedCoefficient, k - characteristicRise(signedCoefficient));
    }

    function testLog10UnroundedOracle(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -200, 200);
        checkAbsolute(signedCoefficient, exponent);
    }

    function testLog10UnroundedOracleLargeExponent(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -1e40, 1e40);
        checkAbsolute(signedCoefficient, exponent);
    }

    /// Near the floor, and within 75 of it where the exponent cannot take the
    /// whole shift, any coefficient is within the oracle. The oracle's
    /// characteristic is negated, so it starts one above int256.min.
    function testLog10UnroundedOracleAtFloor(int256 signedCoefficient, int256 room) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        room = bound(room, 1, 160);
        checkAbsolute(signedCoefficient, type(int256).min + room);
    }

    /// #422: (2e75, int256.max) panicked. The characteristic reaches
    /// int256.max exactly at 10^int256.max, by each of the coefficient's
    /// paths: scaled up, in place, past 1e76, and rounded up to the next
    /// power of ten from `LOG10_SKIP_BELOW`, for 76 digits and for 77 up to
    /// 1.001e76. The reduced path keeps the characteristic at int256.max with
    /// a log just under int256.max + 1.
    function testLog10UnroundedCharacteristicCeiling() external pure {
        int256 max = type(int256).max;
        checkExact(1, max, max);
        checkExact(1e75, max - 75, max);
        checkExact(1e76, max - 76, max);
        checkAbsolute(LOG10_SKIP_BELOW, max - 76);
        checkAbsolute(1e76 - 1, max - 76);
        checkAbsolute(1.001e76, max - 76);
        checkAbsolute(1.001e76 + 1, max - 76);
        checkAbsolute(LOG10_SKIP_BELOW - 1, max - 75);
    }

    /// A characteristic one past int256.max, on each path above, reverts
    /// `ExponentOverflow` with the input.
    function testLog10UnroundedCharacteristicOverflow() external {
        int256 max = type(int256).max;
        int256[2][9] memory inputs = [
            [int256(10), max],
            [int256(2e75), max],
            [int256(1e75), max - 74],
            [int256(1e76), max - 75],
            [LOG10_SKIP_BELOW, max - 75],
            [int256(1e76 - 1), max - 75],
            [int256(1.001e76), max - 75],
            [int256(1.001e76 + 1), max - 75],
            [type(int256).max, max]
        ];
        for (uint256 i = 0; i < inputs.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, inputs[i][0], inputs[i][1]));
            this.log10UnroundedExternal(inputs[i][0], inputs[i][1]);
        }
    }

    /// The characteristic passes int256.max exactly when the exponent plus
    /// `characteristicRise` does.
    function testLog10UnroundedCharacteristicOverflowFuzz(int256 signedCoefficient, int256 room) external {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        room = bound(room, 0, 160);
        int256 exponent = type(int256).max - room;
        if (characteristicRise(signedCoefficient) <= room) {
            checkAbsolute(signedCoefficient, exponent);
        } else {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
            this.log10UnroundedExternal(signedCoefficient, exponent);
        }
    }

    /// The floor of the log from the int256 floor up, where the characteristic
    /// alone sets the int256 unit of `add`'s sum, as at the ceiling above.
    function testLog10UnroundedOracleFloor(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, type(int256).min, type(int256).min + 80);
        checkAbsolute(signedCoefficient, exponent);
    }

    /// #483: log10 2 is 0.30103 from `bc -l`, so 2 10^k has log k + 0.30103,
    /// which `add` truncates toward zero to k + 1 for a negative k and to k
    /// for a positive one.
    function testLog10UnroundedTruncatesAtLimits() external pure {
        int256 min = type(int256).min;
        int256 max = type(int256).max;
        checkExact(2, min, min + 1);
        checkExact(2, min + 1, min + 2);
        checkExact(2, max - 1, max - 1);
        checkExact(2, max, max);
        checkAbsolute(2, min);
        checkAbsolute(9, min);
    }

    /// `absoluteOk` takes only the truncation toward zero, not the integer
    /// either side of it, at both limits.
    function testLog10UnroundedAbsoluteRejectsNeighbours() external pure {
        int256 min = type(int256).min;
        int256 max = type(int256).max;
        assertTrue(absoluteOk(2, min + 1, min + 2, 0), "floor truncation");
        assertFalse(absoluteOk(2, min + 1, min + 1, 0), "floor below");
        assertFalse(absoluteOk(2, min + 1, min + 3, 0), "floor above");
        assertTrue(absoluteOk(2, max - 1, max - 1, 0), "ceiling truncation");
        assertFalse(absoluteOk(2, max - 1, max - 2, 0), "ceiling below");
        assertFalse(absoluteOk(2, max - 1, max, 0), "ceiling above");
    }

    /// The raw log of 1.4482...e0 is 0.99988e-50 below its log from `bc -l`
    /// at scale 130 truncated to 76 places, and of 9.9994...e0 0.9999e-50
    /// above. Each is within `LOG10_RAW_ERROR_E54` and reaches 99.5% of it,
    /// so that bound can be neither lowered past them nor raised by 0.5%.
    function testLog10UnroundedRawErrorReached() external pure {
        int256[2][2] memory references = [
            [int256(1448249443771554926630073670106315934706894775468672318138123474693615199258), LOG10_LOW_REFERENCE],
            [int256(9999453323501747426601859962676171576268035899274424060577868894318634900000), LOG10_HIGH_REFERENCE]
        ];
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 bound = int256(LOG10_RAW_ERROR_E54) * 1e22;
        for (uint256 i = 0; i < references.length; i++) {
            (int256 rawCoefficient, int256 rawExponent) =
                LibDecimalFloatImplementation.log10Unrounded(references[i][0], -75);
            assertGe(rawExponent, -76, "exponent");
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 error = abs(rawCoefficient * int256(10 ** uint256(rawExponent + 76)) - references[i][1]);
            assertLe(error, bound + 1, "within the bound");
            assertGe(error * 1000, bound * 995, "bound tight");
        }
    }
}
