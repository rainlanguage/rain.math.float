// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {ZeroNegativePower, PowNegativeBase, ExponentOverflow, ExponentUnderflow} from "src/error/ErrDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {console2} from "forge-std-1.17.0/src/Test.sol";
import {LibTestErrorBound} from "test/lib/LibTestErrorBound.sol";
import {LibTestPowRange, PowRange} from "test/lib/LibTestPowRange.sol";

contract LibDecimalFloatPowTest is LogTest {
    using LibDecimalFloat for Float;

    /// The proven bound of a pow leg, `LibTestErrorBound.pow`.
    function legError(Float b) internal pure returns (Float) {
        return LibTestErrorBound.pow(b);
    }

    /// With c = a^b (1 + d1), the inverse 1/b (1 + e) and the round trip
    /// c^(1/b (1 + e)) (1 + d2), ln(a / roundTrip) = -(d1 / b + d2 + e ln a) to
    /// first order. Each d is within `legError` plus the floor losses of its
    /// result and, for a negative b, of the base it inverts. e is the 1e-66 of
    /// a pack and |b ln a| is below 5e9 for a finite c, so e ln a vanishes.
    function roundTripLogError(Float a, Float b, Float c, Float roundTrip) internal pure returns (Float) {
        Float first = legError(b).add(LibTestErrorBound.floor(c));
        Float second = legError(b.inv()).add(LibTestErrorBound.floor(roundTrip));
        if (b.lt(LibDecimalFloat.FLOAT_ZERO)) {
            first = first.add(floorOfInverse(a));
            second = second.add(floorOfInverse(c));
        }
        return first.div(b.abs()).add(second);
    }

    /// `LibTestErrorBound.floor` of 1/x, unpacked, as 1/x need not pack.
    function floorOfInverse(Float x) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = x.unpack();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        return LibTestErrorBound.floor(signedCoefficient, exponent);
    }

    function assertRoundTrip(Float a, Float b, Float c, Float roundTrip) internal view {
        Float logError = roundTripLogError(a, b, c, roundTrip);
        // |a / roundTrip|, as |a| does not pack for the most negative Float.
        if (logError.lte(LibDecimalFloat.FLOAT_ONE)) {
            // e^y - 1 <= y + y^2 for y <= 1.
            Float diff = a.div(roundTrip).abs().sub(LibDecimalFloat.FLOAT_ONE).abs();
            assertTrue(diff.lte(logError.add(logError.mul(logError))), "diff");
        } else {
            // e^y < 10^ceil(y log10 e), log10 e under 0.4343, and past the
            // largest Float there is no bound.
            Float exponent = logError.mul(LibDecimalFloat.packLossless(4343, -4)).ceil();
            if (exponent.lte(LibDecimalFloat.packLossless(type(int32).max, 0))) {
                Float factor = this.pow10External(exponent);
                assertTrue(a.div(roundTrip).abs().lte(factor), "ratio");
                assertTrue(roundTrip.div(a).abs().lte(factor), "ratio");
            }
        }
    }

    /// The one revert pow(a, b) may have, derived from the inputs: the exact
    /// error, or only its selector where its arguments are pow's
    /// intermediates, or empty where pow must return. `mayReturn` is false
    /// where no result is representable.
    function expectedPowError(Float a, Float b) internal pure returns (bool mayReturn, bytes memory err) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        if (b.isZero()) {
            // forge-lint: disable-next-line(boolean-cst)
            return (true, "");
        } else if (signedCoefficientA == 0) {
            return b.lt(LibDecimalFloat.FLOAT_ZERO)
                // forge-lint: disable-next-line(boolean-cst)
                ? (false, abi.encodeWithSelector(ZeroNegativePower.selector, b))
                // forge-lint: disable-next-line(boolean-cst)
                : (true, bytes(""));
        } else if (signedCoefficientA < 0 && !b.frac().isZero()) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, abi.encodeWithSelector(PowNegativeBase.selector, signedCoefficientA, exponentA));
        } else if (LibDecimalFloatImplementation.eq(
                signedCoefficientA < 0 ? -signedCoefficientA : signedCoefficientA, exponentA, 1, 0
            )) {
            // forge-lint: disable-next-line(boolean-cst)
            return (true, "");
        }
        PowRange range = powRange(a, b);
        if (range == PowRange.Inside) {
            // forge-lint: disable-next-line(boolean-cst)
            return (true, "");
        }
        bool edge = range == PowRange.OverEdge || range == PowRange.UnderEdge;
        bool over = range == PowRange.Over || range == PowRange.OverEdge;
        return (edge, abi.encodePacked(over ? ExponentOverflow.selector : ExponentUnderflow.selector));
    }

    /// Where |a|^b lands, for a nonzero a other than +-1. L = b log10 |a| from
    /// the oracle. pow's bound E is relative, but its integer leg truncates
    /// multiplicatively, (1 - 1e-75)^(2N + 1), which moves L by under
    /// (2N + 1) 1e-75 / ln 10; the leg and the rounding move it by under
    /// 5.0000004e-41. So E, with |b| for N, is a slack on L both ways.
    function powRange(Float a, Float b) internal pure returns (PowRange) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficientL, int256 exponentL) = LibTestPowRange.log10Abs(signedCoefficientA, exponentA);
        (signedCoefficientL, exponentL) =
            LibDecimalFloatImplementation.mul(signedCoefficientL, exponentL, signedCoefficientB, exponentB);
        (int256 slackCoefficient, int256 slackExponent) = LibDecimalFloatImplementation.mul(
            signedCoefficientB < 0 ? -signedCoefficientB : signedCoefficientB, exponentB, 3, -75
        );
        (slackCoefficient, slackExponent) =
            LibDecimalFloatImplementation.add(slackCoefficient, slackExponent, 50000004, -48);
        return LibTestPowRange.range(signedCoefficientL, exponentL, slackCoefficient, slackExponent);
    }

    /// pow(a, b), failing on any revert but the one `expectedPowError`
    /// derives, and on a value where it derives none is representable.
    function powChecked(Float a, Float b) internal returns (bool returned, Float c) {
        (bool mayReturn, bytes memory err) = expectedPowError(a, b);
        try this.powExternal(a, b) returns (Float result) {
            assertTrue(mayReturn, "pow returned past the range");
            // forge-lint: disable-next-line(boolean-cst)
            return (true, result);
        } catch (bytes memory reason) {
            assertTrue(err.length > 0, "pow reverted inside the range");
            if (err.length == 4) {
                // forge-lint: disable-next-line(unsafe-typecast)
                assertEq(bytes4(reason), bytes4(err), "pow revert selector");
            } else {
                assertEq(reason, err, "pow revert");
            }
            // forge-lint: disable-next-line(boolean-cst)
            return (false, c);
        }
    }

    function checkPow(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        address tables = logTables();
        uint256 beforeGas = gasleft();
        Float c = a.pow(b, tables);
        uint256 afterGas = gasleft();
        console2.log("Gas used:", beforeGas - afterGas);
        (int256 actualSignedCoefficient, int256 actualExponent) = c.unpack();
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testPows() external {
        checkPow(5, 0, 13, 0, 1220703125, 0);
        // 0.5 ^ 30 = 9.3132257462e-10
        checkPow(5e37, -38, 3e37, -36, 93132257461547851562500000000000000000000, -50);
        // 0.5 ^ 60 = 8.67361737988403547205962240695953369140625e-19 is 42
        // digits on a tie, which rounds away from zero.
        checkPow(5e37, -38, 6e37, -36, 86736173798840354720596224069595336914063, -59);
        // Issues found in fuzzing from here.
        // 8.74538833058575652925523041334332969215722254574942755921268
        // 633458353995901024989835096189737575745161722050119812356738
        // 280497952674131705456780502007277553280469772918551495558754.. e48726
        checkPow(9998, 0, 12182, 0, 87453883305857565292552304133433296921572, 48686);
        // 783767830987557747626713214413804946776011874600896376644775
        // 737184122084874429184097039019333746546707574834238563105201
        // 601306157447680045947322051787243602068130996873443425180605.. e60909
        checkPow(99998, 0, 12182, 0, 78376783098755774762671321441380494677601, 60869);
        // 99999 ^ 12182 = 8.853071703048649170130397094169464632911643045383977634639832230468640539353...e60909
        // 8.853071703048649170130397094169464632911643045383977634639832230468640539353e75 e60909
        checkPow(99999, 0, 12182, 0, 88530717030486491701303970941694646329116, 60869);
        // 339181340264437326833371724490610161292169214732614339791381
        // 077839070153170394796050442886983271326431055976856477078397
        // 05146977035502651573305246467342588868622024704
        checkPow(1785215562, 0, 18, 0, 33918134026443732683337172449061016129217, 126);

        // 1.1295514523570834631500830078383428992881418895780763453451
        // 678937388891303478211805800680150846537485488564609577873121
        // 201465463889111526015508340821749525697772648457658570819388
        // 829891895455052532621e-60910
        checkPow(99999, 0, -12182, 0, 11295514523570834631500830078383428992881, -60950);

        {
            (int256 signedCoefficientE, int256 exponentE) = LibDecimalFloat.FLOAT_E.unpack();
            (int256 roundedCoefficientE, int256 roundedExponentE) =
                LibDecimalFloatImplementation.roundSignificant(signedCoefficientE, exponentE);
            checkPow(signedCoefficientE, exponentE, 1, 0, roundedCoefficientE, roundedExponentE);
        }

        checkPow(1.0029e67, -67, 0.41e2, -2, 10011879843709906483145356860918928113507, -40);
        checkPow(96001e62, -62, 0.00115e5, -5, 10132803416620015886357268353997943721136, -40);
    }

    function checkPowPrecision(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 referenceSignedCoefficient,
        int256 referenceExponent
    ) internal {
        Float c = this.powExternal(
            LibDecimalFloat.packLossless(signedCoefficientA, exponentA),
            LibDecimalFloat.packLossless(signedCoefficientB, exponentB)
        );
        Float expected = LibDecimalFloat.packLossless(referenceSignedCoefficient, referenceExponent);
        assertTrue(
            c.div(expected).sub(LibDecimalFloat.FLOAT_ONE).abs()
                .lte(legError(LibDecimalFloat.packLossless(signedCoefficientB, exponentB))),
            "precision"
        );
    }

    /// References are a^b to 45 digits from `bc -l` at scale 200.
    function testPowFractionPrecision() external {
        checkPowPrecision(2, 0, 5, -1, 141421356237309504880168872420969807856967187, -44);
        checkPowPrecision(10029, -4, 41, -2, 100118798437099064831453568609189281135073206, -44);
        checkPowPrecision(96001, 0, 115, -5, 101328034166200158863572683539979437211361504, -44);
        checkPowPrecision(123456789, -3, 37, -5, 100434717085231634989719732301784742153564552, -44);
        checkPowPrecision(7, -30, 77, -1, 321554734269797788332981945064452993255285428, -269);
        // Issue #148: a very small positive b.
        checkPowPrecision(2, 0, 1, -7, 100000006931472045825965603683996211583433798, -44);
        checkPowPrecision(999, 3, 1, -4, 100138240564875062452749129558785898736266833, -44);
        checkPowPrecision(7, -30, 37, -38, 999999999999999999999999999999999975161292222, -45);
        checkPowPrecision(123456789, -3, 1, -100, 1, 0);
    }

    function checkPowExact(Float a, Float b, Float expected) internal {
        Float c = this.powExternal(a, b);
        assertTrue(c.eq(expected), "exact");
    }

    function checkPowExact(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        checkPowExact(
            LibDecimalFloat.packLossless(signedCoefficientA, exponentA),
            LibDecimalFloat.packLossless(signedCoefficientB, exponentB),
            LibDecimalFloat.packLossless(expectedSignedCoefficient, expectedExponent)
        );
    }

    function testPowFractionExact() external {
        checkPowExact(4, 0, 15, -1, 8, 0);
        checkPowExact(16, 0, 25, -2, 2, 0);
        checkPowExact(32, 0, 2, -1, 2, 0);
        checkPowExact(81, 0, 25, -2, 3, 0);
        checkPowExact(100, 0, 15, -1, 1000, 0);
        checkPowExact(625, -4, 75, -2, 125, -3);
        checkPowExact(1024, 0, 7, -1, 128, 0);
        checkPowExact(
            LibDecimalFloat.packLossless(8, 0),
            LibDecimalFloat.FLOAT_ONE.div(LibDecimalFloat.packLossless(3, 0)),
            LibDecimalFloat.packLossless(2, 0)
        );
        checkPowExact(
            LibDecimalFloat.packLossless(1e18, 0),
            LibDecimalFloat.FLOAT_ONE.div(LibDecimalFloat.packLossless(3, 0)),
            LibDecimalFloat.packLossless(1e6, 0)
        );
    }

    /// a^b is error for negative a and all b.
    /// A negative base with a fractional exponent has no real result.
    function testNegativePowError(Float a, Float b) external {
        // We can't simply minus 0 to get a negative base.
        vm.assume(!a.isZero());
        vm.assume(!b.frac().isZero());
        if (a.gt(LibDecimalFloat.FLOAT_ZERO)) {
            a = a.minus();
        }
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        vm.expectRevert(abi.encodeWithSelector(PowNegativeBase.selector, signedCoefficientA, exponentA));
        this.powExternal(a, b);
    }

    /// Issue #88: (-a)^b for a whole b is a^b, negated when b is odd.
    function assertNegativeBaseWholeExponent(Float a, Float b, bool odd) internal {
        Float magnitude = this.powExternal(a.minus(), b);
        Float expected = odd ? magnitude.minus() : magnitude;
        assertEq(Float.unwrap(this.powExternal(a, b)), Float.unwrap(expected));
    }

    function testPowNegativeBaseWholeExponent() external {
        Float minusTwo = LibDecimalFloat.packLossless(-2, 0);
        assertTrue(
            this.powExternal(minusTwo, LibDecimalFloat.packLossless(2, 0)).eq(LibDecimalFloat.packLossless(4, 0))
        );
        assertTrue(
            this.powExternal(minusTwo, LibDecimalFloat.packLossless(3, 0)).eq(LibDecimalFloat.packLossless(-8, 0))
        );
        assertTrue(
            this.powExternal(minusTwo, LibDecimalFloat.packLossless(-1, 0)).eq(LibDecimalFloat.packLossless(-5, -1))
        );
        assertTrue(
            this.powExternal(minusTwo, LibDecimalFloat.packLossless(-2, 0)).eq(LibDecimalFloat.packLossless(25, -2))
        );
        // A negative base to the first power is itself.
        assertEq(Float.unwrap(this.powExternal(minusTwo, LibDecimalFloat.packLossless(1, 0))), Float.unwrap(minusTwo));

        Float minusOneAndAHalf = LibDecimalFloat.packLossless(-15, -1);
        assertNegativeBaseWholeExponent(minusOneAndAHalf, LibDecimalFloat.packLossless(3, 0), true);
        assertNegativeBaseWholeExponent(minusOneAndAHalf, LibDecimalFloat.packLossless(4, 0), false);
        // Whole exponents written with a non-zero exponent: 30e-1 is 3, 2e1 is 20.
        assertNegativeBaseWholeExponent(minusOneAndAHalf, LibDecimalFloat.packLossless(30, -1), true);
        assertNegativeBaseWholeExponent(minusOneAndAHalf, LibDecimalFloat.packLossless(2, 1), false);
        assertNegativeBaseWholeExponent(
            LibDecimalFloat.packLossless(-1, 0), LibDecimalFloat.packLossless(12345, 0), true
        );
    }

    function testPowNegativeBaseWholeExponentFuzz(int64 coefficientA, int8 exponentA, int8 integerB, bool scaledB)
        external
    {
        vm.assume(coefficientA != 0);
        Float a = LibDecimalFloat.packLossless(
            -int256(coefficientA < 0 ? -int256(coefficientA) : int256(coefficientA)), exponentA
        );
        // Some whole exponents carry a negative Float exponent, e.g. 30e-1.
        Float b = scaledB
            ? LibDecimalFloat.packLossless(int256(integerB) * 10, -1)
            : LibDecimalFloat.packLossless(integerB, 0);
        assertNegativeBaseWholeExponent(a, b, integerB % 2 != 0);
    }

    /// 1^b is 1 and (-1)^b is 1 or -1 by the parity of a whole b, for a b too
    /// large for the integer leg.
    function testPowOneHugeExponent() external {
        Float one = LibDecimalFloat.packLossless(1, 0);
        Float minusOne = LibDecimalFloat.packLossless(-1, 0);
        Float oneWide = LibDecimalFloat.packLossless(1e66, -66);
        Float[5] memory exponents = [
            LibDecimalFloat.packLossless(1, 77),
            LibDecimalFloat.packLossless(1, 100),
            LibDecimalFloat.packLossless(-1, 100),
            LibDecimalFloat.packLossless(15, 99),
            LibDecimalFloat.packLossless(1, type(int32).max)
        ];
        for (uint256 i = 0; i < exponents.length; i++) {
            assertEq(Float.unwrap(this.powExternal(one, exponents[i])), Float.unwrap(LibDecimalFloat.FLOAT_ONE));
            assertEq(Float.unwrap(this.powExternal(oneWide, exponents[i])), Float.unwrap(LibDecimalFloat.FLOAT_ONE));
            assertEq(Float.unwrap(this.powExternal(minusOne, exponents[i])), Float.unwrap(LibDecimalFloat.FLOAT_ONE));
        }
        // The largest odd b packs with exponent 0, below the integer leg's
        // limit, and keeps the sign.
        assertTrue(this.powExternal(minusOne, LibDecimalFloat.packLossless(type(int224).max, 0)).eq(minusOne));
    }

    /// a^0 = 1 for all a including 0^0.
    function testPowBZero(Float a, int32 exponentB) external {
        Float b = LibDecimalFloat.packLossless(0, exponentB);
        // If b is zero then the result is always 1.
        address tables = logTables();
        Float c = a.pow(b, tables);
        assertTrue(c.eq(LibDecimalFloat.packLossless(1, 0)), "c is not 1");
    }

    /// 0^b is defined as 0 for all b > 0.
    function testPowAZero(int32 exponentA, Float b) external {
        // 0^0 is defined as 1.
        vm.assume(b.gt(LibDecimalFloat.FLOAT_ZERO));
        // If a is zero then the result is always zero.
        Float a = LibDecimalFloat.packLossless(0, exponentA);
        address tables = logTables();
        Float c = a.pow(b, tables);
        assertTrue(c.isZero(), "c is not zero");
    }

    /// 0^a is error for all a < 0.
    function testPowAZeroNegative(Float b) external {
        vm.assume(b.lt(LibDecimalFloat.FLOAT_ZERO));
        vm.expectRevert(abi.encodeWithSelector(ZeroNegativePower.selector, b));
        this.powExternal(LibDecimalFloat.FLOAT_ZERO, b);
    }

    /// a^1 is a rounded to 41 significant digits, for every nonzero a of
    /// either sign and however 1 is written.
    function testPowBOne(Float a) external {
        vm.assume(!a.isZero());
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 roundedCoefficient, int256 roundedExponent) =
            LibDecimalFloatImplementation.roundSignificant(signedCoefficientA, exponentA);
        // A rounding that carries past the largest or most negative Float
        // keeps a.
        if (
            LibDecimalFloatImplementation.gt(roundedCoefficient, roundedExponent, type(int224).max, type(int32).max)
                || LibDecimalFloatImplementation.lt(
                    roundedCoefficient, roundedExponent, type(int224).min, type(int32).max
                )
        ) {
            (roundedCoefficient, roundedExponent) = (signedCoefficientA, exponentA);
        }
        unchecked {
            int256 exponent = 0;
            for (int256 i = 1; exponent >= -67;) {
                (int256 signedCoefficient, int256 exponentC) =
                    this.powExternal(a, LibDecimalFloat.packLossless(i, exponent)).unpack();
                assertTrue(
                    LibDecimalFloatImplementation.eq(signedCoefficient, exponentC, roundedCoefficient, roundedExponent),
                    "a^1"
                );
                exponent--;
                i *= 10;
            }
        }
    }

    /// int224.min at int32.max has no packed negation, so a negative base is
    /// negated unpacked. To the first power, rounding to 41 digits carries
    /// past int224, so it is itself.
    function testPowInt224MinAtTop() external {
        Float a = LibDecimalFloat.packLossless(type(int224).min, type(int32).max);
        (int256 signedCoefficient, int256 exponent) = this.powExternal(a, LibDecimalFloat.FLOAT_ONE).unpack();
        assertEq(signedCoefficient, type(int224).min);
        assertEq(exponent, type(int32).max);
        // 2^446 to 41 digits from `bc -l`.
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentOverflow.selector, int256(18170968107390172263733095197200113358841), int256(4294967388)
            )
        );
        this.powExternal(a, LibDecimalFloat.packLossless(2, 0));
    }

    /// Rounding a 68 digit coefficient at the top exponent raises the exponent
    /// past int32, and pow packs it back with a wider coefficient. A rounding
    /// that carries above the largest Float keeps the unrounded value, and
    /// only a value above the largest Float reverts.
    function testPowRoundedAtTheTop() external {
        (int256 signedCoefficient, int256 exponent) = this.powExternal(
                LibDecimalFloat.packLossless(1e67 + 1, type(int32).max), LibDecimalFloat.FLOAT_ONE
            ).unpack();
        assertEq(signedCoefficient, 1e67);
        assertEq(exponent, type(int32).max);

        (signedCoefficient, exponent) = this.powExternal(
                LibDecimalFloat.packLossless(type(int224).max, type(int32).max), LibDecimalFloat.FLOAT_ONE
            ).unpack();
        assertEq(signedCoefficient, type(int224).max);
        assertEq(exponent, type(int32).max);

        (signedCoefficient, exponent) = this.powExternal(
                LibDecimalFloat.packLossless(-type(int224).max, type(int32).max), LibDecimalFloat.FLOAT_ONE
            ).unpack();
        assertEq(signedCoefficient, -type(int224).max);
        assertEq(exponent, type(int32).max);

        // 13479973333575319897333507543509815336818.5e27 at the top exponent is
        // below the largest Float and rounds up past it.
        (signedCoefficient, exponent) = this.powExternal(
                LibDecimalFloat.packLossless(
                    13479973333575319897333507543509815336818500000000000000000000000000, type(int32).max
                ),
                LibDecimalFloat.FLOAT_ONE
            ).unpack();
        assertEq(signedCoefficient, 13479973333575319897333507543509815336818500000000000000000000000000);
        assertEq(exponent, type(int32).max);

        // A square above the largest Float still reverts.
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(13689), int256(type(int32).max) + 63));
        this.powExternal(
            LibDecimalFloat.packLossless(117, type(int32).max / 2 + 32), LibDecimalFloat.packLossless(2, 0)
        );
    }

    /// A rounded exponent one past int32 takes back one digit.
    function testPowRoundedOnePastTheTop() external {
        assertEq(
            Float.unwrap(
                this.powExternal(
                    LibDecimalFloat.packLossless(1234567890123456789012345678901234567890123, type(int32).max - 1),
                    LibDecimalFloat.FLOAT_ONE
                )
            ),
            Float.unwrap(LibDecimalFloat.packLossless(123456789012345678901234567890123456789010, type(int32).max))
        );
    }

    /// A rounded coefficient exactly at the headroom bound for its excess lifts
    /// to the top exponent, rather than falling back to the unrounded value.
    function testPowRoundedAtTheHeadroomBound() external {
        // int224.max / 1e27, the widest 41 digit coefficient that lifts 27
        // digits, followed by 27 digits that round down.
        int256 bound = 13479973333575319897333507543509815336818;
        int256 a = bound * 1e27 + 499999999999999999999999999;
        assertEq(bound, type(int224).max / 1e27);
        assertEq(-bound, type(int224).min / 1e27);

        assertEq(
            Float.unwrap(this.powExternal(LibDecimalFloat.packLossless(a, type(int32).max), LibDecimalFloat.FLOAT_ONE)),
            Float.unwrap(LibDecimalFloat.packLossless(bound * 1e27, type(int32).max))
        );
        assertEq(
            Float.unwrap(
                this.powExternal(LibDecimalFloat.packLossless(-a, type(int32).max), LibDecimalFloat.FLOAT_ONE)
            ),
            Float.unwrap(LibDecimalFloat.packLossless(-bound * 1e27, type(int32).max))
        );
    }

    /// A rounded power without the headroom to lift reverts with the unrounded
    /// value up to an excess of 67, and with the rounded value past it.
    function testPowRoundedPastTheTopRevertValue() external {
        // (3000000000000000000001e1073741856)^2 is
        // 9000000000000000000006000000000000000000001e2147483712, rounded to
        // 90000000000000000000060000000000000000000e2147483714, excess 67.
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentOverflow.selector, int256(9000000000000000000006000000000000000000001), int256(2147483712)
            )
        );
        this.powExternal(
            LibDecimalFloat.packLossless(3000000000000000000001, 1073741856), LibDecimalFloat.packLossless(2, 0)
        );

        // (999999999999999999999e1073741857)^2 is
        // 999999999999999999998000000000000000000001e2147483714, rounded to
        // 99999999999999999999800000000000000000000e2147483715, excess 68.
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentOverflow.selector, int256(99999999999999999999800000000000000000000), int256(2147483715)
            )
        );
        this.powExternal(
            LibDecimalFloat.packLossless(999999999999999999999, 1073741857), LibDecimalFloat.packLossless(2, 0)
        );
    }

    /// A short coefficient takes back more digits than a 41 digit one can, up
    /// to the 68 of int224.
    function testPowShortCoefficientPastTheTop() external {
        // (1e1073741850)^2 is 1e53 at the top exponent.
        Float a = LibDecimalFloat.packLossless(1, 1073741850);
        assertEq(
            Float.unwrap(this.powExternal(a, LibDecimalFloat.packLossless(2, 0))),
            Float.unwrap(LibDecimalFloat.packLossless(1e53, type(int32).max))
        );
        // (11e1073741856)^2 is 121e2147483712, 1.21e67 at the top exponent.
        a = LibDecimalFloat.packLossless(11, 1073741856);
        assertEq(
            Float.unwrap(this.powExternal(a, LibDecimalFloat.packLossless(2, 0))),
            Float.unwrap(LibDecimalFloat.packLossless(121e65, type(int32).max))
        );
        // (12e1073741856)^2 is 1.44e67, above the largest Float.
        a = LibDecimalFloat.packLossless(12, 1073741856);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(144), int256(2147483712)));
        this.powExternal(a, LibDecimalFloat.packLossless(2, 0));
    }

    /// Issue #297 review: a^1 kept all 67 digits of a, and 2 - 1e-50 put a
    /// 51 digit product above a^2, a 41 digit leg times a.
    function testPowRoundsAtFortyOneDigits() external {
        Float a = LibDecimalFloat.packLossless(1000000000000000000000000000000000000000051, -42);
        Float one = LibDecimalFloat.packLossless(1, -40).add(LibDecimalFloat.FLOAT_ONE);
        assertTrue(this.powExternal(a, LibDecimalFloat.FLOAT_ONE).eq(one), "a^1");
        Float justUnderOne = LibDecimalFloat.packLossless(99999999999999999999999999999999999999999999999999, -50);
        assertTrue(this.powExternal(a, justUnderOne).eq(one), "a^(1 - 1e-50)");

        Float two = LibDecimalFloat.packLossless(2, 0);
        Float justUnderTwo = LibDecimalFloat.packLossless(199999999999999999999999999999999999999999999999999, -50);
        Float a2 = this.powExternal(a, two);
        assertTrue(a2.eq(LibDecimalFloat.packLossless(10000000000000000000000000000000000000001, -40)), "a^2");
        assertTrue(this.powExternal(a, justUnderTwo).lte(a2), "a^(2 - 1e-50)");

        // 4042e-32 ^ 3.4215982134851648797 had 51 digits. bc -l at scale 300
        // gives 7.06611427578335537458715515449107452108994177e-98.
        assertTrue(
            this.powExternal(
                    LibDecimalFloat.packLossless(4042, -32), LibDecimalFloat.packLossless(34215982134851648797, -19)
                ).eq(LibDecimalFloat.packLossless(70661142757833553745871551544910745210899, -138)),
            "41 digits"
        );
    }

    function checkRoundTrip(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        address tables = logTables();
        Float c = a.pow(b, tables);

        Float roundTrip = c.pow(b.inv(), tables);
        assertRoundTrip(a, b, c, roundTrip);
    }

    /// X^Y^(1/Y) = X within `roundTripLogError`.
    function testRoundTripSimple() external {
        checkRoundTrip(5, 0, 2, 0);
        checkRoundTrip(5, 0, 3, 0);
        checkRoundTrip(50, 0, 40, 0);
        checkRoundTrip(5, -1, 3, -1);
        checkRoundTrip(5, -1, 2, -1);
        checkRoundTrip(5, 10, 3, 5);
        checkRoundTrip(5, -1, 100, 0);
        checkRoundTrip(7721, 0, -1, -2);
        checkRoundTrip(4157, 0, -1, -2);
    }

    function testRoundTripExtremes() external {
        int256 full = 12345678901234567890123456789012345678901234567890123456789012345;
        checkRoundTrip(full, -100000, 3, 0);
        checkRoundTrip(full, 100000, 3, 0);
        checkRoundTrip(full, -1000000, 7, -6);
        checkRoundTrip(2, 0, full, -60);
        checkRoundTrip(2, 0, -full, -60);
        checkRoundTrip(full, -66, 1, 9);
        checkRoundTrip(7, 0, 1, -30);
        checkRoundTrip(7, 0, -1, -30);
        checkRoundTrip(full, -30, 1, -30);
        checkRoundTrip(1e66 + 1, -66, 1, 9);
        checkRoundTrip(1e66 - 1, -66, -1, 9);
        checkRoundTrip(7, 0, 1e66 + 1, -66);
        checkRoundTrip(7, 0, 1e66 - 1, -66);
        checkRoundTrip(7, 0, -1e66 - 1, -66);
        checkRoundTrip(7, 0, -1e66 + 1, -66);
        checkRoundTrip(full, -50, -1e66 + 1, -66);
        // ln(1e100) * 1e-41 sits a fraction of the 41st digit above 1, so the
        // round trip is only good to a factor, not to the old 0.09.
        checkRoundTrip(1, 100, 1, -41);
    }

    function testRoundTripFuzzPowBounded(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external {
        signedCoefficientA = bound(signedCoefficientA, 1, 1e67 - 1);
        exponentA = bound(exponentA, -300, 300);
        signedCoefficientB = bound(signedCoefficientB, -1e67 + 1, 1e67 - 1);
        vm.assume(signedCoefficientB != 0);
        exponentB = bound(exponentB, -110, 40);
        roundTripFuzz(
            LibDecimalFloat.packLossless(signedCoefficientA, exponentA),
            LibDecimalFloat.packLossless(signedCoefficientB, exponentB)
        );
    }

    function powExternal(Float a, Float b) external returns (Float) {
        return a.pow(b, logTables());
    }

    /// `pow` raises to an integer exponent via exponentiation by squaring,
    /// which squares the base in place. The base exponent therefore grows by
    /// roughly a factor of two per bit of the integer exponent, so a large
    /// enough integer exponent overflows `ExponentOverflow` before the result
    /// can be produced. This is the squaring-loop limitation that previously
    /// forced `testRoundTripFuzzPow` to `vm.assume(exponentInv <= 8e8)`: the
    /// inverse leg of a round trip can land an integer exponent above that
    /// ceiling. Pin the boundary so the fuzz test can instead just catch the
    /// revert and keep exercising the full input range.
    function testPowIntegerExponentSquaringOverflow() external {
        // 2 ^ 1e9 is right at the edge of what the squaring loop can represent
        // and does not overflow.
        Float a = LibDecimalFloat.packLossless(2, 0);
        this.powExternal(a, LibDecimalFloat.packLossless(1, 9));

        // 2 ^ 1e10 pushes the squared base exponent past EXPONENT_MAX and
        // reverts with ExponentOverflow. A round trip catches this rather than
        // treating it as a math regression.
        vm.expectRevert(
            abi.encodeWithSelector(ExponentOverflow.selector, 43632686345562428988582910876713633851546, 3010299916)
        );
        this.powExternal(a, LibDecimalFloat.packLossless(1, 10));
    }

    /// Issue #239: an integer exponent large enough to double the squared
    /// base's exponent past int256 panicked instead of reverting typed.
    function testPowSquaringPastInt256Underflow() external {
        Float a = LibDecimalFloat.packLossless(1, 1700000000);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentUnderflow.selector, int256(1e76), int256(-269375752548498747818049431142400000076)
            )
        );
        this.powExternal(a, LibDecimalFloat.packLossless(-8, 69));
    }

    function testPowSquaringPastInt256Overflow() external {
        Float a = LibDecimalFloat.packLossless(1, 1700000000);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentOverflow.selector, int256(1), int256(269375752548498747818049431142400000000)
            )
        );
        this.powExternal(a, LibDecimalFloat.packLossless(8, 69));
    }

    /// Issue #149: the inverse of a base this far up the range is below
    /// int32.min, but a small negative power of it is not.
    function testPowNegativeExponentHugeBase() external {
        Float a = LibDecimalFloat.packLossless(1e66, type(int32).max);
        Float b = LibDecimalFloat.packLossless(1, -7);
        Float product = this.powExternal(a, b.minus()).mul(this.powExternal(a, b));
        assertTrue(product.gt(LibDecimalFloat.packLossless(999, -3)));
        assertTrue(product.lt(LibDecimalFloat.packLossless(1001, -3)));
    }

    /// Issue #297 review: 0.1^2147483645.5 is 316.2277e-2147483648, below
    /// 1e-2147483608, so it sheds digits at the int32 floor.
    function testPowFloor() external {
        checkPow(1, -1, 21474836455, -1, 316, type(int32).min);
    }

    /// The base's inverse is the result when the power is -1, so it still
    /// underflows: 10^-2147483713 is 1e40 · 10^-2147483753.
    function testPowMinusOneHugeBaseUnderflows() external {
        Float a = LibDecimalFloat.packLossless(1e66, type(int32).max);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1e40), int256(-2147483753)));
        this.powExternal(a, LibDecimalFloat.packLossless(-1, 0));
    }

    /// pow(a, -1) is the inverse rounded to 41 digits.
    function testPowMinusOneIsInv(int64 c, int16 e) external {
        vm.assume(c > 0);
        Float a = LibDecimalFloat.packLossless(c, e);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.inv(c, e);
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.roundSignificant(signedCoefficient, exponent);
        Float r = this.powExternal(a, LibDecimalFloat.packLossless(-1, 0));
        assertTrue(r.eq(LibDecimalFloat.packLossless(signedCoefficient, exponent)), "pow(a, -1) != inv(a) rounded");
    }

    function invExternal(Float a) external pure returns (Float) {
        return a.inv();
    }

    function mulExternal(Float a, Float b) external pure returns (Float) {
        return a.mul(b);
    }

    /// a^-b is 1/a^b across a's whole exponent range, wherever 1/a^b has
    /// headroom for pow's approximation error on both sides of the range.
    /// Each side is within `legError` plus the floor losses of what it packed.
    function testPowNegativeExponentIsInverseFuzz(
        int224 coefficientA,
        int32 exponentA,
        uint8 region,
        int256 coefficientB,
        int256 exponentB
    ) external {
        coefficientA = int224(bound(coefficientA, 1, type(int224).max));
        if (region % 3 == 1) {
            exponentA = int32(bound(exponentA, type(int32).max - 300, type(int32).max));
        } else if (region % 3 == 2) {
            exponentA = int32(bound(exponentA, type(int32).min, type(int32).min + 300));
        }
        Float a = LibDecimalFloat.packLossless(coefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(bound(coefficientB, 1, 1e9), bound(exponentB, -15, 0));

        (bool returned, Float power) = powChecked(a, b);
        (bool returnedInverse, Float actual) = powChecked(a, b.minus());
        if (returned && inverseRepresentable(power)) {
            assertTrue(returnedInverse, "a^-b reverted");
            assertInverse(b, power, actual);
        }
    }

    /// 1/x, unpacked, is two orders inside the range on both sides.
    function inverseRepresentable(Float x) internal pure returns (bool) {
        (int256 signedCoefficient, int256 exponent) = x.unpack();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        return LibDecimalFloatImplementation.lte(signedCoefficient, exponent, type(int224).max, type(int32).max - 2)
            && LibDecimalFloatImplementation.gte(signedCoefficient, exponent, 1, type(int32).min + 2);
    }

    function assertInverse(Float b, Float power, Float actual) internal pure {
        Float expected = power.inv();
        Float diff = actual.div(expected).sub(LibDecimalFloat.FLOAT_ONE).abs();
        Float limit = legError(b).add(legError(b)).add(LibTestErrorBound.floor(power))
            .add(LibTestErrorBound.floor(actual)).add(LibTestErrorBound.floor(expected));
        assertTrue(diff.lte(limit), "diff");
    }

    /// `lastExponent` is the last e where (1e66 · 10^e)^b packs. The true
    /// value there is 10^((e + 66) · b), so it lands on the smallest Float,
    /// and e + 1 underflows.
    function checkPowNegativeBoundary(
        Float b,
        int256 lastExponent,
        int256 expectedCoefficient,
        int256 underflowCoefficient,
        int256 underflowExponent
    ) internal {
        (int256 coefficient, int256 exponent) =
            this.powExternal(LibDecimalFloat.packLossless(1e66, lastExponent), b).unpack();
        assertEq(coefficient, expectedCoefficient, "coefficient");
        assertEq(exponent, type(int32).min, "exponent");

        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, underflowCoefficient, underflowExponent));
        this.powExternal(LibDecimalFloat.packLossless(1e66, lastExponent + 1), b);
    }

    function testPowNegativeExponentHugeBaseBoundary() external {
        checkPowNegativeBoundary(LibDecimalFloat.packLossless(-1, 0), 2147483582, 1, 1e40, -2147483689);
        checkPowNegativeBoundary(
            LibDecimalFloat.packLossless(-10000001, -7),
            2147483367,
            1,
            17850755436588146297541876494389270655413,
            -2147483689
        );
        checkPowNegativeBoundary(
            LibDecimalFloat.packLossless(-1000001, -6),
            2147481434,
            3,
            32998864808301811879257186566783903264015,
            -2147483689
        );
        checkPowNegativeBoundary(LibDecimalFloat.packLossless(-2, 0), 1073741758, 1, 1e40, -2147483690);
    }

    /// The inverse of the smallest base is 10^2147483648, which still packs,
    /// so every power past -1 overflows, typed.
    function testPowNegativeExponentTinyBaseOverflows() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);

        (int256 coefficient, int256 exponent) = this.powExternal(a, LibDecimalFloat.packLossless(-1, 0)).unpack();
        assertEq(coefficient, 1e40, "coefficient");
        assertEq(exponent, 2147483608, "exponent");

        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentOverflow.selector, int256(63095734448019324943436013662234386467295), int256(2362231972)
            )
        );
        this.powExternal(a, LibDecimalFloat.packLossless(-11, -1));

        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1e40), int256(4294967256)));
        this.powExternal(a, LibDecimalFloat.packLossless(-2, 0));

        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1e40), int256(2147483647999999960)));
        this.powExternal(a, LibDecimalFloat.packLossless(-1, 9));

        // The squared base passes int128 before the loop ends.
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentOverflow.selector, int256(1e76), int256(340282366920938463463374607431768211380)
            )
        );
        this.powExternal(a, LibDecimalFloat.packLossless(-1, 30));
    }

    /// Issue #276's counterexample, bit for bit: a full-width coefficient base
    /// raised to a negative power with a 233-bit integer part.
    function testPowIssue276Counterexample() external {
        Float a = Float.wrap(0x5061727365206572726f7220286e656729000000000000000000000000000000);
        Float b = Float.wrap(0x00000003b58e88c75313ec9d329eaaa18fb92f75215b170fffffffffffffffff);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentUnderflow.selector,
                int256(28887451280490018407141552948600676295694378589943120383753856872962994543013),
                int256(-213688438148915952713935726556846144011)
            )
        );
        this.powExternal(a, b);
    }

    /// The concrete counterexample surfaced by `testRoundTripFuzzPow`: a is 1,
    /// whose round trip leg `c.pow(b.inv())` reverted `WithTargetExponentOverflow`
    /// on an inverse with exponent 363177628, until 1^b returned 1 (#312).
    function testRoundTripOneHugeExponent() external {
        Float a = Float.wrap(bytes32(uint256(1)));
        Float b = Float.wrap(bytes32(0xea5a58dfdcc79c60ac38b8284569e4519fda5eaaffec2a3d22027a4af1969e13));

        Float c = this.powExternal(a, b);
        assertEq(Float.unwrap(c), Float.unwrap(LibDecimalFloat.FLOAT_ONE));
        assertEq(Float.unwrap(this.powExternal(c, b.inv())), Float.unwrap(LibDecimalFloat.FLOAT_ONE));
    }

    /// A b whose integer part is past int256 takes every a but 1 past the
    /// range, on the side a is of 1 after b's sign inverts it. It reverted
    /// `WithTargetExponentOverflow` before.
    function testPowHugeExponentDirection() external {
        Float b = LibDecimalFloat.packLossless(1, 77);
        Float wide = LibDecimalFloat.packLossless(58, 75);
        Float above = LibDecimalFloat.packLossless(1e67 + 1, -67);
        Float below = LibDecimalFloat.packLossless(1e67 - 1, -67);

        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(2), int256(0)));
        this.powExternal(LibDecimalFloat.packLossless(2, 0), b);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(5), int256(-1)));
        this.powExternal(LibDecimalFloat.packLossless(5, -1), b);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1e67 + 1), int256(-67)));
        this.powExternal(above, wide);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1e67 - 1), int256(-67)));
        this.powExternal(below, wide);

        // A negative b inverts a first.
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.inv(2, 0);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, signedCoefficient, exponent));
        this.powExternal(LibDecimalFloat.packLossless(2, 0), b.minus());
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(5, -1);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
        this.powExternal(LibDecimalFloat.packLossless(5, -1), b.minus());

        // A whole b keeps a negative base, by its magnitude.
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(2), int256(0)));
        this.powExternal(LibDecimalFloat.packLossless(-2, 0), b);

        // 5.7e76 still fits int256 and goes to the squaring loop.
        // `bc -l`: 7.0556238177305947296050112001e2475478546. The squaring
        // loop agrees to 27 digits, inside no bound at this N.
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentOverflow.selector, int256(70556238177305947296050111997187013240152), int256(2475478506)
            )
        );
        this.powExternal(above, LibDecimalFloat.packLossless(57, 75));
    }

    /// The most negative Float as b, or as a base with a whole b, does not
    /// pack negated. It reverted `ExponentOverflow` whichever side of the range
    /// the power is on.
    function testPowMostNegativeFloat() external {
        Float most = LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE;

        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.inv(2, 0);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, signedCoefficient, exponent));
        this.powExternal(LibDecimalFloat.packLossless(2, 0), most);
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(5, -1);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
        this.powExternal(LibDecimalFloat.packLossless(5, -1), most);

        // most is -2^223 10^2147483647. From `bc -l`, 2^-223 and 2^446 rounded
        // to 41 digits.
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentUnderflow.selector, int256(-74184123013748427714634705230952790267351), int256(-2147483755)
            )
        );
        this.powExternal(most, LibDecimalFloat.packLossless(-1, 0));
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentOverflow.selector, int256(18170968107390172263733095197200113358841), int256(4294967388)
            )
        );
        this.powExternal(most, LibDecimalFloat.packLossless(2, 0));
        assertEq(
            Float.unwrap(this.powExternal(most, LibDecimalFloat.FLOAT_ZERO)), Float.unwrap(LibDecimalFloat.FLOAT_ONE)
        );
    }

    function testRoundTripFuzzPow(Float a, Float b) external {
        roundTripFuzz(a, b);
    }

    /// Each leg returns or reverts only as `powChecked` derives from its own
    /// inputs.
    function roundTripFuzz(Float a, Float b) internal {
        (bool returned, Float c) = powChecked(a, b);
        // If C is 1 then either a == 1 or b == 0 (or b rounds to 0).
        // The case where a is 1 should round trip, but all other cases won't.
        if (!returned || !(a.eq(LibDecimalFloat.FLOAT_ONE) || !c.eq(LibDecimalFloat.FLOAT_ONE))) {
            return;
        }
        if (b.isZero()) {
            assertTrue(c.eq(LibDecimalFloat.FLOAT_ONE), "b is 0 so c should be 1");
        } else if (!(c.isZero() && b.lt(LibDecimalFloat.FLOAT_ZERO))) {
            // 1/b underflows for a b near the top of the range, and then there
            // is no round trip.
            (int256 signedCoefficient, int256 exponent) = b.unpack();
            (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
            (Float inv,) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
            if (inv.isZero()) {
                return;
            }
            (bool roundTripped, Float roundTrip) = powChecked(c, inv);
            if (roundTripped && !roundTrip.isZero()) {
                // An even power drops a negative base's sign and the root
                // returned is the positive one, while an odd one keeps it, so
                // magnitudes are compared. testPowNegativeBaseWholeExponent
                // pins the sign.
                assertRoundTrip(a, b, c, roundTrip);
            }
        }
    }

    /// a^(p / q) for a = n^q 10^(qk) is n^p 10^(pk) exactly, wherever n^p has
    /// at most the 41 digits pow keeps.
    function testPowExactRoots(uint256 n, int256 k, uint256 which) external {
        // (q, p, the largest n for n^q below 1e66 and n^p below 1e41, b's coefficient,
        // b's exponent)
        uint256[5][11] memory roots = [
            [uint256(2), 1, 1e20 - 1, 5, 1],
            [uint256(2), 3, 46415888336127, 15, 1],
            [uint256(4), 1, 1e10 - 1, 25, 2],
            [uint256(4), 3, 1e10 - 1, 75, 2],
            [uint256(5), 1, 1e8 - 1, 2, 1],
            [uint256(5), 2, 1e8 - 1, 4, 1],
            [uint256(5), 3, 1e8 - 1, 6, 1],
            [uint256(8), 1, 1e5 - 1, 125, 3],
            [uint256(8), 5, 1e5 - 1, 625, 3],
            [uint256(10), 1, 1e4 - 1, 1, 1],
            [uint256(10), 7, 1e4 - 1, 7, 1]
        ];
        uint256[5] memory root = roots[which % roots.length];
        n = bound(n, 1, root[2]);
        k = bound(k, -1e7, 1e7);
        // forge-lint: disable-next-line(unsafe-typecast)
        Float a = LibDecimalFloat.packLossless(int256(n ** root[0]), int256(root[0]) * k);
        // forge-lint: disable-next-line(unsafe-typecast)
        Float b = LibDecimalFloat.packLossless(int256(root[3]), -int256(root[4]));
        // forge-lint: disable-next-line(unsafe-typecast)
        Float expected = LibDecimalFloat.packLossless(int256(n ** root[1]), int256(root[1]) * k);
        assertTrue(this.powExternal(a, b).eq(expected), "exact");
    }

    function pow10External(Float x) external pure returns (Float) {
        return x.pow10(address(0));
    }

    /// (10^k)^b is pow10(k b) exactly, as log10(10^k) is exactly k.
    function testPowPowersOfTenMatchPow10(int256 k, int256 signedCoefficientB, int256 exponentB) external {
        k = bound(k, -1e4, 1e4);
        vm.assume(k != 0);
        Float b = LibDecimalFloat.packLossless(bound(signedCoefficientB, 1, 1e12), bound(exponentB, -12, -9));
        Float kb = LibDecimalFloat.packLossless(k, 0).mul(b);
        assertTrue(this.powExternal(LibDecimalFloat.packLossless(1, k), b).eq(this.pow10External(kb)), "pow10");
    }

    /// a < c implies a^b <= c^b + 2E for b > 0, down to adjacent coefficients.
    function testPowMonotoneInBase(
        int256 signedCoefficientA,
        int256 gap,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external {
        signedCoefficientA = bound(signedCoefficientA, 1, type(int224).max - 1e3);
        gap = bound(gap, 1, 1e3);
        exponentA = bound(exponentA, -1000, 1000);
        Float b = LibDecimalFloat.packLossless(bound(signedCoefficientB, 1, 1e9), bound(exponentB, -9, -8));
        Float low = this.powExternal(LibDecimalFloat.packLossless(signedCoefficientA, exponentA), b);
        Float high = this.powExternal(LibDecimalFloat.packLossless(signedCoefficientA + gap, exponentA), b);
        assertTrue(LibTestErrorBound.monotoneRelative(low, high, legError(b), legError(b)), "monotone");
    }

    /// One unit in the 41st significant digit of x.
    function ulp(Float x) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = x.unpack();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);
        int256 digits = signedCoefficient / 1e76 == 0 ? int256(76) : int256(77);
        return LibDecimalFloat.packLossless(1, exponent + digits - 41);
    }

    /// b < c implies a^b <= a^c + 2E for a > 1, down to adjacent exponents,
    /// and a flip is exactly one unit in the last place.
    function testPowMonotoneInExponent(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 lowB,
        int256 exponentB,
        int256 gap
    ) external {
        signedCoefficientA = bound(signedCoefficientA, 1, 1e67);
        exponentA = bound(exponentA, -67, 0);
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        vm.assume(a.gt(LibDecimalFloat.FLOAT_ONE));
        exponentB = bound(exponentB, -50, -18);
        // b is at most 4.
        // forge-lint: disable-next-line(unsafe-typecast)
        lowB = bound(lowB, 1, 4 * int256(10 ** uint256(-exponentB)));
        gap = bound(gap, 1, 1e3);
        Float b = LibDecimalFloat.packLossless(lowB, exponentB);
        Float c = LibDecimalFloat.packLossless(lowB + gap, exponentB);
        Float low = this.powExternal(a, b);
        Float high = this.powExternal(a, c);
        assertTrue(LibTestErrorBound.monotoneRelative(low, high, legError(b), legError(c)), "monotone");
        if (high.lt(low)) {
            assertTrue(low.eq(high.add(ulp(high))), "one ulp");
        }
    }
}
