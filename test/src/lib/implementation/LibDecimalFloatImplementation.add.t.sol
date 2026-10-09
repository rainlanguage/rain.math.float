// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    ExponentOverflow,
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    ADD_MAX_EXPONENT_DIFF
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibDecimalFloatImplementationAddPre394} from "test/lib/LibDecimalFloatImplementationAddPre394.sol";

contract LibDecimalFloatImplementationAddTest is Test {
    function addExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256 signedCoefficient, int256 exponent)
    {
        return LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function willOverflow(int256 a, int256 b) internal pure returns (bool) {
        unchecked {
            if (a > 0 && b > 0) {
                return a > type(int256).max - b;
            } else if (a < 0 && b < 0) {
                return a < type(int256).min - b;
            } else {
                return false; // No overflow if signs are different.
            }
        }
    }

    /// This is copypasta from the internals of add.
    function willOverflow2(int256 a, int256 b) internal pure returns (bool didOverflow) {
        unchecked {
            int256 c = a + b;
            assembly ("memory-safe") {
                let sameSignAB := iszero(shr(0xff, xor(a, b)))
                let sameSignAC := iszero(shr(0xff, xor(a, c)))
                didOverflow := and(sameSignAB, iszero(sameSignAC))
            }
        }
    }

    function testOverflowChecks(int256 a, int256 b) external pure {
        bool expected = willOverflow(a, b);
        bool actual = willOverflow2(a, b);
        assertEq(actual, expected, "Overflow check mismatch");
    }

    function checkAdd(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(exponent, expectedExponent, "exponent mismatch");
    }

    /// Simple 0 add 0
    /// 0 + 0 = 0
    function testAddZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(0, 0, 0, 0);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, 0);
    }

    /// 0 add 0 any exponent
    /// 0 + 0 = 0
    function testAddZeroAnyExponent(int128 inputExponent) external pure {
        inputExponent = int128(bound(inputExponent, EXPONENT_MIN, EXPONENT_MAX));
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(0, inputExponent, 0, 0);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, 0);
    }

    /// 0 add 1
    /// 0 + 1 = 1
    function testAddZeroOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(0, 0, 1, 0);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);
    }

    /// 1 add 0
    /// 1 + 0 = 1
    function testAddOneZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(1, 0, 0, 0);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);
    }

    /// 1 add 1
    /// 1 + 1 = 2
    function testAddOneOneNotMaximized() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(1, 0, 1, 0);
        assertEq(signedCoefficient, 2e76, "Signed coefficient mismatch");
        assertEq(exponent, -76, "Exponent mismatch");
    }

    function testAddOneOnePreMaximized() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(1e76, -76, 1e76, -76);
        assertEq(signedCoefficient, 2e76);
        assertEq(exponent, -76);
    }

    /// 123456789 add 987654321
    /// 123456789 + 987654321 = 1111111110
    function testAdd123456789987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(123456789, 0, 987654321, 0);
        assertEq(signedCoefficient, 1.11111111e76);
        assertEq(exponent, -76 + 9);
    }

    /// 123456789e9 add 987654321
    /// 123456789e9 + 987654321 = 123456789987654321
    function testAdd123456789e9987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(123456789, 9, 987654321, 0);
        assertEq(signedCoefficient, 1.23456789987654321e76);
        assertEq(exponent, -76 + 17);
    }

    function testGasAddZero() external pure {
        LibDecimalFloatImplementation.add(0, 0, 0, 0);
    }

    function testGasAddOne() external pure {
        LibDecimalFloatImplementation.add(1e37, -37, 1e37, -37);
    }

    function testAddRevertMaxA() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, type(int256).max, type(int256).max));
        this.addExternal(type(int256).max, type(int256).max, 1, type(int256).max);
    }

    /// Provided our exponents are in range we should never revert.
    function testAddNeverRevert(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (signedCoefficient, exponent);
    }

    function testAddingSmallToLargeReturnsLargeFuzz(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) public pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        vm.assume(signedCoefficientA != 0);
        vm.assume(signedCoefficientB != 0);

        (int256 normalizedSignedCoefficientA, int256 normalizedExponentA) =
            LibDecimalFloatImplementation.maximizeFull(signedCoefficientA, exponentA);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.maximizeFull(signedCoefficientB, exponentB);

        vm.assume(normalizedSignedCoefficientA != 0);
        vm.assume(expectedSignedCoefficient != 0);

        // ADD_MAX_EXPONENT_DIFF = 76
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.assume((expectedExponent - normalizedExponentA) > int256(ADD_MAX_EXPONENT_DIFF));

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }

    function testAddingSmallToLargeReturnsLargeExamples() external pure {
        // Establish a baseline.
        checkAdd(1e37, 0, 1e37, -37, 10000000000000000000000000000000000001e39, -39);
        // Show baseline with reversed order.
        checkAdd(1e37, -37, 1e37, 0, 10000000000000000000000000000000000001e39, -39);

        // Show full precision loss.
        checkAdd(1e37, 0, 1e37, -38, 100000000000000000000000000000000000001e38, -39);
        checkAdd(1e37, 0, 1e37, -75, 10000000000000000000000000000000000000000000000000000000000000000000000000010, -39);
        checkAdd(1e38, 0, 1e37, -76, 1e76, -38);
        checkAdd(1e37, 0, 1e37, -76, 10000000000000000000000000000000000000000000000000000000000000000000000000001, -39);
        // Show same thing again with reversed order.
        checkAdd(1e37, -38, 1e37, 0, 100000000000000000000000000000000000001e38, -39);
        checkAdd(1e37, -75, 1e37, 0, 10000000000000000000000000000000000000000000000000000000000000000000000000010, -39);
        checkAdd(1e37, -76, 1e37, 0, 10000000000000000000000000000000000000000000000000000000000000000000000000001, -39);

        // Same precision loss happens for negative numbers.
        checkAdd(-1e37, 0, -1e37, -38, -100000000000000000000000000000000000001e38, -39);
        checkAdd(
            -1e37, 0, -1e37, -75, -10000000000000000000000000000000000000000000000000000000000000000000000000010, -39
        );
        checkAdd(
            -1e37, 0, -1e37, -76, -10000000000000000000000000000000000000000000000000000000000000000000000000001, -39
        );
        // Reverse order.
        checkAdd(-1e37, -38, -1e37, 0, -100000000000000000000000000000000000001e38, -39);
        checkAdd(
            -1e37, -75, -1e37, 0, -10000000000000000000000000000000000000000000000000000000000000000000000000010, -39
        );
        checkAdd(
            -1e37, -76, -1e37, 0, -10000000000000000000000000000000000000000000000000000000000000000000000000001, -39
        );

        // Only the difference in exponents matters. Show the baseline.
        checkAdd(1e37, -20, 1e37, -57, 10000000000000000000000000000000000001e39, -59);
        checkAdd(
            1e37, -20, 1e37, -95, 10000000000000000000000000000000000000000000000000000000000000000000000000010, -59
        );
        checkAdd(
            1e37, -20, 1e37, -96, 10000000000000000000000000000000000000000000000000000000000000000000000000001, -59
        );
        checkAdd(1e37, -20, 1e37, -97, 1e76, -59);
        // Reverse order.
        checkAdd(1e37, -57, 1e37, -20, 10000000000000000000000000000000000001e39, -59);
        checkAdd(
            1e37, -95, 1e37, -20, 10000000000000000000000000000000000000000000000000000000000000000000000000010, -59
        );
        checkAdd(
            1e37, -96, 1e37, -20, 10000000000000000000000000000000000000000000000000000000000000000000000000001, -59
        );
        checkAdd(1e37, -97, 1e37, -20, 1e76, -59);

        // Show the same thing with negative numbers.
        checkAdd(-1e37, -20, -1e37, -57, -10000000000000000000000000000000000001e39, -59);
        checkAdd(
            -1e37, -20, -1e37, -95, -10000000000000000000000000000000000000000000000000000000000000000000000000010, -59
        );
        checkAdd(
            -1e37, -20, -1e37, -96, -10000000000000000000000000000000000000000000000000000000000000000000000000001, -59
        );
        checkAdd(-1e37, -20, -1e37, -97, -1e76, -59);

        // Reverse order.
        checkAdd(-1e37, -57, -1e37, -20, -10000000000000000000000000000000000001e39, -59);
        checkAdd(
            -1e37, -95, -1e37, -20, -10000000000000000000000000000000000000000000000000000000000000000000000000010, -59
        );
        checkAdd(
            -1e37, -96, -1e37, -20, -10000000000000000000000000000000000000000000000000000000000000000000000000001, -59
        );
        checkAdd(-1e37, -97, -1e37, -20, -1e76, -59);

        // Suspicious values flagged in fuzzing elsewhere.
        checkAdd(54304950862250382, -16, 1e76, -76, 6.4304950862250382e75, -75);
    }

    /// If the exponents are the same then addition is simply adding the
    /// coefficients.
    function testAddSameExponent(int256 signedCoefficientA, int256 signedCoefficientB) external pure {
        int256 exponentA;
        int256 exponentB;
        int256 signedCoefficientAMaximized;
        int256 signedCoefficientBMaximized;
        (signedCoefficientAMaximized, exponentA) = LibDecimalFloatImplementation.maximizeFull(signedCoefficientA, 0);
        (signedCoefficientBMaximized, exponentB) = LibDecimalFloatImplementation.maximizeFull(signedCoefficientB, 0);

        if (signedCoefficientA == 0 || signedCoefficientB == 0) {
            exponentA = 0;
        }
        exponentB = exponentA;

        int256 expectedSignedCoefficient;
        unchecked {
            expectedSignedCoefficient = signedCoefficientAMaximized + signedCoefficientBMaximized;
            // We aren't testing the overflow case in this test.
            vm.assume(!willOverflow(signedCoefficientAMaximized, signedCoefficientBMaximized));
        }
        int256 expectedExponent = exponentA;

        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(
            signedCoefficientAMaximized, exponentA, signedCoefficientBMaximized, exponentB
        );

        assertEq(signedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(exponent, expectedExponent, "exponent mismatch");
    }

    /// a + b == b + a for all in-range inputs (compared via eq, since zero
    /// can have different exponent representations).
    function testAddCommutative(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        (int256 coeffAB, int256 expAB) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 coeffBA, int256 expBA) =
            LibDecimalFloatImplementation.add(signedCoefficientB, exponentB, signedCoefficientA, exponentA);

        assertTrue(LibDecimalFloatImplementation.eq(coeffAB, expAB, coeffBA, expBA), "add not commutative");
    }

    /// Adding any zero to any value returns the non-zero value.
    function testAddZeroToAnyNonZero(int256 exponentZero, int256 signedCoefficient, int256 exponent) external pure {
        exponentZero = bound(exponentZero, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponent = bound(exponent, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        vm.assume(signedCoefficient != 0);

        (int256 expectedSignedCoefficient, int256 expectedExponent) = (signedCoefficient, exponent);
        (int256 signedCoefficientAddZero, int256 exponentAddZero) =
            LibDecimalFloatImplementation.add(0, exponentZero, signedCoefficient, exponent);
        assertEq(signedCoefficientAddZero, expectedSignedCoefficient);
        assertEq(exponentAddZero, expectedExponent);

        // Reverse order.
        (signedCoefficientAddZero, exponentAddZero) =
            LibDecimalFloatImplementation.add(signedCoefficient, exponent, 0, exponentZero);
        assertEq(signedCoefficientAddZero, expectedSignedCoefficient);
        assertEq(exponentAddZero, expectedExponent);
    }

    /// Operands too close to `type(int256).min` to take their full shift add
    /// exactly when the sum fits at the floor.
    function testAddAtFloor() external pure {
        int256 min = type(int256).min;
        checkAdd(1, min, 1, min, 2, min);
        checkAdd(1, min, -1, min, 0, min);
        checkAdd(1, min, 1, min + 1, 11, min);
        checkAdd(1, min + 1, 1, min, 11, min);
        checkAdd(-1, min, 1, min + 76, 1e76 - 1, min);
        // The sum overflows the maximized coefficients, so one digit fewer is
        // shed.
        checkAdd(5e75, min, 5e75, min, 1e76, min);
        // The smaller operand's last digit lands on the 77th digit, then past
        // it, where the larger operand is returned unchanged.
        checkAdd(1e76, min, 1, min, 1e76 + 1, min);
        checkAdd(1e76, min + 1, 1, min, 1e76, min + 1);
    }

    /// Near the floor, the sum is the sum of the same operands shifted up by
    /// `-type(int256).min`, truncated to the floor.
    function testAddNearFloorMatchesShifted(
        int256 signedCoefficientA,
        int256 signedCoefficientB,
        uint256 headroomA,
        uint256 headroomB
    ) external pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentA = int256(bound(headroomA, 0, 80));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentB = int256(bound(headroomB, 0, 80));
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        if (expectedExponent < 0) {
            expectedCoefficient =
                LibDecimalFloatImplementation.withTargetExponent(expectedCoefficient, expectedExponent, 0);
            expectedExponent = 0;
        }
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(
            signedCoefficientA, type(int256).min + exponentA, signedCoefficientB, type(int256).min + exponentB
        );
        assertTrue(
            LibDecimalFloatImplementation.eq(
                signedCoefficient, exponent - type(int256).min, expectedCoefficient, expectedExponent
            ),
            "shifted sum"
        );
    }

    /// `add` returns the parts its NatSpec states for any int256 parts, and
    /// reverts `ExponentOverflow` where their exponent is past int256.
    function checkAddExact(int256 a, int256 ea, int256 b, int256 eb) internal view {
        (bool overflows, int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.addPartsWide(a, ea, b, eb);
        try this.addExternal(a, ea, b, eb) returns (int256 signedCoefficient, int256 exponent) {
            assertFalse(overflows, "exact sum overflows");
            assertEq(signedCoefficient, expectedSignedCoefficient, "exact coefficient");
            assertEq(exponent, expectedExponent, "exact exponent");
        } catch (bytes memory err) {
            assertTrue(overflows, "exact sum returns");
            assertEq(bytes4(err), ExponentOverflow.selector, "ExponentOverflow");
        }
    }

    /// `c` with its last `shift % 78` digits dropped.
    function digits(int256 c, uint8 shift) internal pure returns (int256) {
        return c / int256(10 ** (uint256(shift) % 78));
    }

    /// #394: past int256 the sum sheds its own last digit, so the last digits
    /// of the operands carry. `2 × int256.max` and `2 × int256.min` are
    /// `±(2^256 - 2)` and `-2^256`, both `±1157…963993` tens.
    function testAddOverflowKeepsCarry() external view {
        int256 max = type(int256).max;
        int256 min = type(int256).min;
        checkAdd(max, 0, max, 0, 11579208923731619542357098500868790785326998466564056403945758400791312963993, 1);
        checkAdd(min, 0, min, 0, -11579208923731619542357098500868790785326998466564056403945758400791312963993, 1);
        checkAdd(max, 0, 9, 0, 5789604461865809771178549250434395392663499233282028201972879200395656481997, 1);
        checkAdd(min, 0, -9, 0, -5789604461865809771178549250434395392663499233282028201972879200395656481997, 1);
        checkAdd(-9, 0, min, 0, -5789604461865809771178549250434395392663499233282028201972879200395656481997, 1);
        checkAddExact(max, 0, max, 0);
        checkAddExact(min, 0, min, 0);
        checkAddExact(max, 0, 9, 0);
        checkAddExact(min, 0, -9, 0);
        checkAddExact(min, 0, max, 0);
        checkAddExact(min, 0, min, 1);
        checkAddExact(min, min, min, min);
        checkAddExact(min, max, min, max);
    }

    function testAddMatchesExact(int256 a, int256 ea, int256 b, int256 eb, uint8 sa, uint8 sb) external view {
        checkAddExact(digits(a, sa), ea, digits(b, sb), eb);
    }

    /// Exponents close enough that the sum can carry past int256.
    function testAddNearbyMatchesExact(int256 a, int256 ea, int256 b, uint256 gap, uint8 sa, uint8 sb) external view {
        ea = bound(ea, type(int256).min + 80, type(int256).max);
        // forge-lint: disable-next-line(unsafe-typecast)
        checkAddExact(digits(a, sa), ea, digits(b, sb), ea - int256(bound(gap, 0, 80)));
    }

    /// Exponents at or near the floor, where the sum sheds what it cannot
    /// hold.
    function testAddNearFloorMatchesExact(int256 a, uint256 ea, int256 b, uint256 eb, uint8 sa, uint8 sb)
        external
        view
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentA = type(int256).min + int256(bound(ea, 0, 160));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentB = type(int256).min + int256(bound(eb, 0, 160));
        checkAddExact(digits(a, sa), exponentA, digits(b, sb), exponentB);
    }

    /// Float operands maximize to coefficients with a zero last digit, so no
    /// carry is lost and `add` returns what it did before #394.
    function testAddFloatRangeMatchesPre394(int224 a, int32 ea, int224 b, int32 eb) external pure {
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementationAddPre394.add(a, ea, b, eb);
        checkAdd(a, ea, b, eb, expectedSignedCoefficient, expectedExponent);
    }
}
