// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibDecimalFloatImplementation,
    POW_FIXED_ONE,
    EXP10_HORNER_2,
    EXP10_HORNER_3,
    EXP10_HORNER_4,
    EXP10_HORNER_5,
    EXP10_HORNER_6,
    EXP10_HORNER_7,
    EXP10_HORNER_8,
    EXP10_HORNER_9
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {Exp10FixedOutOfRange} from "src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatImplementationExp10FixedTest is Test {
    /// The true power is in [truncated, truncated + 1), and exp10Fixed is
    /// never above it, so at most truncated. It is under 88.08 units below,
    /// so at least truncated - 88, and under 1.408e-49 of it below.
    function assertProvenBound(uint256 actual, uint256 truncated) internal pure {
        uint256 below = Math.mulDiv(truncated + 1, 1408, 1e52, Math.Rounding.Ceil);
        assertGe(actual + below, truncated, "below relative");
        assertGe(actual + 88, truncated, "below");
        assertLe(actual, truncated, "above");
    }

    /// References are 10^x truncated to 50 places from `bc -l` at scale 120.
    function testExp10Fixed() external pure {
        assertEq(LibDecimalFloatImplementation.exp10Fixed(0), POW_FIXED_ONE);
        // Every binary digit and the largest remainder.
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(POW_FIXED_ONE - 1),
            999999999999999999999999999999999999999999999999976
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(5e49), 316227766016837933199889354443271853371955513932521
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(7.5e49), 562341325190349080394951039776481231468251043098691
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(12345678901234567890123456789012345678901234567890),
            132879133982907133325799753963302210145286380241964
        );
        // The remainder alone, at its largest and where the result is exactly
        // the truncated power.
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(1.52587890625e45 - 1),
            100003513527746185660858233586155663318996214797052
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(286622127933679969227965878450164870526176577),
            100000659974016921256786164026392746149691811088958
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(1e47), 100230523807789967191540488932811055405366845354216
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(1), 100000000000000000000000000000000000000000000000002
        );
    }

    /// At x = 2^-i the step for i is taken alone, so the result is its
    /// constant, 10^(2^-i) floored to 50 places from `bc -l` at scale 130.
    function testExp10FixedSteps() external pure {
        uint256[16] memory powers = [
            uint256(316227766016837933199889354443271853371955513932521),
            177827941003892280122542119519268484473579052640225,
            133352143216332402567593171529533109241566796476437,
            115478198468945817966648288729550828156694804147961,
            107460782832131749721594153196434359466719822837527,
            103663292843769799729165172492534446770887303110100,
            101815172171818184147422688857883534761587963866759,
            100903504484144743775925442390642133138116897958823,
            100450736425446251566479469434131766413696548644885,
            100225114829291291546567363886657119245424113020822,
            100112494139987987588542643436571177327133841887328,
            100056231260220863661851136780963697869649047983110,
            100028111678778013239925736576968704561701000407571,
            100014054851694725816277118785892892480765770706773,
            100007027178941143553881363867653576320883673909194,
            100003513527746185660858233586155663318996214797054
        ];
        for (uint256 i = 0; i < powers.length; i++) {
            assertEq(LibDecimalFloatImplementation.exp10Fixed(POW_FIXED_ONE >> (i + 1)), powers[i]);
        }
    }

    /// At x = 1 - 2^-16 every step is taken. The reference is 10^x truncated
    /// to 50 places from `bc -l` at scale 200.
    function testExp10FixedAllSteps() external pure {
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(POW_FIXED_ONE - 1.52587890625e45),
            999964865956982493168325998248471709590758801441386
        );
    }

    /// x below 2^-16 whose r^1 Horner multiply, ln 10 term included, has a
    /// low word below its remainder mod 1e50. References are 10^x truncated to
    /// 50 places from `bc -l` at scale 200.
    function testExp10FixedLn10TermMultiplyBorrow() external pure {
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(1000000000000000000045587860971055972294985359),
            100002302611602688067106602906991101183429167140617
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(1000000000000000001051322010896134384349740718),
            100002302611602688067108918748775847507337638560317
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(1000000000000000003565657385708830414486527219),
            100002302611602688067114708353237713317108817109568
        );
    }

    /// 10^x 1e50 is 0.99999908 above its truncation here, so a result one unit
    /// higher than the truncation is above 10^x. Reference from `bc -l` at
    /// scale 200.
    function testExp10FixedJustBelowNextUnit() external pure {
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(300000000000000000000000000000000000987345372),
            100000690777913757857062170874388096259674712694619
        );
    }

    function exp10FixedExternal(uint256 x) external pure returns (uint256) {
        return LibDecimalFloatImplementation.exp10Fixed(x);
    }

    /// #422: exp10Fixed(2e50) was 9.9985e51 for 1e52. One is the first x
    /// past [0, 1), whose last value, 1 - 1e-50, `testExp10Fixed` checks.
    function testExp10FixedOutOfRange() external {
        uint256[3] memory xs = [uint256(POW_FIXED_ONE), 2e50, type(uint256).max];
        for (uint256 i = 0; i < xs.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(Exp10FixedOutOfRange.selector, xs[i]));
            this.exp10FixedExternal(xs[i]);
        }
    }

    function testExp10FixedOutOfRangeFuzz(uint256 x) external {
        x = bound(x, POW_FIXED_ONE, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Exp10FixedOutOfRange.selector, x));
        this.exp10FixedExternal(x);
    }

    /// The value the multiply after adding (ln 10)^step / step! takes times r,
    /// as the documented Horner rule floors it.
    function hornerFactor(uint256 r, uint256 step) internal pure returns (uint256 factor) {
        uint256[8] memory coefficients = [
            EXP10_HORNER_2,
            EXP10_HORNER_3,
            EXP10_HORNER_4,
            EXP10_HORNER_5,
            EXP10_HORNER_6,
            EXP10_HORNER_7,
            EXP10_HORNER_8,
            EXP10_HORNER_9
        ];
        factor = EXP10_HORNER_9;
        for (uint256 k = 8; k >= step; k--) {
            factor = coefficients[k - 2] + Math.mulDiv(factor, r, POW_FIXED_ONE);
        }
    }

    /// The low word of a * b is below a b mod 1e50.
    function lowWordBelowRemainder(uint256 a, uint256 b) internal pure returns (bool) {
        uint256 low;
        unchecked {
            low = a * b;
        }
        return low < mulmod(a, b, POW_FIXED_ONE);
    }

    /// x below 2^-16 whose multiply after adding (ln 10)^step / step!, for
    /// step 8 down to 2, has a low word below its remainder mod 1e50, so
    /// subtracting the remainder borrows from the high word. References are
    /// 10^x truncated to 50 places from `bc -l` at scale 200.
    function testExp10FixedHornerMultiplyRemainderBorrows() external pure {
        uint256[3][13] memory cases = [
            [
                uint256(8),
                762940942320212121346300472980936507770876579,
                100001756751871326318313412630848020413772097696325
            ],
            [
                uint256(8),
                508627625814133283966100736957054540933761976,
                100001171165247171211367533024862294197188937236630
            ],
            [
                uint256(7),
                762941128478606530888775983110234293147290216,
                100001756752299979392456063802066758513917291318075
            ],
            [
                uint256(7),
                508627791287750329703429612494245112952342259,
                100001171165628192757601251437659585372979822334652
            ],
            [
                uint256(6),
                762941367815036310745078012683917445721738015,
                100001756752851081569209183982705444674272458760978
            ],
            [
                uint256(6),
                508628004031633991451072542368952413579770704,
                100001171166118059389830080800768966236323180024699
            ],
            [
                uint256(5),
                762941686930275944371049105618478268881614943,
                100001756753585884471383657713278870259907461331726
            ],
            [
                uint256(5),
                508628287690237783991637131006414028007567499,
                100001171166771215111873348971325335583079328207055
            ],
            [
                uint256(4),
                762942133691555367663066349924066535396032431,
                100001756754614608405343089783236578275876030213830
            ],
            [
                uint256(4),
                305177496816814754944306844366986248933302412,
                100000702699623809875931178672353195502267833005752
            ],
            [
                uint256(3),
                117376252165447036455505654530596961595237084,
                100000270269173734141712308142315110290330419046444
            ],
            [
                uint256(2),
                508630273301571623514985782118028471512034183,
                100001171171343307715958989543746160062945412514778
            ],
            [
                uint256(2),
                138717741109131768047353978597871383874358790,
                100000319409912924070264117940886962149664776203160
            ]
        ];
        for (uint256 i = 0; i < cases.length; i++) {
            uint256 x = cases[i][1];
            assertTrue(lowWordBelowRemainder(hornerFactor(x, cases[i][0]), x), "borrows");
            assertProvenBound(LibDecimalFloatImplementation.exp10Fixed(x), cases[i][2]);
        }
    }
}
