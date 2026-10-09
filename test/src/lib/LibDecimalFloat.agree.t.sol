// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {
    LibDecimalFloatImplementation,
    ADD_MAX_EXPONENT_DIFF
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AgreeToleranceNegative, AgreeNoPositiveTolerance} from "src/error/ErrDecimalFloat.sol";

// The exponent gap at which the spread subtraction stops seeing the smaller
// operand at all, so the spread reads as exactly the larger one. `add` aligns
// without loss up to `ADD_MAX_EXPONENT_DIFF` and drops the smaller operand one
// past it.
//
// `ADD_MAX_EXPONENT_DIFF` is a `uint256` of 76 and the exponent walk works in
// `int256`, so the cast is exact and cannot truncate.
//forge-lint: disable-next-line(unsafe-typecast)
int256 constant BOUNDARY_CLIFF_GAP = int256(ADD_MAX_EXPONENT_DIFF) + 1;

contract LibDecimalFloatAgreeTest is Test {
    using LibDecimalFloat for Float;

    function f(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    function minNegative() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(type(int224).min, type(int32).max);
    }

    function maxPositive() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(type(int224).max, type(int32).max);
    }

    /// `agree` is an internal library call, so it inlines and its reverts land
    /// at the test's own call depth where `vm.expectRevert` cannot see them.
    /// The revert tests go through here, matching how the rest of this suite
    /// asserts library reverts.
    function agreeExternal(Float absolute, Float proportional, Float lowest, Float highest)
        external
        pure
        returns (bool)
    {
        return LibDecimalFloat.agree(absolute, proportional, lowest, highest);
    }

    /// The proportional tolerance is of the LARGER MAGNITUDE of the two
    /// extremes, so with positive values it is a proportion of the highest.
    ///
    /// 100 - 99 == 1 == 0.01 * 100, so this sits exactly on the limit and is
    /// accepted, because the check is `<=`. Anchoring on the lower value would
    /// give 0.01 * 99 == 0.99 and reject it, so these distinguish the two
    /// anchors rather than merely exercising one.
    function testAgreeProportionalBoundary() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(99, 0), f(100, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(98999, -3), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(99001, -3), f(100, 0)));
    }

    /// The absolute tolerance is in the same units as the values and does not
    /// scale with them.
    function testAgreeAbsoluteBoundary() external pure {
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(100, 0), f(101, 0)));
        assertFalse(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(100, 0), f(101001, -3)));
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(100, 0), f(100999, -3)));
    }

    /// The limit is the LARGER of the two terms, not their sum.
    ///
    /// With an absolute tolerance of 0.5, a proportional tolerance of 0.01 and
    /// a highest of 100, the larger term is 1 and the sum would be 1.5. A
    /// spread of 1.2 falls between them, so it distinguishes the two forms
    /// rather than merely exercising one.
    function testAgreeLimitIsTheLargerNotTheSum() external pure {
        assertTrue(LibDecimalFloat.agree(f(5, -1), f(1, -2), f(99, 0), f(100, 0)));
        assertFalse(LibDecimalFloat.agree(f(5, -1), f(1, -2), f(988, -1), f(100, 0)));
    }

    /// Either tolerance alone carries the check when the other is zero.
    function testAgreeOneToleranceZero() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(99, 0), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(100, 0), f(101, 0)));
    }

    /// The magnitude is taken, so negatives behave as positives reflected
    /// through zero rather than being rejected outright.
    function testAgreeNegativeValues() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(-100, 0), f(-99, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(-100, 0), f(-98999, -3)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(-100, 0), f(-100, 0)));
    }

    /// Values symmetric about zero are the furthest apart anything can be
    /// relative to its own magnitude: the spread is twice the anchor, so a
    /// proportional tolerance has to reach 200%.
    function testAgreeSymmetricAboutZero() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(2, 0), f(-1, 0), f(1, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(199, -2), f(-1, 0), f(1, 0)));
        assertTrue(LibDecimalFloat.agree(f(2, 0), f(0, 0), f(-1, 0), f(1, 0)));
    }

    /// WHY BOTH TOLERANCES EXIST. A proportional tolerance collapses as the
    /// values approach zero, because the quantity it is a proportion of
    /// shrinks with them. The absolute term is what covers that region.
    function testAgreeNearZero() external pure {
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(-1, -3), f(1, -3)));
        assertTrue(LibDecimalFloat.agree(f(1, -2), f(0, 0), f(-1, -3), f(1, -3)));
    }

    /// THE REASON THIS CANNOT BE COMPOSED FROM THE PUBLIC SURFACE.
    ///
    /// Both `abs` and `sub` revert `ExponentOverflow` on these values, because
    /// the exponent is already at its maximum and neither the magnitude of the
    /// most negative coefficient nor the spread across the whole range fits a
    /// packed value. `agree` answers instead of reverting, which is only
    /// possible by staying below that surface.
    function testAgreeAcrossTheWholeRange() external pure {
        // A spread this wide is not within a 1% proportional tolerance.
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, -2), minNegative(), maxPositive()));
        // The most negative value against itself has a zero spread, so it
        // agrees. The packed `abs` cannot even be asked this question.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), minNegative(), minNegative()));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), maxPositive(), maxPositive()));
    }

    /// Identical values agree under any valid tolerance, however small.
    function testAgreeZeroSpread() external pure {
        // The smallest positive tolerance still accepts a zero spread, and
        // still refuses a spread of 1.
        assertTrue(LibDecimalFloat.agree(f(1, -20), f(0, 0), f(100, 0), f(100, 0)));
        assertFalse(LibDecimalFloat.agree(f(1, -20), f(0, 0), f(100, 0), f(101, 0)));
        // And via the proportional term alone.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -20), f(100, 0), f(100, 0)));
    }

    /// The comparison is numerical, so the representation of the tolerances
    /// and the values does not change the answer.
    function testAgreeNumericalEquality() external pure {
        // 0.01 written three ways, against the same boundary.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(99, 0), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(10, -3), f(99, 0), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(100, -4), f(990, -1), f(1000, -1)));
    }

    /// The anchor is whichever end is further from zero, so for values
    /// straddling zero it is not simply the highest.
    function testAgreeStraddlingZero() external pure {
        // Spread 101, anchor 100, so 1.01 reaches it and 1 does not.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(101, -2), f(-1, 0), f(100, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, 0), f(100, 0)));
        // Reflected: the negative end is now the larger magnitude.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(101, -2), f(-100, 0), f(1, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-100, 0), f(1, 0)));
    }

    /// A zero anchor collapses the proportional term whatever its size, so
    /// only the absolute term can accept a spread there.
    function testAgreeZeroAnchor() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(0, 0), f(0, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1000, 0), f(0, 0), f(0, 0)));
        // The anchor is the larger magnitude, so with a highest of 1 it is 1,
        // not 0.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(0, 0), f(1, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(99, -2), f(0, 0), f(1, 0)));
    }

    /// The proportional term scales with the values and the absolute term
    /// does not, which is the whole reason for taking both.
    function testAgreeScaling() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(1000, 0), f(1001, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(10, 0), f(11, 0)));
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(1000, 0), f(1001, 0)));
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(10, 0), f(11, 0)));
    }

    /// AN INDEPENDENT ORACLE, composed in plain integer arithmetic sharing
    /// nothing with this library.
    ///
    /// Everything else here is a hand-derived assertion, so a misread of the
    /// formula would be written into both the code and the expectations. This
    /// computes the predicate as exact integers at a fixed scale, so the two
    /// can disagree.
    ///
    /// THE DOMAIN IS RESTRICTED ON PURPOSE. Values and tolerances are integers
    /// at exponent 0 within a range where the products fit an int256 exactly,
    /// so both paths are lossless and must agree exactly. Widening it would
    /// surface rounding differences rather than formula differences.
    function testAgreeAgainstIntegerOracle(
        int256 lowestSeed,
        int256 highestSeed,
        uint256 absoluteSeed,
        uint256 proportionalSeed
    ) external pure {
        int256 lowestValue = bound(lowestSeed, -1e12, 1e12);
        int256 highestValue = bound(highestSeed, -1e12, 1e12);
        if (highestValue < lowestValue) {
            (lowestValue, highestValue) = (highestValue, lowestValue);
        }
        // Absolute is an integer; proportional is hundredths, so the product
        // with an anchor up to 1e12 stays exact.
        int256 absoluteValue = int256(bound(absoluteSeed, 0, 1e12));
        int256 proportionalHundredths = int256(bound(proportionalSeed, 0, 100000));
        // `agree` rejects a pair with no positive tolerance, so nudge rather
        // than discard the run: bounding spends every run on a valid call.
        if (absoluteValue == 0 && proportionalHundredths == 0) {
            absoluteValue = 1;
        }

        int256 spread = highestValue - lowestValue;
        int256 anchor = highestValue < 0
            ? -lowestValue
            : (lowestValue < 0 && -lowestValue > highestValue ? -lowestValue : highestValue);
        // Clear the denominator: spread*100 <= max(absolute*100, proportional*anchor).
        int256 proportionalTerm = proportionalHundredths * anchor;
        int256 absoluteTerm = absoluteValue * 100;
        bool expected = spread * 100 <= (absoluteTerm > proportionalTerm ? absoluteTerm : proportionalTerm);

        assertEq(
            LibDecimalFloat.agree(
                f(absoluteValue, 0), f(proportionalHundredths, -2), f(lowestValue, 0), f(highestValue, 0)
            ),
            expected
        );
    }

    /// A tolerance at the top of the range accepts rather than reverting: the
    /// multiplication scales the coefficient down and raises the exponent
    /// instead of overflowing, and nothing is packed back.
    function testAgreeExtremeTolerance() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), maxPositive(), f(1, 0), f(2, 0)));
        assertTrue(LibDecimalFloat.agree(maxPositive(), f(0, 0), f(1, 0), f(2, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), maxPositive(), minNegative(), maxPositive()));
    }

    /// The comparison is exact only to representable precision, and this pins
    /// that so the natspec claim cannot drift silently.
    ///
    /// The real spread of `-1e-100` and `1` is `1 + 1e-100`, which needs 101
    /// significant digits against the coefficient's 76. The subtraction
    /// discards the small term, the spread reads as exactly `1`, and a limit of
    /// `1` is therefore met. An exact comparison would refuse all three of
    /// these.
    function testAgreeBoundaryExactOnlyToRepresentablePrecision() external pure {
        // A proportional tolerance of 1 against an anchor of 1 is a limit of 1.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, -100), f(1, 0)));
        // The same limit reached by the absolute term instead.
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(-1, -100), f(1, 0)));
        // And both terms at once, so neither branch of the `max` escapes it.
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(1, 0), f(-1, -100), f(1, 0)));
    }

    /// The mechanism behind the boundary, asserted directly rather than
    /// inferred: `sub` itself reports the spread as exactly `1`, so `agree` is
    /// agreeing with the library's own arithmetic rather than departing from
    /// it.
    function testAgreeBoundarySpreadIsExactlyOne() external pure {
        (int256 lowestCoefficient, int256 lowestExponent) = f(-1, -100).unpack();
        (int256 highestCoefficient, int256 highestExponent) = f(1, 0).unpack();
        (int256 spreadCoefficient, int256 spreadExponent) =
            LibDecimalFloatImplementation.sub(highestCoefficient, highestExponent, lowestCoefficient, lowestExponent);
        (int256 oneCoefficient, int256 oneExponent) = f(1, 0).unpack();
        assertTrue(
            LibDecimalFloatImplementation.eq(spreadCoefficient, spreadExponent, oneCoefficient, oneExponent),
            "spread is not exactly one"
        );
    }

    /// Just inside the coefficient's reach the small term survives, the spread
    /// exceeds the limit, and the check refuses. This is what shows the
    /// boundary is a precision limit rather than `agree` ignoring small terms
    /// in general.
    function testAgreeSmallTermRefusedWhenRepresentable() external pure {
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, -60), f(1, 0)));
        assertFalse(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(-1, -60), f(1, 0)));
    }

    /// Walks the exponent gap to LOCATE the precision cliff rather than
    /// sampling a point either side of it. Below the cliff the small term
    /// survives and the spread exceeds the limit; at and past it the term is
    /// discarded and the spread reads as exactly the limit.
    ///
    /// Also asserts the transition happens exactly once. A scatter of accepts
    /// and refusals would mean something other than a precision limit is
    /// deciding, which sampling two points could never distinguish.
    function testAgreeBoundaryCliffLocated() external pure {
        bool seenAccepted = false;
        int256 firstAccepted = 0;
        for (int256 n = 1; n <= 120; n++) {
            bool accepted = LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, -n), f(1, 0));
            if (accepted) {
                if (!seenAccepted) {
                    seenAccepted = true;
                    firstAccepted = n;
                }
            } else {
                // A term that has already vanished cannot reappear as the gap
                // widens further.
                assertFalse(seenAccepted, "acceptance is not monotone in the exponent gap");
            }
        }
        assertTrue(seenAccepted, "never accepted anywhere in the walk");
        // Both operands are maximized to the same order of magnitude before
        // alignment, so the gap the alignment sees is the exponent difference,
        // and it gives up one past ADD_MAX_EXPONENT_DIFF.
        assertEq(firstAccepted, BOUNDARY_CLIFF_GAP, "the cliff moved");
    }

    /// The cliff is a RELATIVE precision limit, so scaling the whole problem by
    /// a power of ten moves it not at all. Anchoring on an absolute exponent
    /// instead would shift the cliff with the scale.
    function testAgreeBoundaryCliffIsScaleInvariant() external pure {
        int256 cliff = BOUNDARY_CLIFF_GAP;
        for (int256 k = -30; k <= 30; k += 10) {
            // One below the cliff: the small term survives, so it is refused.
            assertFalse(
                LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, k - cliff + 1), f(1, k)), "refused side moved with scale"
            );
            // At the cliff: the term is discarded and the spread reads exactly
            // as the limit.
            assertTrue(
                LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, k - cliff), f(1, k)), "accepted side moved with scale"
            );
        }
    }

    /// The same spread reached with the operands placed the other way about
    /// zero behaves identically. `-1e-100` against `1` and `-1` against
    /// `1e-100` are both a real spread of `1 + 1e-100` with an anchor of `1`,
    /// so neither the sign of the larger operand nor which side carries the
    /// tiny magnitude changes the outcome.
    function testAgreeBoundaryMirroredAboutZero() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, -100), f(1, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, 0), f(1, -100)));
        // And one below the cliff both ways round.
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, -60), f(1, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(-1, 0), f(1, -60)));
    }

    /// The loss is ONE DIRECTIONAL. When the discarded term would have made the
    /// spread SMALLER, the truncated answer and the exact answer agree, so the
    /// imprecision cannot cause a refusal.
    ///
    /// Here both extremes are positive, so the spread `1 - 1e-100` is slightly
    /// under the limit of `1`, and it reads as exactly `1`. Both the truncated
    /// and the exact comparison accept, unlike the opposite-sign case where
    /// they differ.
    function testAgreeBoundaryLossIsOneDirectional() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(1, -100), f(1, 0)));
        // Well inside precision the same shape is still accepted, because the
        // spread is genuinely below the limit rather than rounded to it.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, 0), f(1, -60), f(1, 0)));
    }

    /// A refusal is always sound. Truncation only ever reduces the spread's
    /// magnitude, so if the computed spread already exceeds the limit then the
    /// exact spread does too. Fuzzed across gaps that straddle the cliff, a
    /// refusal must be backed by `sub` reporting a spread above the limit.
    function testAgreeRefusalIsAlwaysBackedByTheSpread(int256 gap, int256 anchorExponent) external pure {
        gap = bound(gap, 1, 120);
        anchorExponent = bound(anchorExponent, -40, 40);

        Float lowest = f(-1, anchorExponent - gap);
        Float highest = f(1, anchorExponent);

        if (LibDecimalFloat.agree(f(0, 0), f(1, 0), lowest, highest)) {
            return;
        }

        (int256 lowestCoefficient, int256 lowestExponent) = lowest.unpack();
        (int256 highestCoefficient, int256 highestExponent) = highest.unpack();
        (int256 spreadCoefficient, int256 spreadExponent) =
            LibDecimalFloatImplementation.sub(highestCoefficient, highestExponent, lowestCoefficient, lowestExponent);
        (int256 limitCoefficient, int256 limitExponent) = highest.unpack();
        assertTrue(
            LibDecimalFloatImplementation.gt(spreadCoefficient, spreadExponent, limitCoefficient, limitExponent),
            "refused without the spread exceeding the limit"
        );
    }

    /// Away from the cliff the check is exactly the integer comparison, for
    /// every gap the coefficient can hold. This bounds the imprecision to the
    /// cliff rather than leaving it as a property that might apply anywhere.
    function testAgreeMatchesIntegerComparisonInsidePrecision(int256 spreadUnits, int256 limitUnits) external pure {
        spreadUnits = bound(spreadUnits, 0, 1e18);
        limitUnits = bound(limitUnits, 1, 1e18);

        // lowest = 0, highest = spreadUnits, so the spread is exact and the
        // anchor is the highest. An absolute tolerance keeps the limit exact
        // too, so the whole comparison is representable.
        bool expected = spreadUnits <= limitUnits;
        assertEq(
            LibDecimalFloat.agree(f(limitUnits, 0), f(0, 0), f(0, 0), f(spreadUnits, 0)),
            expected,
            "diverged from the integer comparison inside precision"
        );
    }

    /// A NEGATIVE TOLERANCE IS REJECTED, either side.
    ///
    /// It cannot mean anything: the spread is a distance and so non-negative,
    /// which makes `spread <= negative` unsatisfiable, and under the `max` the
    /// negative term is inert — it cannot cancel the other term, only fail to
    /// be it. Left unrejected it would be silently dominated and the check
    /// would pass on a malformed tolerance.
    function testAgreeRejectsNegativeTolerance() external {
        vm.expectRevert(abi.encodeWithSelector(AgreeToleranceNegative.selector, f(-1, 0), f(1, -2)));
        this.agreeExternal(f(-1, 0), f(1, -2), f(99, 0), f(100, 0));

        vm.expectRevert(abi.encodeWithSelector(AgreeToleranceNegative.selector, f(1, 0), f(-1, -2)));
        this.agreeExternal(f(1, 0), f(-1, -2), f(99, 0), f(100, 0));

        // Rejected even where the other term would have accepted the spread on
        // its own, which is the case that would otherwise pass silently.
        vm.expectRevert(abi.encodeWithSelector(AgreeToleranceNegative.selector, f(-1, 0), f(1, 0)));
        this.agreeExternal(f(-1, 0), f(1, 0), f(99, 0), f(100, 0));

        // And where both are negative.
        vm.expectRevert(abi.encodeWithSelector(AgreeToleranceNegative.selector, f(-1, 0), f(-1, 0)));
        this.agreeExternal(f(-1, 0), f(-1, 0), f(100, 0), f(100, 0));
    }

    /// NEITHER TOLERANCE POSITIVE IS REJECTED. The limit would be zero and
    /// `agree` would degenerate into exact equality, which `eq` answers
    /// directly, so a caller that meant to set a tolerance and set none is
    /// misunderstood rather than served.
    function testAgreeRejectsNoPositiveTolerance() external {
        vm.expectRevert(abi.encodeWithSelector(AgreeNoPositiveTolerance.selector, f(0, 0), f(0, 0)));
        this.agreeExternal(f(0, 0), f(0, 0), f(100, 0), f(100, 0));
    }

    /// A packed zero with a NON-ZERO EXPONENT is rejected the same way, which is
    /// what makes the guard numeric rather than bytewise.
    ///
    /// `packLossless` cannot construct one — it canonicalises every zero to
    /// `FLOAT_ZERO`, which the first two assertions pin, so a test written with
    /// `f(0, 5)` silently tests the canonical case twice. These are built with
    /// `Float.wrap` instead: the exponent occupies the high 32 bits, so a zero
    /// coefficient with exponent 5 and with exponent -5 are distinct words that
    /// are both numerically zero.
    function testAgreeRejectsNonCanonicalZeroTolerances() external {
        Float zeroExponentFive = Float.wrap(bytes32(uint256(5) << 224));
        Float zeroExponentMinusFive = Float.wrap(bytes32(uint256(0xfffffffb) << 224));

        // The premise: these are not what `packLossless` would give, and they
        // are numerically zero.
        assertTrue(Float.unwrap(f(0, 5)) == Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "f(0,5) is not canonical zero");
        assertTrue(
            Float.unwrap(zeroExponentFive) != Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "wrapped zero is canonical"
        );
        assertTrue(zeroExponentFive.isZero(), "exponent 5 zero is not zero");
        assertTrue(zeroExponentMinusFive.isZero(), "exponent -5 zero is not zero");

        vm.expectRevert(
            abi.encodeWithSelector(AgreeNoPositiveTolerance.selector, zeroExponentFive, zeroExponentMinusFive)
        );
        this.agreeExternal(zeroExponentFive, zeroExponentMinusFive, f(100, 0), f(100, 0));

        // Mixed with a canonical zero, either way round.
        vm.expectRevert(abi.encodeWithSelector(AgreeNoPositiveTolerance.selector, zeroExponentFive, f(0, 0)));
        this.agreeExternal(zeroExponentFive, f(0, 0), f(100, 0), f(100, 0));

        vm.expectRevert(abi.encodeWithSelector(AgreeNoPositiveTolerance.selector, f(0, 0), zeroExponentMinusFive));
        this.agreeExternal(f(0, 0), zeroExponentMinusFive, f(100, 0), f(100, 0));
    }

    /// A non-canonical zero is not itself the problem: paired with a positive
    /// term it is accepted, exactly as a canonical zero is. Without this the
    /// test above would also pass for a guard that rejected any non-canonical
    /// tolerance.
    function testAgreeAcceptsNonCanonicalZeroWithPositive() external pure {
        Float zeroExponentFive = Float.wrap(bytes32(uint256(5) << 224));
        assertTrue(LibDecimalFloat.agree(zeroExponentFive, f(1, -2), f(99, 0), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(1, 0), zeroExponentFive, f(100, 0), f(101, 0)));
    }

    /// Either tolerance ALONE may be zero. This is the boundary between the two
    /// guards: one positive term is enough, and it is what makes the rejection
    /// above about having no tolerance rather than about zero appearing at all.
    function testAgreeAcceptsOneZeroTolerance() external pure {
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(100, 0), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(100, 0), f(100, 0)));
    }

    /// THE GUARD, STATED AS A LAW over arbitrary packed tolerances: `agree`
    /// reverts exactly when a tolerance is negative, or when neither is
    /// positive, and returns otherwise.
    ///
    /// The expectation is derived from the tolerances' own signs via `lt`/`gt`
    /// against zero, not from calling `agree`, so this pins the guard's domain
    /// rather than restating its implementation. Values are held fixed and
    /// valid, so the only variable is the tolerance pair.
    /// forge-config: default.fuzz.runs = 5000
    function testAgreeGuardHoldsForArbitraryTolerances(bytes32 absoluteRaw, bytes32 proportionalRaw) external {
        Float absolute = Float.wrap(absoluteRaw);
        Float proportional = Float.wrap(proportionalRaw);
        (int256 signedCoefficientAbsolute,) = absolute.unpack();
        (int256 signedCoefficientProportional,) = proportional.unpack();

        bool anyNegative = signedCoefficientAbsolute < 0 || signedCoefficientProportional < 0;
        bool nonePositive = signedCoefficientAbsolute <= 0 && signedCoefficientProportional <= 0;

        if (anyNegative) {
            vm.expectRevert(abi.encodeWithSelector(AgreeToleranceNegative.selector, absolute, proportional));
            this.agreeExternal(absolute, proportional, f(100, 0), f(100, 0));
        } else if (nonePositive) {
            vm.expectRevert(abi.encodeWithSelector(AgreeNoPositiveTolerance.selector, absolute, proportional));
            this.agreeExternal(absolute, proportional, f(100, 0), f(100, 0));
        } else {
            // A zero spread, so a valid tolerance of any size accepts it.
            assertTrue(this.agreeExternal(absolute, proportional, f(100, 0), f(100, 0)));
        }
    }

    /// The guard runs BEFORE the arithmetic, so a bad tolerance is rejected even
    /// where the spread is the widest representable. A guard placed after the
    /// spread and limit were computed would still reject these, so this is about
    /// ordering being irrelevant to the outcome rather than about the ordering
    /// itself.
    function testAgreeRejectsBadToleranceAtTheRangeExtremes() external {
        vm.expectRevert(abi.encodeWithSelector(AgreeToleranceNegative.selector, f(-1, 0), f(1, -2)));
        this.agreeExternal(f(-1, 0), f(1, -2), minNegative(), maxPositive());

        vm.expectRevert(abi.encodeWithSelector(AgreeNoPositiveTolerance.selector, f(0, 0), f(0, 0)));
        this.agreeExternal(f(0, 0), f(0, 0), minNegative(), maxPositive());
    }

    /// The exact counterexample `testSubPacked` fails on, driven through
    /// `agree`. Pinned as a case in its own right so a future change to the
    /// packing path cannot quietly make `agree` revert.
    function testAgreeSurvivesTheSubUnderflowCounterexample() external pure {
        Float a = Float.wrap(0x8000000000000000000000000000000000000000000000000000000000000009);
        Float b = Float.wrap(0x8000000000000000000000000000000000000000000000000000000000000003);
        bool forward = LibDecimalFloat.agree(f(0, 0), f(1, -2), a, b);
        bool backward = LibDecimalFloat.agree(f(0, 0), f(1, -2), b, a);
        // In units of 1e-2147483648 the spreads are -6 and 6, the limit 0.09.
        assertTrue(forward, "forward");
        assertFalse(backward, "backward");
    }
}
