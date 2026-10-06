// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

contract LibDecimalFloatImplementationExp10FixedTest is Test {
    /// The true power is in [truncated, truncated + 1), and exp10Fixed is
    /// within [-3.048e-49, 0] relative of it, so at most truncated.
    function assertProvenBound(uint256 actual, uint256 truncated) internal pure {
        uint256 below = Math.mulDiv(truncated + 1, 3048, 1e52, Math.Rounding.Ceil);
        assertGe(actual + below, truncated, "below");
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

    /// At x = 1 - 2^-16 every step is taken and the series is exactly one, so
    /// the result is the floored product of the steps. 10^(1 - 2^-16) from
    /// `bc -l` at scale 120 is 999964865956982493168325998248471709590758801441386.28,
    /// 76.28 units above it. sqrt's `roundRoot` needs this over 23.03.
    function testExp10FixedAllSteps() external pure {
        assertEq(
            LibDecimalFloatImplementation.exp10Fixed(POW_FIXED_ONE - 1.52587890625e45),
            999964865956982493168325998248471709590758801441310
        );
    }
}
