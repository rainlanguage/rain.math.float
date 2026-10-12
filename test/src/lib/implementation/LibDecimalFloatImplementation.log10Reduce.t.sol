// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Log10ReduceOutOfRange} from "src/error/ErrDecimalFloat.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";

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

    /// 2^256 / 10^(2^-i) rounded to nearest, for i in [11, 16], from `bc -l`
    /// at scale 200.
    function reciprocalsLate() internal pure returns (uint256[6] memory) {
        return [
            uint256(115661976291793632079080739461244514212109858454009171777232224145244584379146),
            115727014478658864191206019837644585076293120248274136969870782148370783742109,
            115759547285228489644640649073775386641395351335601881572150779206589155570705,
            115775817117921914513665754670628277870063336875992169054789846993299520681056,
            115783952891761361996258436523111610648709418794355347035638479532448488583968,
            115788020993071844566540918178001145605824617021039977012160767671253988218160
        ];
    }

    /// For i in [11, 16], x where step i is the only step taken and the
    /// product x K_i lands within x of a multiple of 2^256, from `bc -l` at
    /// scale 200: the low word of x K_i is below x (`lows`), or at least
    /// 2^256 - x (`highs`). Either way floor(x K_i / 2^256) is the only value
    /// within x / 2^256 of the product, so the step must take the exact high
    /// word of the full product with the rounded-to-nearest reciprocal.
    function lateStepInputs() internal pure returns (uint256[6] memory lows, uint256[6] memory highs) {
        lows = [
            uint256(1001124941399879875885426434365711773271338418873287617190761945242904872686),
            1000562312602208636618511367809636978696490479831100413718397439177031577073,
            1000281116787780132399257365769687045617010004075711462195816279315578113459,
            1000140548516947258162771187858928924807657707067732580839449098218983452469,
            1000070271789411435538813638676535763208836739091941327682886747964405338318,
            1000035135277461856608582335861556633189962147970549360011398536055919608561
        ];
        highs = [
            uint256(1001124941399879875885426434365711773271338418873287617190761945242904872693),
            1000562312602208636618511367809636978696490479831100413718397439177031577088,
            1000281116787780132399257365769687045617010004075711462195816279315578113490,
            1000140548516947258162771187858928924807657707067732580839449098218983452531,
            1000070271789411435538813638676535763208836739091941327682886747964405338441,
            1000035135277461856608582335861556633189962147970549360011398536055919608807
        ];
    }

    function checkLateStep(uint256 i, uint256 x, uint256 k) internal pure {
        (uint256 reduced, uint256 seed) = LibDecimalFloatImplementation.log10Reduce(x);
        assertEq(seed, POW_FIXED_ONE >> i, "seed");
        (uint256 high,) = LibExactFloat.words(LibExactFloat.mul(x, k));
        assertEq(reduced, high, "reduced");
    }

    /// Steps 11 to 16 each divide by their reciprocal as the exact high word
    /// of x K_i, at the inputs where any other reciprocal or a dropped borrow
    /// moves that word.
    function testLog10ReduceLateStepsExactProduct() external pure {
        uint256[6] memory k = reciprocalsLate();
        (uint256[6] memory lows, uint256[6] memory highs) = lateStepInputs();
        for (uint256 j = 0; j < 6; j++) {
            checkLateStep(j + 11, lows[j], k[j]);
            checkLateStep(j + 11, highs[j], k[j]);
        }
    }

    function log10ReduceExternal(uint256 x) external pure returns (uint256, uint256) {
        return LibDecimalFloatImplementation.log10Reduce(x);
    }

    /// The top of the range, 1e76 - 1, is past every threshold after the
    /// steps before it, so it takes every step and lands in range.
    function testLog10ReduceTop() external pure {
        (uint256 reduced, uint256 seed) = LibDecimalFloatImplementation.log10Reduce(1e76 - 1);
        // 1e50 is divisible by 2^16, so every step's 2^-i is exact.
        assertEq(seed, POW_FIXED_ONE - (POW_FIXED_ONE >> 16), "every step");
        assertReducedInRange(reduced);
    }

    /// #422: log10Reduce(5e76) broke its postcondition. Either side of
    /// [1e75, 1e76) reverts with the input.
    function testLog10ReduceOutOfRange() external {
        uint256[5] memory xs = [uint256(0), 1e75 - 1, 1e76, 5e76, type(uint256).max];
        for (uint256 i = 0; i < xs.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(Log10ReduceOutOfRange.selector, xs[i]));
            this.log10ReduceExternal(xs[i]);
        }
    }

    function testLog10ReduceOutOfRangeFuzz(uint256 x, bool high) external {
        x = high ? bound(x, 1e76, type(uint256).max) : bound(x, 0, 1e75 - 1);
        vm.expectRevert(abi.encodeWithSelector(Log10ReduceOutOfRange.selector, x));
        this.log10ReduceExternal(x);
    }
}
