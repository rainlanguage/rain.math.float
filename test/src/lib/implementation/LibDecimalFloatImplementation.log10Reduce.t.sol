// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationLog10ReduceTest is Test {
    /// 1e75 10^(2^-i) rounded up, for i in [1, 16], from `bc -l` at scale 140.
    function thresholds() internal pure returns (uint256[16] memory) {
        return [
            uint256(3162277660168379331998893544432718533719555139325216826857504852792594438640),
            1778279410038922801225421195192684844735790526402255358011830722776301881540,
            1333521432163324025675931715295331092415667964764370993329549987162758943181,
            1154781984689458179666482887295508281566948041479611129977426848717929206981,
            1074607828321317497215941531964343594667198228375277635737525385456277680090,
            1036632928437697997291651724925344467708873031101004651184732490611638515681,
            1018151721718181841474226888578835347615879638667598311831418789512158676639,
            1009035044841447437759254423906421331381168979588236162503174368256031811568,
            1004507364254462515664794694341317664136965486448855489880346341316837480908,
            1002251148292912915465673638866571192454241130208227099208420545124889760121,
            1001124941399879875885426434365711773271338418873287617190761945242904872061,
            1000562312602208636618511367809636978696490479831100413718397439177031575557,
            1000281116787780132399257365769687045617010004075711462195816279315578112995,
            1000140548516947258162771187858928924807657707067732580839449098218983450057,
            1000070271789411435538813638676535763208836739091941327682886747964405335251,
            1000035135277461856608582335861556633189962147970549360011398536055919590052
        ];
    }

    function assertReducedInRange(uint256 reduced) internal pure {
        assertGe(reduced, 1e75 - 1, "reduced below range");
        assertLt(reduced, thresholds()[15], "reduced above range");
    }

    /// At 1e75 10^(2^-i) the step for i is taken alone: the seed is exactly
    /// 2^-i and the rest is left within 10^(2^-16) of 1e75.
    function testLog10ReduceAtEachThreshold() external pure {
        uint256[16] memory t = thresholds();
        for (uint256 i = 0; i < t.length; i++) {
            (uint256 reduced, uint256 seed) = LibDecimalFloatImplementation.log10Reduce(t[i]);
            assertEq(seed, POW_FIXED_ONE >> (i + 1), "seed");
            assertReducedInRange(reduced);
        }
    }

    /// Just below 1e75 10^(2^-i) the step for i is not taken, and the later
    /// steps, summing to under 2^-i, still bring x into range.
    function testLog10ReduceBelowEachThreshold() external pure {
        uint256[16] memory t = thresholds();
        for (uint256 i = 0; i < t.length; i++) {
            (uint256 reduced, uint256 seed) = LibDecimalFloatImplementation.log10Reduce(t[i] - 1);
            assertLt(seed, POW_FIXED_ONE >> (i + 1), "seed");
            assertReducedInRange(reduced);
        }
    }

    /// 1e75 needs no step.
    function testLog10ReduceOne() external pure {
        (uint256 reduced, uint256 seed) = LibDecimalFloatImplementation.log10Reduce(1e75);
        assertEq(seed, 0);
        assertEq(reduced, 1e75);
    }

    /// Every x in [1e75, 1e76) lands in range with a seed below 1.
    function testLog10ReduceInRange(uint256 x) external pure {
        x = bound(x, 1e75, 1e76 - 1);
        (uint256 reduced, uint256 seed) = LibDecimalFloatImplementation.log10Reduce(x);
        assertLt(seed, POW_FIXED_ONE);
        assertReducedInRange(reduced);
    }
}
