// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibExp10Bracket} from "src/lib/implementation/LibExp10Bracket.sol";

/// The references are `bc -l` at scale 220, truncated: 10^g 10^76 for a
/// positive g, 10^-g 10^77 for a negative one.
contract LibExp10BracketTest is Test {
    uint256 constant SQRT10 = 31622776601683793319988935444327185337195551393252168268575048527925944386392;
    uint256 constant G50 = 12345678901234567890123456789012345678901234567890;
    uint256 constant EXP10_G50 = 13287913398290713332579975396330221014528638024196431737440733111395177555490;
    uint256 constant EXP10_MINUS_G50 = 75256360425154087286064932947247412843988180101377755093196977821296202913582;
    uint256 constant G77 = 98765432109876543210987654321098765432109876543210987654321098765432109876543;
    uint256 constant EXP10_G77 = 97197326873542009082148600416483903755259669267654711633474206039261579097119;

    function limbs3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory value) {
        value = new uint256[](3);
        value[0] = a;
        value[1] = b;
        value[2] = c;
    }

    function limbs5(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e)
        internal
        pure
        returns (uint256[] memory value)
    {
        value = new uint256[](5);
        value[0] = a;
        value[1] = b;
        value[2] = c;
        value[3] = d;
        value[4] = e;
    }

    function assertBrackets(uint256[] memory low, uint256[] memory high, uint256[] memory truth) internal pure {
        assertLe(LibExp10Bracket.compare(low, truth), 0, "low");
        // truth is floored, so high is at least truth.
        assertGe(LibExp10Bracket.compare(high, truth), 0, "high");
    }

    /// A 77 digit r beside 10^s is within a unit of 1e-76 of it, under the
    /// width of the two limb bounds, so it takes four limbs. Both sides of the
    /// truncation are checked.
    function checkForcesFourLimbs(uint256 g, int256 gExponent, bool negative, uint256 truncated, int256 rExponent)
        internal
        pure
    {
        assertEq(LibExp10Bracket.sideAt(g, gExponent, negative, truncated, rExponent, 2), 0, "two limbs below");
        assertEq(LibExp10Bracket.sideAt(g, gExponent, negative, truncated + 1, rExponent, 2), 0, "two limbs above");
        assertEq(LibExp10Bracket.sideAt(g, gExponent, negative, truncated, rExponent, 4), 1, "four limbs below");
        assertEq(LibExp10Bracket.sideAt(g, gExponent, negative, truncated + 1, rExponent, 4), -1, "four limbs above");
        assertFalse(LibExp10Bracket.below(g, gExponent, negative, truncated, rExponent), "below truncated");
        assertTrue(LibExp10Bracket.below(g, gExponent, negative, truncated + 1, rExponent), "below truncated plus one");
    }

    function testForcesFourLimbsSqrt10() external pure {
        checkForcesFourLimbs(5, -1, false, SQRT10, -76);
    }

    function testForcesFourLimbsInverseSqrt10() external pure {
        checkForcesFourLimbs(5, -1, true, SQRT10, -77);
    }

    function testForcesFourLimbsFiftyDigits() external pure {
        checkForcesFourLimbs(G50, -50, false, EXP10_G50, -76);
    }

    function testForcesFourLimbsFiftyDigitsNegative() external pure {
        checkForcesFourLimbs(G50, -50, true, EXP10_MINUS_G50, -77);
    }

    function testForcesFourLimbsSeventySevenDigits() external pure {
        checkForcesFourLimbs(G77, -77, false, EXP10_G77, -76);
    }

    /// An r far from 10^s is decided at the first precision.
    function testDecidedAtTwoLimbs() external pure {
        assertEq(LibExp10Bracket.sideAt(5, -1, false, 316, -2, 2), 1);
        assertEq(LibExp10Bracket.sideAt(5, -1, false, 317, -2, 2), -1);
        assertEq(LibExp10Bracket.sideAt(5, -1, true, 316, -3, 2), 1);
        assertEq(LibExp10Bracket.sideAt(5, -1, true, 317, -3, 2), -1);
    }

    function testExp10BracketsSqrt10FourLimbs() external pure {
        (uint256[] memory low, uint256[] memory high) = LibExp10Bracket.exp10(5, -1, 4);
        assertBrackets(
            low,
            high,
            limbs5(
                5514854885603045388001469051959670015,
                38221344248108379300295187347284152840,
                95551393252168268575048527925944386392,
                16227766016837933199889354443271853371,
                3
            )
        );
    }

    function testExp10BracketsFiftyDigitsTwoLimbs() external pure {
        (uint256[] memory low, uint256[] memory high) = LibExp10Bracket.exp10(G50, -50, 2);
        assertBrackets(
            low, high, limbs3(28638024196431737440733111395177555490, 32879133982907133325799753963302210145, 1)
        );
    }

    function testLn10Brackets() external pure {
        (uint256[] memory low, uint256[] memory high) = LibExp10Bracket.ln10(2);
        assertBrackets(
            low, high, limbs3(11014886287729760333279009675726096773, 30258509299404568401799145468436420760, 2)
        );
        (low, high) = LibExp10Bracket.ln10(4);
        assertBrackets(
            low,
            high,
            limbs5(
                24863340952546508280675666628736909878,
                52480235997205089598298341967784042286,
                11014886287729760333279009675726096773,
                30258509299404568401799145468436420760,
                2
            )
        );
    }

    function testFromDecimal() external pure {
        (uint256[] memory value, bool inexact) = LibExp10Bracket.fromDecimal(SQRT10, -76, 2);
        assertFalse(inexact);
        assertEq(
            LibExp10Bracket.compare(
                value, limbs3(95551393252168268575048527925944386392, 16227766016837933199889354443271853371, 3)
            ),
            0
        );
        (value, inexact) = LibExp10Bracket.fromDecimal(SQRT10, -78, 1);
        assertTrue(inexact);
        uint256[] memory expected = new uint256[](2);
        expected[0] = 3162277660168379331998893544432718533;
        assertEq(LibExp10Bracket.compare(value, expected), 0);
    }

    function testMulRounds() external pure {
        uint256[] memory third = new uint256[](2);
        third[0] = 33333333333333333333333333333333333333;
        uint256[] memory half = new uint256[](2);
        half[0] = 5e37;
        uint256[] memory product = LibExp10Bracket.mul(third, half, 1, false);
        assertEq(product[0], 16666666666666666666666666666666666666);
        product = LibExp10Bracket.mul(third, half, 1, true);
        assertEq(product[0], 16666666666666666666666666666666666667);
    }

    function testDivSmallRounds() external pure {
        uint256[] memory one = new uint256[](2);
        one[1] = 1;
        assertEq(LibExp10Bracket.divSmall(one, 3, false)[0], 33333333333333333333333333333333333333);
        assertEq(LibExp10Bracket.divSmall(one, 3, true)[0], 33333333333333333333333333333333333334);
        assertEq(LibExp10Bracket.divSmall(one, 2, true)[0], 5e37);
    }
}
