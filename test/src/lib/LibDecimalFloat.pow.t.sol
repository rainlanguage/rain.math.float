// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {ZeroNegativePower, PowNegativeBase, ExponentOverflow, ExponentUnderflow} from "src/error/ErrDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTestErrorBound} from "test/lib/LibTestErrorBound.sol";
import {LibTestPowRange, PowRange, LOG10_OVERFLOW, THRESHOLD_SLACK} from "test/lib/LibTestPowRange.sol";
import {LibTranscendentalOracle} from "test/lib/LibTranscendentalOracle.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

contract LibDecimalFloatPowTest is Test {
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

    /// The reverts pow(a, b) may have, derived from the inputs: none where it
    /// must return, and the range errors `LibTestPowRange.powRange` allows.
    /// `mayReturn` is false where no result is representable.
    function expectedPowError(Float a, Float b)
        internal
        pure
        returns (bool mayReturn, bytes memory err, bytes memory otherErr)
    {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        if (signedCoefficientB == 0) {
            // forge-lint: disable-next-line(boolean-cst)
            return (true, "", "");
        } else if (signedCoefficientA == 0) {
            return signedCoefficientB < 0
                // forge-lint: disable-next-line(boolean-cst)
                ? (false, abi.encodeWithSelector(ZeroNegativePower.selector, b), bytes(""))
                // forge-lint: disable-next-line(boolean-cst)
                : (true, bytes(""), bytes(""));
        } else if (signedCoefficientA < 0 && !LibTestExactDecimal.isWhole(signedCoefficientB, exponentB)) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, abi.encodeWithSelector(PowNegativeBase.selector, signedCoefficientA, exponentA), bytes(""));
        } else if (LibTestExactDecimal.eq(
                signedCoefficientA < 0 ? -signedCoefficientA : signedCoefficientA, exponentA, 1, 0
            )) {
            // forge-lint: disable-next-line(boolean-cst)
            return (true, "", "");
        }
        PowRange range = LibTestPowRange.powRange(a, b);
        mayReturn = LibTestPowRange.mayReturn(range);
        if (LibTestPowRange.mayRevert(range, true)) {
            err = LibTestPowRange.rangeError(true, a);
        }
        if (LibTestPowRange.mayRevert(range, false)) {
            otherErr = LibTestPowRange.rangeError(false, a);
        }
    }

    /// pow(a, b), failing on any revert but those `expectedPowError`
    /// derives, and on a value where it derives none is representable.
    function powChecked(Float a, Float b) internal view returns (bool returned, Float c) {
        (bool mayReturn, bytes memory err, bytes memory otherErr) = expectedPowError(a, b);
        try this.powExternal(a, b) returns (Float result) {
            assertTrue(mayReturn, "pow returned past the range");
            // forge-lint: disable-next-line(boolean-cst)
            return (true, result);
        } catch (bytes memory reason) {
            assertTrue(
                (err.length > 0 && keccak256(reason) == keccak256(err))
                    || (otherErr.length > 0 && keccak256(reason) == keccak256(otherErr)),
                "pow revert"
            );
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
    ) internal view {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        uint256 beforeGas = gasleft();
        Float c = a.pow(b);
        uint256 afterGas = gasleft();
        console2.log("Gas used:", beforeGas - afterGas);
        (int256 actualSignedCoefficient, int256 actualExponent) = c.unpack();
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testPows() external view {
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

        // -1/2^59 = -1.73472347597680709441192448139190673828125e-18 is 42 digits
        // on a tie, which rounds away from zero.
        checkPow(-576460752303423488, 0, -1, 0, -17347234759768070944119244813919067382813, -58);

        {
            // e = 2.7182818284590452353602874713526624977572 47..., so e^1 at 41
            // digits rounds down.
            (int256 signedCoefficientE, int256 exponentE) = LibDecimalFloat.FLOAT_E.unpack();
            checkPow(signedCoefficientE, exponentE, 1, 0, 27182818284590452353602874713526624977572, -40);
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
    ) internal view {
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
    function testPowFractionPrecision() external view {
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

    function checkPowExact(Float a, Float b, Float expected) internal view {
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
    ) internal view {
        checkPowExact(
            LibDecimalFloat.packLossless(signedCoefficientA, exponentA),
            LibDecimalFloat.packLossless(signedCoefficientB, exponentB),
            LibDecimalFloat.packLossless(expectedSignedCoefficient, expectedExponent)
        );
    }

    function testPowFractionExact() external view {
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

    /// b = n + 1/2, which pow takes as the root of a^(2N+1). References are
    /// a^b from `bc -l` at scale 400, rounded to 41 digits; each true value is
    /// at least 0.04 of a unit from a rounding midpoint.
    function testPowHalfReference() external view {
        int256 m = type(int224).max;
        checkPowExact(2, 0, 5, -1, 14142135623730950488016887242096980785697, -40);
        checkPowExact(2, 0, 15, -1, 28284271247461900976033774484193961571393, -40);
        checkPowExact(2, 0, -5, -1, 70710678118654752440084436210484903928484, -41);
        checkPowExact(2, 0, -15, -1, 35355339059327376220042218105242451964242, -41);
        checkPowExact(3, 0, 25, -1, 15588457268119895641747017073552851302485, -39);
        checkPowExact(7, 0, 105, -1, 74735926038504668213500094491157274492835, -32);
        checkPowExact(10001, -4, 3655, -1, 10372242686267163625948684644874211166049, -40);
        checkPowExact(
            12345678901234567890123456789012345678901, -40, 15, -1, 13717420939643347448902607016495201211796, -40
        );
        checkPowExact(m, 0, 5, -1, 36715083186035844657140163036746987446154, -7);
        // m^3 passes 1e76 in the coefficient, so a digit is dropped before the root.
        checkPowExact(m, 0, 15, -1, 49491834228776278184956125696820890771745, 60);
        checkPowExact(m, 0, 25, -1, 66714860563363448814354475902698812823710, 127);
        checkPowExact(m, 0, -15, -1, 20205353379660459832413064675171877816182, -141);
        checkPowExact(2, 0, 1005, -1, 17927286711931564773994220232786614963942, -10);
        checkPowExact(999, -2, 25, -1, 31543778943002358670330350761941590124385, -38);
        checkPowExact(7, -30, 15, -1, 18520259177452134133511310275474822979972, -84);
        checkPowExact(5, -1, -25, -1, 56568542494923801952067548968387923142787, -40);
    }

    /// A = floor((2c + 1)^2 / 4e16) has a root just below the midpoint
    /// (c + 1/2) 1e-8 and A + 1 one just above it, so a half power of each
    /// rounds to c 1e-8 and (c + 1) 1e-8, in every representation of a half
    /// down to the most digits a packed coefficient holds, 5e66 10^-67.
    function testPowHalfMidpoint(uint256 c) external view {
        c = bound(c, 1e40, 1e41 - 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 a = int256(Math.mulDiv(2 * c + 1, 2 * c + 1, 4e16));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedC = int256(c);
        int256[4] memory digits = [int256(0), 30, 65, 66];
        for (uint256 i = 0; i < digits.length; i++) {
            int256 j = digits[i];
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 half = 5 * int256(10 ** uint256(j));
            checkPowExact(a, 0, half, -j - 1, signedC, -8);
            checkPowExact(a + 1, 0, half, -j - 1, signedC + 1, -8);
        }
    }

    /// A half in any representation takes the same root.
    function testPowHalfRepresentations() external view {
        checkPowExact(2, 0, 50, -2, 14142135623730950488016887242096980785697, -40);
        checkPowExact(2, 0, 1500000, -6, 28284271247461900976033774484193961571393, -40);
        checkPowExact(2, 0, 15e60, -61, 28284271247461900976033774484193961571393, -40);
        checkPowExact(2, 0, -15e60, -61, 35355339059327376220042218105242451964242, -41);
    }

    /// a^(1/2) is sqrt a, correctly rounded.
    function testPowHalfIsSqrt(int224 signedCoefficient, int32 exponent) external view {
        vm.assume(signedCoefficient > 0);
        Float a = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        assertTrue(this.powExternal(a, LibDecimalFloat.FLOAT_HALF).eq(a.sqrt()), "sqrt");
    }

    /// A fractional part next to a half takes the log path, within its bound.
    /// References are a^b to 45 digits from `bc -l` at scale 100.
    function testPowNearHalf() external view {
        checkPowPrecision(2, 0, 4999999, -7, 141421346434728409926273288890691513652913439, -44);
        checkPowPrecision(2, 0, 5000001, -7, 141421366039891279297232822101374230501114564, -44);
    }

    /// a^b is error for negative a and all b.
    /// A negative base with a fractional exponent has no real result.
    function testNegativePowError(Float a, Float b) external {
        // We can't simply minus 0 to get a negative base.
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        vm.assume(signedCoefficientA != 0);
        vm.assume(!LibTestExactDecimal.isWhole(signedCoefficientB, exponentB));
        if (signedCoefficientA > 0) {
            // A positive int224 coefficient negates exactly.
            a = LibDecimalFloat.packLossless(-signedCoefficientA, exponentA);
            signedCoefficientA = -signedCoefficientA;
        }
        vm.expectRevert(abi.encodeWithSelector(PowNegativeBase.selector, signedCoefficientA, exponentA));
        this.powExternal(a, b);
    }

    /// Issue #88: (-a)^b for a whole b is a^b, negated when b is odd.
    function assertNegativeBaseWholeExponent(Float a, Float b, bool odd) internal view {
        Float magnitude = this.powExternal(a.minus(), b);
        Float expected = odd ? magnitude.minus() : magnitude;
        assertEq(Float.unwrap(this.powExternal(a, b)), Float.unwrap(expected));
    }

    function testPowNegativeBaseWholeExponent() external view {
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
        view
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
    function testPowOneHugeExponent() external view {
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
    function testPowBZero(Float a, int32 exponentB) external pure {
        Float b = LibDecimalFloat.packLossless(0, exponentB);
        // If b is zero then the result is always 1.
        Float c = a.pow(b);
        assertTrue(c.eq(LibDecimalFloat.packLossless(1, 0)), "c is not 1");
    }

    /// 0^b is defined as 0 for all b > 0.
    function testPowAZero(int32 exponentA, Float b) external pure {
        // 0^0 is defined as 1.
        vm.assume(b.gt(LibDecimalFloat.FLOAT_ZERO));
        // If a is zero then the result is always zero.
        Float a = LibDecimalFloat.packLossless(0, exponentA);
        Float c = a.pow(b);
        assertTrue(c.isZero(), "c is not zero");
    }

    /// 0^a is error for all a < 0.
    function testPowAZeroNegative(Float b) external {
        (int256 signedCoefficientB,) = b.unpack();
        vm.assume(signedCoefficientB < 0);
        vm.expectRevert(abi.encodeWithSelector(ZeroNegativePower.selector, b));
        this.powExternal(LibDecimalFloat.FLOAT_ZERO, b);
    }

    /// x rounded to 41 significant digits, half away from zero, in integers.
    function roundHalfAway41(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        uint256 magnitude = LibTestExactDecimal.abs(signedCoefficient);
        uint256 guard = 1;
        while (magnitude / guard >= 1e41) {
            guard *= 10;
            exponent++;
        }
        uint256 rounded = magnitude / guard;
        if (2 * (magnitude % guard) >= guard) {
            rounded++;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return (signedCoefficient < 0 ? -int256(rounded) : int256(rounded), exponent);
    }

    /// a^1 is a rounded to 41 significant digits, for every nonzero a of
    /// either sign and however 1 is written.
    function testPowBOne(Float a) external view {
        vm.assume(!a.isZero());
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 roundedCoefficient, int256 roundedExponent) = roundHalfAway41(signedCoefficientA, exponentA);
        // A rounding that carries past the largest or most negative Float
        // keeps a.
        if (LibTestExactDecimal.overflows(
                LibTestExactDecimal.u512(LibTestExactDecimal.abs(roundedCoefficient)), roundedExponent
            )) {
            (roundedCoefficient, roundedExponent) = (signedCoefficientA, exponentA);
        }
        unchecked {
            int256 exponent = 0;
            for (int256 i = 1; exponent >= -67;) {
                (int256 signedCoefficient, int256 exponentC) =
                    this.powExternal(a, LibDecimalFloat.packLossless(i, exponent)).unpack();
                assertTrue(
                    LibTestExactDecimal.eq(signedCoefficient, exponentC, roundedCoefficient, roundedExponent), "a^1"
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
        vm.expectRevert(
            abi.encodeWithSelector(ExponentOverflow.selector, int256(type(int224).min), int256(type(int32).max))
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
        vm.expectRevert(
            abi.encodeWithSelector(ExponentOverflow.selector, int256(117), int256(type(int32).max / 2 + 32))
        );
        this.powExternal(
            LibDecimalFloat.packLossless(117, type(int32).max / 2 + 32), LibDecimalFloat.packLossless(2, 0)
        );
    }

    /// A rounded exponent one past int32 takes back one digit.
    function testPowRoundedOnePastTheTop() external view {
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
    function testPowRoundedAtTheHeadroomBound() external view {
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

    /// A rounded power without the headroom to lift reverts with a, whether
    /// the unrounded value is packed, up to an excess of 67, or not, past it.
    function testPowRoundedPastTheTopRevertValue() external {
        // (3000000000000000000001e1073741856)^2 is
        // 9000000000000000000006000000000000000000001e2147483712, rounded to
        // 90000000000000000000060000000000000000000e2147483714, excess 67.
        vm.expectRevert(
            abi.encodeWithSelector(ExponentOverflow.selector, int256(3000000000000000000001), int256(1073741856))
        );
        this.powExternal(
            LibDecimalFloat.packLossless(3000000000000000000001, 1073741856), LibDecimalFloat.packLossless(2, 0)
        );

        // (999999999999999999999e1073741857)^2 is
        // 999999999999999999998000000000000000000001e2147483714, rounded to
        // 99999999999999999999800000000000000000000e2147483715, excess 68.
        vm.expectRevert(
            abi.encodeWithSelector(ExponentOverflow.selector, int256(999999999999999999999), int256(1073741857))
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
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(12), int256(1073741856)));
        this.powExternal(a, LibDecimalFloat.packLossless(2, 0));
    }

    /// A fractional power's unrounded value is wider than int224, so the carry
    /// fallback sheds digits to pack it. From `bc -l`, a^1.25 for this a is
    /// 1.34799733335753198973335075435098153368185299...e2147483714: its 41
    /// digit rounding carries above the largest Float, and it is below the
    /// overflow threshold, (int224.max / 10 + 1) 10^(int32.max + 1). The leg
    /// is within 3.34e-48 relative of it and the pack truncates, so the packed
    /// coefficient at int32.max is within 4.51e19 of the true one. a (1 + 1e-39)
    /// is past the threshold.
    function testPowCarryShedsTheUnrounded() external {
        int256 signedCoefficientA = 2012571074104523405533623944864037356347794582055760651559118452;
        int256 exponentA = 1717986908;
        Float b = LibDecimalFloat.packLossless(125, -2);
        (bool returned, Float c) = powChecked(LibDecimalFloat.packLossless(signedCoefficientA, exponentA), b);
        assertTrue(returned, "returned");
        (int256 signedCoefficient, int256 exponent) = c.unpack();
        assertEq(exponent, type(int32).max);
        int256 trueCoefficient = 13479973333575319897333507543509815336818529999999999999999999993262;
        assertApproxEqAbs(signedCoefficient, trueCoefficient, 45023110934141568458);

        int256 signedCoefficientPast = 2012571074104523405533623944864037356349807153129865174964652075;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientPast, exponentA));
        this.powExternal(LibDecimalFloat.packLossless(signedCoefficientPast, exponentA), b);
    }

    /// A half power is a correctly rounded root, so no carry fallback: this
    /// a^1.5 is 1.34799733335753198973335075435098153368185722112713e2147483714
    /// from `bc`, at or above the overflow threshold by c^3 against
    /// (int224.max / 10 + 1)^2 10^67 exactly.
    function testPowHalfPastTheThreshold() external {
        int256 signedCoefficientA = 2629012728145285679841056168393364475926807479622600963406791093691;
        int256 exponentA = 1431655743;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientA, exponentA));
        this.powExternal(
            LibDecimalFloat.packLossless(signedCoefficientA, exponentA), LibDecimalFloat.packLossless(15, -1)
        );
    }

    /// a^b with b log10 a at THRESHOLD_SLACK past each threshold must revert,
    /// and as far inside must return.
    function testPowThresholds() external {
        int256 overflow = LOG10_OVERFLOW / 1e9;
        int256 underflow = int256(type(int32).min) * 1e57;
        uint256[3] memory bases = [uint256(10), 2, 7];
        for (uint256 i = 0; i < bases.length; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            Float a = LibDecimalFloat.packLossless(int256(bases[i]), 0);
            checkPowThreshold(a, thresholdPower(a, overflow + 1 + THRESHOLD_SLACK, true), PowRange.Over);
            checkPowThreshold(a, thresholdPower(a, overflow - THRESHOLD_SLACK, false), PowRange.Inside);
            checkPowThreshold(a, thresholdPower(a, underflow - 1 - THRESHOLD_SLACK, true), PowRange.Under);
            checkPowThreshold(a, thresholdPower(a, underflow + THRESHOLD_SLACK, false), PowRange.Inside);
        }
    }

    /// b = B 10^-57 with b log10 a past `target` 10^-57 in magnitude when
    /// `past`, else short of it, for an a above 1. The oracle's log10 a is
    /// within 1e-67, so truncated to `log` 10^-66, which fits to int32.max, the
    /// exact log10 a is in (log - 1, log + 2) 10^-66.
    function thresholdPower(Float a, int256 target, bool past) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(uint256(signedCoefficient), exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 log = uint256(characteristic) * 1e66 + fraction / 1e4;
        uint256 magnitude = LibTestExactDecimal.abs(target);
        uint256 power = past
            ? Math.mulDiv(magnitude, 1e66, log - 1, Math.Rounding.Ceil)
            : Math.mulDiv(magnitude, 1e66, log + 2, Math.Rounding.Floor);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedPower = int256(power);
        return LibDecimalFloat.packLossless(target < 0 ? -signedPower : signedPower, -57);
    }

    function checkPowThreshold(Float a, Float b, PowRange expected) internal {
        assertTrue(LibTestPowRange.powRange(a, b) == expected, "range");
        if (expected == PowRange.Inside) {
            this.powExternal(a, b);
        } else {
            vm.expectRevert(LibTestPowRange.rangeError(expected == PowRange.Over, a));
            this.powExternal(a, b);
        }
    }

    /// a is c 10^int32.max for c = int224.max / 10 + 1, so a^b overflows
    /// from a 10. No Float power is exactly a 10: c is squarefree, so
    /// a^b = a 10 forces b = ±1/q and a = (a 10)^±q, none of them a Float. So
    /// b is taken just past the error bound either side.
    function testPowEitherSideOfTheOverflowThreshold() external {
        int256 overflow = LOG10_OVERFLOW / 1e9;
        Float a = LibDecimalFloat.packLossless(type(int224).max / 10 + 1, type(int32).max);
        checkPowThreshold(a, thresholdPower(a, overflow + 1 + THRESHOLD_SLACK, true), PowRange.Over);
        checkPowThreshold(a, thresholdPower(a, overflow - THRESHOLD_SLACK, false), PowRange.Inside);

        // a^b is 2.604e-57 relative past a 10, inside the bound, so either
        // outcome is allowed, but a revert reports a.
        powChecked(
            a, LibDecimalFloat.packLossless(1000000000465661273184989617541055125131739873881019438247110325622, -66)
        );
    }

    /// A negative base to an odd power is past the range on its magnitude.
    /// (-2e715827904)^3 is -8e65 10^int32.max, inside it. (-2e715827905)^3 is
    /// -8e2147483715, past (int224.max / 10 + 1) 10^(int32.max + 1), and rounds
    /// at an excess of 28, where the carry fallback checks the unrounded value.
    /// (-2e715827950)^3 rounds at an excess of 163, past the fallback.
    function testPowNegativeOddPowerPastTheRange() external {
        Float three = LibDecimalFloat.packLossless(3, 0);
        (int256 signedCoefficient, int256 exponent) =
            this.powExternal(LibDecimalFloat.packLossless(-2, 715827904), three).unpack();
        assertTrue(LibDecimalFloatImplementation.eq(signedCoefficient, exponent, -8e65, type(int32).max), "inside");

        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(-2), int256(715827905)));
        this.powExternal(LibDecimalFloat.packLossless(-2, 715827905), three);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(-2), int256(715827950)));
        this.powExternal(LibDecimalFloat.packLossless(-2, 715827950), three);
    }

    /// A half power past the range reverts with a, the input of pow. The
    /// largest Float is about 1.35e2147483714 and the least positive is
    /// 1e-2147483648. (1e1431655809)^1.5 is sqrt(10) 1e2147483713, inside, and
    /// (1e1431655810)^1.5 is 1e2147483715, past. (1e-1431655765)^1.5 is
    /// sqrt(10) 1e-2147483648, which sheds to 3 at the floor, and
    /// (1e-1431655766)^1.5 is 1e-2147483649, below it. -1.5 takes the inverse
    /// of each past base to the other side. b = 2^100 + 0.5 trips the squaring
    /// guard before the root.
    function testPowHalfPastTheRange() external {
        Float threeHalves = LibDecimalFloat.packLossless(15, -1);
        Float a = LibDecimalFloat.packLossless(1, 1431655809);
        (int256 signedCoefficient, int256 exponent) = this.powExternal(a, threeHalves).unpack();
        assertTrue(
            LibDecimalFloatImplementation.eq(
                signedCoefficient, exponent, 31622776601683793319988935444327185337196, 2147483673
            ),
            "inside over"
        );
        a = LibDecimalFloat.packLossless(1, 1431655810);
        vm.expectRevert(LibTestPowRange.rangeError(true, a));
        this.powExternal(a, threeHalves);
        a = LibDecimalFloat.packLossless(1, -1431655810);
        vm.expectRevert(LibTestPowRange.rangeError(true, a));
        this.powExternal(a, threeHalves.minus());

        a = LibDecimalFloat.packLossless(1, -1431655765);
        (signedCoefficient, exponent) = this.powExternal(a, threeHalves).unpack();
        assertTrue(LibDecimalFloatImplementation.eq(signedCoefficient, exponent, 3, type(int32).min), "inside under");
        a = LibDecimalFloat.packLossless(1, -1431655766);
        vm.expectRevert(LibTestPowRange.rangeError(false, a));
        this.powExternal(a, threeHalves);
        a = LibDecimalFloat.packLossless(1, 1431655766);
        vm.expectRevert(LibTestPowRange.rangeError(false, a));
        this.powExternal(a, threeHalves.minus());

        Float hugeHalf = LibDecimalFloat.packLossless(int256(2 ** 100) * 10 + 5, -1);
        a = LibDecimalFloat.packLossless(1, 2000000000);
        vm.expectRevert(LibTestPowRange.rangeError(true, a));
        this.powExternal(a, hugeHalf);
        a = LibDecimalFloat.packLossless(1, -2000000000);
        vm.expectRevert(LibTestPowRange.rangeError(false, a));
        this.powExternal(a, hugeHalf);
    }

    /// Issue #297 review: a^1 kept all 67 digits of a, and 2 - 1e-50 put a
    /// 51 digit product above a^2, a 41 digit leg times a.
    function testPowRoundsAtFortyOneDigits() external view {
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
        view
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        Float c = a.pow(b);

        Float roundTrip = c.pow(b.inv());
        assertRoundTrip(a, b, c, roundTrip);
    }

    /// X^Y^(1/Y) = X within `roundTripLogError`.
    function testRoundTripSimple() external view {
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

    function testRoundTripExtremes() external view {
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
    ) external view {
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

    function powExternal(Float a, Float b) external pure returns (Float) {
        return a.pow(b);
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
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(2), int256(0)));
        this.powExternal(a, LibDecimalFloat.packLossless(1, 10));
    }

    /// Issue #239: an integer exponent large enough to double the squared
    /// base's exponent past int256 panicked instead of reverting typed.
    function testPowSquaringPastInt256Underflow() external {
        Float a = LibDecimalFloat.packLossless(1, 1700000000);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1), int256(1700000000)));
        this.powExternal(a, LibDecimalFloat.packLossless(-8, 69));
    }

    function testPowSquaringPastInt256Overflow() external {
        Float a = LibDecimalFloat.packLossless(1, 1700000000);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), int256(1700000000)));
        this.powExternal(a, LibDecimalFloat.packLossless(8, 69));
    }

    /// Issue #149: the inverse of a base this far up the range is below
    /// int32.min, but a small negative power of it is not.
    function testPowNegativeExponentHugeBase() external view {
        Float a = LibDecimalFloat.packLossless(1e66, type(int32).max);
        Float b = LibDecimalFloat.packLossless(1, -7);
        Float product = this.powExternal(a, b.minus()).mul(this.powExternal(a, b));
        assertTrue(product.gt(LibDecimalFloat.packLossless(999, -3)));
        assertTrue(product.lt(LibDecimalFloat.packLossless(1001, -3)));
    }

    /// Issue #297 review: 0.1^2147483645.5 is 316.2277e-2147483648, below
    /// 1e-2147483608, so it sheds digits at the int32 floor. 0.1^2147483648.5
    /// is 0.316e-2147483648 and sheds every digit.
    function testPowFloor() external {
        checkPow(1, -1, 21474836455, -1, 316, type(int32).min);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1), int256(-1)));
        this.powExternal(LibDecimalFloat.packLossless(1, -1), LibDecimalFloat.packLossless(21474836485, -1));
    }

    /// The base's inverse is the result when the power is -1, so it still
    /// underflows: 10^-2147483713.
    function testPowMinusOneHugeBaseUnderflows() external {
        Float a = LibDecimalFloat.packLossless(1e66, type(int32).max);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1e66), int256(type(int32).max)));
        this.powExternal(a, LibDecimalFloat.packLossless(-1, 0));
    }

    /// pow(a, -1) is the exact 1/a rounded to 41 digits, half away from zero.
    /// 1/(c 10^e) is (q + r/m) 10^(-62 - e) for q, r the quotient and remainder
    /// of 1e62 by m = |c|, and q has at least 43 digits.
    function testPowMinusOneIsInv(int64 c, int16 e) external view {
        vm.assume(c != 0);
        uint256 m = LibTestExactDecimal.abs(c);
        uint256 q = 1e62 / m;
        uint256 r = 1e62 % m;
        uint256 guard = 1;
        int256 exponent = -62 - int256(e);
        while (q / guard >= 1e41) {
            guard *= 10;
            exponent++;
        }
        uint256 rounded = q / guard;
        if (2 * ((q % guard) * m + r) >= guard * m) {
            rounded++;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = c < 0 ? -int256(rounded) : int256(rounded);
        (int256 actualCoefficient, int256 actualExponent) =
            this.powExternal(LibDecimalFloat.packLossless(c, e), LibDecimalFloat.packLossless(-1, 0)).unpack();
        assertTrue(
            LibTestExactDecimal.eq(actualCoefficient, actualExponent, signedCoefficient, exponent),
            "pow(a, -1) != 1/a rounded"
        );
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
    ) external view {
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
    function checkPowNegativeBoundary(Float b, int256 lastExponent, int256 expectedCoefficient) internal {
        (int256 coefficient, int256 exponent) =
            this.powExternal(LibDecimalFloat.packLossless(1e66, lastExponent), b).unpack();
        assertEq(coefficient, expectedCoefficient, "coefficient");
        assertEq(exponent, type(int32).min, "exponent");

        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1e66), lastExponent + 1));
        this.powExternal(LibDecimalFloat.packLossless(1e66, lastExponent + 1), b);
    }

    function testPowNegativeExponentHugeBaseBoundary() external {
        checkPowNegativeBoundary(LibDecimalFloat.packLossless(-1, 0), 2147483582, 1);
        checkPowNegativeBoundary(LibDecimalFloat.packLossless(-10000001, -7), 2147483367, 1);
        checkPowNegativeBoundary(LibDecimalFloat.packLossless(-1000001, -6), 2147481434, 3);
        checkPowNegativeBoundary(LibDecimalFloat.packLossless(-2, 0), 1073741758, 1);
    }

    /// The inverse of the smallest base is 10^2147483648, which still packs,
    /// so every power past -1 overflows, typed.
    function testPowNegativeExponentTinyBaseOverflows() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);

        (int256 coefficient, int256 exponent) = this.powExternal(a, LibDecimalFloat.packLossless(-1, 0)).unpack();
        assertEq(coefficient, 1e40, "coefficient");
        assertEq(exponent, 2147483608, "exponent");

        bytes memory overflow = abi.encodeWithSelector(ExponentOverflow.selector, int256(1), int256(type(int32).min));
        vm.expectRevert(overflow);
        this.powExternal(a, LibDecimalFloat.packLossless(-11, -1));

        vm.expectRevert(overflow);
        this.powExternal(a, LibDecimalFloat.packLossless(-2, 0));

        vm.expectRevert(overflow);
        this.powExternal(a, LibDecimalFloat.packLossless(-1, 9));

        // The squared base passes int128 before the loop ends.
        vm.expectRevert(overflow);
        this.powExternal(a, LibDecimalFloat.packLossless(-1, 30));
    }

    /// Issue #276's counterexample, bit for bit: a full-width coefficient base
    /// raised to a negative power with a 233-bit integer part.
    function testPowIssue276Counterexample() external {
        Float a = Float.wrap(0x5061727365206572726f7220286e656729000000000000000000000000000000);
        Float b = Float.wrap(0x00000003b58e88c75313ec9d329eaaa18fb92f75215b170fffffffffffffffff);
        // a's coefficient and exponent, its low 224 and high 32 bits, from
        // `bc`.
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentUnderflow.selector,
                int256(10649868514120859750743193552471890618207833841010459988146104827904),
                int256(1348563571)
            )
        );
        this.powExternal(a, b);
    }

    /// The concrete counterexample surfaced by `testRoundTripFuzzPow`: a is 1,
    /// whose round trip leg `c.pow(b.inv())` reverted `WithTargetExponentOverflow`
    /// on an inverse with exponent 363177628, until 1^b returned 1 (#312).
    function testRoundTripOneHugeExponent() external view {
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

        // A negative b inverts a first, and the error reports a.
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(2), int256(0)));
        this.powExternal(LibDecimalFloat.packLossless(2, 0), b.minus());
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(5), int256(-1)));
        this.powExternal(LibDecimalFloat.packLossless(5, -1), b.minus());

        // A whole b keeps a negative base, by its magnitude.
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(-2), int256(0)));
        this.powExternal(LibDecimalFloat.packLossless(-2, 0), b);

        // b = 1e76 fits int256, and (1 - 1e-67)^(±1e76) is 10^(∓434294481.9)
        // with every truncation moving it under 9 in log10: inside the range.
        Float c = this.powExternal(below, LibDecimalFloat.packLossless(1, 76));
        assertTrue(c.gt(LibDecimalFloat.packLossless(1, -434294501)), "1e76 below floor");
        assertTrue(c.lt(LibDecimalFloat.packLossless(1, -434294461)), "1e76 below ceiling");
        c = this.powExternal(below, LibDecimalFloat.packLossless(-1, 76));
        assertTrue(c.gt(LibDecimalFloat.packLossless(1, 434294461)), "-1e76 below floor");
        assertTrue(c.lt(LibDecimalFloat.packLossless(1, 434294501)), "-1e76 below ceiling");

        // 5.7e76 still fits int256 and goes to the squaring loop.
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1e67 + 1), int256(-67)));
        this.powExternal(above, LibDecimalFloat.packLossless(57, 75));

        // The largest integer b the squaring loop takes, by the closest a on
        // either side of 1, still lands past the range on that side.
        Float widest = LibDecimalFloat.packLossless(type(int256).max / 1e10, 10);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1e67 + 1), int256(-67)));
        this.powExternal(above, widest);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1e67 - 1), int256(-67)));
        this.powExternal(below, widest);
    }

    /// The most negative Float as b, or as a base with a whole b, does not
    /// pack negated. It reverted `ExponentOverflow` whichever side of the range
    /// the power is on.
    function testPowMostNegativeFloat() external {
        Float most = LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE;

        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(2), int256(0)));
        this.powExternal(LibDecimalFloat.packLossless(2, 0), most);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(5), int256(-1)));
        this.powExternal(LibDecimalFloat.packLossless(5, -1), most);

        // most is int224.min 10^int32.max.
        vm.expectRevert(
            abi.encodeWithSelector(ExponentUnderflow.selector, int256(type(int224).min), int256(type(int32).max))
        );
        this.powExternal(most, LibDecimalFloat.packLossless(-1, 0));
        vm.expectRevert(
            abi.encodeWithSelector(ExponentOverflow.selector, int256(type(int224).min), int256(type(int32).max))
        );
        this.powExternal(most, LibDecimalFloat.packLossless(2, 0));
        assertEq(
            Float.unwrap(this.powExternal(most, LibDecimalFloat.FLOAT_ZERO)), Float.unwrap(LibDecimalFloat.FLOAT_ONE)
        );
    }

    function testRoundTripFuzzPow(Float a, Float b) external view {
        roundTripFuzz(a, b);
    }

    /// Each leg returns or reverts only as `powChecked` derives from its own
    /// inputs.
    function roundTripFuzz(Float a, Float b) internal view {
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
    function testPowExactRoots(uint256 n, int256 k, uint256 which) external view {
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
        return x.pow10();
    }

    /// (10^k)^b is pow10(k b) exactly, as log10(10^k) is exactly k.
    function testPowPowersOfTenMatchPow10(int256 k, int256 signedCoefficientB, int256 exponentB) external view {
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
    ) external view {
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
    ) external view {
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
