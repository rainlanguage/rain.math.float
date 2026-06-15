// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {
    ZeroNegativePower,
    PowNegativeBase,
    ExponentOverflow,
    ExponentUnderflow,
    MaximizeOverflow,
    MulDivOverflow
} from "src/error/ErrDecimalFloat.sol";
import {WithTargetExponentOverflow} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {console2} from "forge-std-1.16.1/src/Test.sol";

contract LibDecimalFloatPowTest is LogTest {
    using LibDecimalFloat for Float;

    function diffLimit() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(90, -3);
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
        checkPow(5, 0, 13, 0, 1220703125e3, -3);
        // 0.5 ^ 30 = 9.3132257462e-10
        checkPow(5e37, -38, 3e37, -36, 9.31322574615478515625e66, -66 - 10);
        // 0.5 ^ 60 = 8.6736174e-19
        checkPow(5e37, -38, 6e37, -36, 8.67361737988403547205962240695953369140625e66, -66 - 19);
        // Issues found in fuzzing from here.
        // 8.74538833058575652925523041334332969215722254574942755921268
        // 633458353995901024989835096189737575745161722050119812356738
        // 280497952674131705456780502007277553280469772918551495558754.. e48726
        checkPow(9998, 0, 12182, 0, 8.745388330585756529255230413343329692157222545749427559212686334583e66, 48660);
        // 783767830987557747626713214413804946776011874600896376644775
        // 737184122084874429184097039019333746546707574834238563105201
        // 601306157447680045947322051787243602068130996873443425180605.. e60909
        checkPow(99998, 0, 12182, 0, 7.837678309875577476267132144138049467760118746008963766447757371841e66, 60843);
        // 99999 ^ 12182 = 8.853071703048649170130397094169464632911643045383977634639832230468640539353...e60909
        // 8.853071703048649170130397094169464632911643045383977634639832230468640539353e75 e60909
        checkPow(99999, 0, 12182, 0, 8.853071703048649170130397094169464632911643045383977634639832230468e66, 60843);
        // 339181340264437326833371724490610161292169214732614339791381
        // 077839070153170394796050442886983271326431055976856477078397
        // 05146977035502651573305246467342588868622024704
        checkPow(1785215562, 0, 18, 0, 3.39181340264437326833371724490610161292169214732614339791381077839e66, 100);

        // 1.1295514523570834631500830078383428992881418895780763453451
        // 678937388891303478211805800680150846537485488564609577873121
        // 201465463889111526015508340821749525697772648457658570819388
        // 829891895455052532621e-60910
        // very close, final two digits are different
        checkPow(99999, 0, -12182, 0, 1.1295514523570834631500830078383428992881418895780763453451678937375e67, -60977);

        {
            (int256 signedCoefficientE, int256 exponentE) = LibDecimalFloat.FLOAT_E.unpack();
            checkPow(signedCoefficientE, exponentE, 1, 0, signedCoefficientE, exponentE);
        }

        checkPow(1.0029e67, -67, 0.41e2, -2, 1.001e3, -3);
        checkPow(96001e62, -62, 0.00115e5, -5, 1.014e3, -3);
    }

    /// a^b is error for negative a and all b.
    /// In the future we may support negative bases with integer exponents.
    /// https://github.com/rainlanguage/rain.math.float/issues/88
    function testNegativePowError(Float a, Float b) external {
        // We can't simply minus 0 to get a negative base.
        vm.assume(!a.isZero());
        // Anything to 0 power is 1, including negative base.
        vm.assume(!b.isZero());
        if (a.gt(LibDecimalFloat.FLOAT_ZERO)) {
            a = a.minus();
        }
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        vm.expectRevert(abi.encodeWithSelector(PowNegativeBase.selector, signedCoefficientA, exponentA));
        this.powExternal(a, b);
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

    /// a^1 = a for all a >= 0 (negative bases revert per current semantics).
    function testPowBOne(Float a) external {
        vm.assume(!a.isZero());
        a = a.abs();
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        unchecked {
            int256 exponent = 0;
            for (int256 i = 1; exponent >= -67;) {
                checkPow(signedCoefficientA, exponentA, i, exponent, signedCoefficientA, exponentA);
                exponent--;
                i *= 10;
            }
        }
    }

    function checkRoundTrip(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        address tables = logTables();
        Float c = a.pow(b, tables);

        Float roundTrip = c.pow(b.inv(), tables);

        Float diff = a.div(roundTrip).sub(LibDecimalFloat.FLOAT_ONE).abs();

        assertTrue(!diff.gt(diffLimit()), "diff");
    }

    /// X^Y^(1/Y) = X
    /// Can generally round trip whatever within `diffLimit` of the original
    /// value.
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
            abi.encodeWithSelector(
                ExponentOverflow.selector,
                43632686345562428988582910876713633851545835514376216610528325287869870302082,
                3010299880
            )
        );
        this.powExternal(a, LibDecimalFloat.packLossless(1, 10));
    }

    /// The complete set of custom errors `pow` is designed to throw, derived by
    /// reading the implementation. Each leg of the round trip is the same `pow`
    /// call, so both legs share this set.
    ///   - `ZeroNegativePower`: 0 raised to a negative power.
    ///   - `PowNegativeBase`: negative base (unsupported).
    ///   - `ExponentOverflow`: the result (or a `log10`/`pow10`/squaring
    ///     intermediate) exceeds `int32` / `add` exponent range. This is the
    ///     squaring-loop overflow pinned by `testPowIntegerExponentSquaringOverflow`.
    ///   - `ExponentUnderflow`: an intermediate rescale produces a magnitude
    ///     smaller than any representable Float (`packArithmeticResult`).
    ///   - `WithTargetExponentOverflow`: `pow10` cannot rescale the
    ///     characteristic to exponent 0 without overflowing the coefficient.
    ///   - `MaximizeOverflow`: `maximizeFull` (inside `log10`/`div`) cannot
    ///     maximize an intermediate coefficient.
    ///   - `MulDivOverflow`: the 512-bit `mulDiv` inside `mul`/`div` overflows.
    /// `DivisionByZero`, `Log10Zero` and `Log10Negative` are intentionally
    /// excluded: `pow` only ever inverts/logs a strictly positive base, so they
    /// are unreachable. A low-level `Panic` (e.g. `0x11` arithmetic overflow) is
    /// also excluded by construction, so an unexpected revert is no longer
    /// silently swallowed.
    function assertExpectedPowError(bytes memory reason) internal {
        bytes4 selector = bytes4(reason);
        bool expected = selector == ZeroNegativePower.selector || selector == PowNegativeBase.selector
            || selector == ExponentOverflow.selector || selector == ExponentUnderflow.selector
            || selector == WithTargetExponentOverflow.selector || selector == MaximizeOverflow.selector
            || selector == MulDivOverflow.selector;
        if (!expected) {
            console2.log("unexpected pow revert selector:");
            console2.logBytes4(selector);
            assertTrue(false, "unexpected pow revert");
        }
    }

    /// Pins the concrete counterexample surfaced by `testRoundTripFuzzPow`
    /// where the first leg `a.pow(b)` succeeds but the round-trip leg
    /// `c.pow(b.inv())` reverts with `WithTargetExponentOverflow`. A tiny
    /// coefficient combined with the large inverted exponent produces an
    /// unrepresentable rescale target during the round-trip. The fuzz test
    /// absorbs this in a try/catch as "can't round-trip this input"; this named
    /// test pins exactly which leg reverts and with which error, so a
    /// regression that shifts the revert boundary surfaces here instead of
    /// being silently swallowed by the fuzz catch.
    function testRoundTripSecondLegRevert() external {
        Float a = Float.wrap(bytes32(uint256(1)));
        Float b = Float.wrap(bytes32(0xea5a58dfdcc79c60ac38b8284569e4519fda5eaaffec2a3d22027a4af1969e13));

        // First leg succeeds.
        Float c = this.powExternal(a, b);

        // Round-trip leg reverts with the exact rescale-overflow error.
        Float inv = b.inv();
        vm.expectRevert(
            abi.encodeWithSelector(
                WithTargetExponentOverflow.selector,
                int256(2696051936649033486196409040598252262955326698850935392994226984449),
                int256(363177628),
                int256(0)
            )
        );
        this.powExternal(c, inv);
    }

    function testRoundTripFuzzPow(Float a, Float b) external {
        try this.powExternal(a, b) returns (Float c) {
            // If C is 1 then either a == 1 or b == 0 (or b rounds to 0).
            // The case where a is 1 should round trip, but all other cases won't.
            if (a.eq(LibDecimalFloat.FLOAT_ONE) || !c.eq(LibDecimalFloat.FLOAT_ONE)) {
                if (b.isZero()) {
                    assertTrue(c.eq(LibDecimalFloat.FLOAT_ONE), "b is 0 so c should be 1");
                } else if (!(c.isZero() && b.lt(LibDecimalFloat.FLOAT_ZERO))) {
                    Float inv = b.inv();
                    // The round-trip pow can still error on intermediate
                    // overflow even when both legs of the original input
                    // were well-formed (e.g. a tiny coefficient combined
                    // with a large inverted exponent produces an
                    // unrepresentable rescale target). Treat those the same
                    // as the first leg: a revert is "we can't round-trip
                    // this input", not a math regression.
                    try this.powExternal(c, inv) returns (Float roundTrip) {
                        if (!roundTrip.isZero()) {
                            Float diff = a.div(roundTrip).sub(LibDecimalFloat.FLOAT_ONE).abs();
                            assertTrue(!diff.gt(diffLimit()), "diff");
                        }
                    } catch (bytes memory reason) {
                        // Can't round trip something that errors, but only if it
                        // errors with an error `pow` is designed to throw. An
                        // unexpected revert (e.g. a low-level `Panic`) fails the
                        // test rather than being silently swallowed.
                        assertExpectedPowError(reason);
                    }
                }
            }
        } catch (bytes memory reason) {
            // Can't round trip something that errors, but only if it errors with
            // an error `pow` is designed to throw. An unexpected revert (e.g. a
            // low-level `Panic`) fails the test rather than being silently
            // swallowed.
            assertExpectedPowError(reason);
        }
    }
}
