// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    LibDecimalFloatImplementation,
    POW_FIXED_ONE,
    POW_FIXED_LN10
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

/// `log10Ratio` and `exp10Fixed` verbatim from
/// `src/lib/implementation/LibDecimalFloatImplementation.sol` at
/// 80790d1e, before their multiplies were written out in place. The helpers
/// they call are called on the live library. Equivalence tests only.
library LibDecimalFloatImplementationSeriesMain {
    function log10Ratio(uint256 a, uint256 b, bool relative) internal pure returns (int256, int256) {
        bool below = a < b;
        uint256 difference = below ? b - a : a - b;
        uint256 sum = a + b;
        uint256 z = LibDecimalFloatImplementation.mulDiv(difference, POW_FIXED_ONE, sum);
        uint256 zSquared = LibDecimalFloatImplementation.mulDivFixed(z, z);
        // atanh(z) / z
        uint256 series = POW_FIXED_ONE;
        uint256 term = POW_FIXED_ONE;
        for (uint256 k = 3; term > 0; k += 2) {
            term = LibDecimalFloatImplementation.mulDivFixed(term, zSquared);
            series += term / k;
        }
        int256 exponent = -50;
        if (relative) {
            // difference is below 1e76 so it fits and maximizes in place.
            // forge-lint: disable-start(unsafe-typecast)
            (int256 differenceCoefficient, int256 differenceExponent) =
                LibDecimalFloatImplementation.maximizeFull(int256(difference), 0);
            // forge-lint: disable-end(unsafe-typecast)
            // forge-lint: disable-next-line(unsafe-typecast)
            difference = uint256(differenceCoefficient);
            exponent += differenceExponent;
        }
        // The quotient is below 1e53 and so fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(
            LibDecimalFloatImplementation.mulDiv(
                difference, LibDecimalFloatImplementation.mulDiv(series, 2 * POW_FIXED_ONE, POW_FIXED_LN10), sum
            )
        );
        return (below ? -signedCoefficient : signedCoefficient, exponent);
    }

    function exp10Fixed(uint256 x) internal pure returns (uint256 result) {
        unchecked {
            result = POW_FIXED_ONE;
            if (x >= 5e49) {
                x -= 5e49;
                result = 316227766016837933199889354443271853371955513932521;
            }
            if (x >= 2.5e49) {
                x -= 2.5e49;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 177827941003892280122542119519268484473579052640225
                );
            }
            if (x >= 1.25e49) {
                x -= 1.25e49;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 133352143216332402567593171529533109241566796476437
                );
            }
            if (x >= 6.25e48) {
                x -= 6.25e48;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 115478198468945817966648288729550828156694804147961
                );
            }
            if (x >= 3.125e48) {
                x -= 3.125e48;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 107460782832131749721594153196434359466719822837527
                );
            }
            if (x >= 1.5625e48) {
                x -= 1.5625e48;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 103663292843769799729165172492534446770887303110100
                );
            }
            if (x >= 7.8125e47) {
                x -= 7.8125e47;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 101815172171818184147422688857883534761587963866759
                );
            }
            if (x >= 3.90625e47) {
                x -= 3.90625e47;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 100903504484144743775925442390642133138116897958823
                );
            }
            if (x >= 1.953125e47) {
                x -= 1.953125e47;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 100450736425446251566479469434131766413696548644885
                );
            }
            if (x >= 9.765625e46) {
                x -= 9.765625e46;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 100225114829291291546567363886657119245424113020822
                );
            }
            if (x >= 4.8828125e46) {
                x -= 4.8828125e46;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 100112494139987987588542643436571177327133841887328
                );
            }
            if (x >= 2.44140625e46) {
                x -= 2.44140625e46;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 100056231260220863661851136780963697869649047983110
                );
            }
            if (x >= 1.220703125e46) {
                x -= 1.220703125e46;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 100028111678778013239925736576968704561701000407571
                );
            }
            if (x >= 6.103515625e45) {
                x -= 6.103515625e45;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 100014054851694725816277118785892892480765770706773
                );
            }
            if (x >= 3.0517578125e45) {
                x -= 3.0517578125e45;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 100007027178941143553881363867653576320883673909194
                );
            }
            if (x >= 1.52587890625e45) {
                x -= 1.52587890625e45;
                result = LibDecimalFloatImplementation.mulDivFixed(
                    result, 100003513527746185660858233586155663318996214797054
                );
            }
            uint256 series = 501392883377544009807090987164215453583108663277;
            series = 1959769462647852369682789087147690310674843760584
                + LibDecimalFloatImplementation.mulDivFixed(series, x);
            series = 6808936507443706236540404026537606122629959236393
                + LibDecimalFloatImplementation.mulDivFixed(series, x);
            series = 20699584869686809669966601589738494188245922773010
                + LibDecimalFloatImplementation.mulDivFixed(series, x);
            series = 53938292919558141019969155571017253478007614081814
                + LibDecimalFloatImplementation.mulDivFixed(series, x);
            series = 117125514891226696317825761603265234076100689858139
                + LibDecimalFloatImplementation.mulDivFixed(series, x);
            series = 203467859229347619683099119171381053024105502647771
                + LibDecimalFloatImplementation.mulDivFixed(series, x);
            series = 265094905523919900528083319429700884579872503956640
                + LibDecimalFloatImplementation.mulDivFixed(series, x);
            series = POW_FIXED_LN10 + LibDecimalFloatImplementation.mulDivFixed(series, x);
            series = POW_FIXED_ONE + LibDecimalFloatImplementation.mulDivFixed(series, x);
            result = LibDecimalFloatImplementation.mulDivFixed(result, series);
        }
    }
}
