// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    LibDecimalFloatImplementation,
    POW_FIXED_ONE,
    POW_FIXED_LN10,
    POW_FIXED_ONE_ODD_INVERSE,
    LOG10_RATIO_Z_MAX
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Exp10FixedOutOfRange, Log10RatioOutOfRange, Log10RatioRelativeSumTooSmall} from "src/error/ErrDecimalFloat.sol";

/// `mulDivFixedUnguarded`, `log10Ratio` and `exp10Fixed` verbatim from
/// `src/lib/implementation/LibDecimalFloatImplementation.sol` at 9d843e7,
/// before their multiplies were written out in place. The helpers they call
/// are called on the live library. Equivalence tests only.
library LibDecimalFloatImplementationSeriesMain {
    function mulDivFixedUnguarded(uint256 x, uint256 y) private pure returns (uint256 result) {
        uint256 inverse = POW_FIXED_ONE_ODD_INVERSE;
        assembly ("memory-safe") {
            let mm := mulmod(x, y, not(0))
            let prod0 := mul(x, y)
            // slither-disable-next-line too-many-digits
            let remainder := mulmod(x, y, 100000000000000000000000000000000000000000000000000)
            let prod1 := sub(sub(sub(mm, prod0), lt(mm, prod0)), gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
            result := mul(or(shr(50, prod0), shl(206, prod1)), inverse)
        }
    }

    function log10Ratio(uint256 a, uint256 b, bool relative) internal pure returns (int256, int256) {
        bool below = a < b;
        uint256 difference = below ? b - a : a - b;
        uint256 sum;
        unchecked {
            sum = a + b;
        }
        uint256 z;
        int256 exponent = -50;
        if (relative) {
            // sum is below a only by wrapping past 2^256.
            if (sum < a) {
                revert Log10RatioOutOfRange(a, b);
            }
            if (sum < POW_FIXED_ONE) {
                revert Log10RatioRelativeSumTooSmall(a, b);
            }
            z = LibDecimalFloatImplementation.mulDiv(difference, POW_FIXED_ONE, sum);
            if (z > LOG10_RATIO_Z_MAX) {
                revert Log10RatioOutOfRange(a, b);
            }
            // Scale the difference by the largest power of ten that keeps it
            // within int256.max, as maximizeFull does.
            unchecked {
                if (difference != 0) {
                    if (difference <= uint256(type(int256).max) / 1e64) {
                        difference *= 1e64;
                        exponent -= 64;
                    }
                    if (difference <= uint256(type(int256).max) / 1e32) {
                        difference *= 1e32;
                        exponent -= 32;
                    }
                    if (difference <= uint256(type(int256).max) / 1e16) {
                        difference *= 1e16;
                        exponent -= 16;
                    }
                    if (difference <= uint256(type(int256).max) / 1e8) {
                        difference *= 1e8;
                        exponent -= 8;
                    }
                    if (difference <= uint256(type(int256).max) / 1e4) {
                        difference *= 1e4;
                        exponent -= 4;
                    }
                    if (difference <= uint256(type(int256).max) / 1e2) {
                        difference *= 1e2;
                        exponent -= 2;
                    }
                    if (difference <= uint256(type(int256).max) / 10) {
                        difference *= 10;
                        exponent -= 1;
                    }
                }
            }
        } else {
            // sum is at most a by wrapping past 2^256 or for b of zero.
            if (sum <= a) {
                revert Log10RatioOutOfRange(a, b);
            }
            z = LibDecimalFloatImplementation.mulDiv(difference, POW_FIXED_ONE, sum);
            if (z > LOG10_RATIO_Z_MAX) {
                revert Log10RatioOutOfRange(a, b);
            }
        }
        uint256 zSquared = mulDivFixedUnguarded(z, z);
        // atanh(z) / z
        uint256 series = POW_FIXED_ONE;
        uint256 term = POW_FIXED_ONE;
        for (uint256 k = 3; term > 0; k += 2) {
            term = mulDivFixedUnguarded(term, zSquared);
            series += term / k;
        }
        // The scaled series is below 0.8686e50, so the quotient is below it
        // when not relative, and below int256.max / 1e50 times it when
        // relative, as a + b is at least 1e50.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(
            LibDecimalFloatImplementation.mulDiv(
                difference, LibDecimalFloatImplementation.mulDiv(series, 2 * POW_FIXED_ONE, POW_FIXED_LN10), sum
            )
        );
        return (below ? -signedCoefficient : signedCoefficient, exponent);
    }

    function exp10Fixed(uint256 x) internal pure returns (uint256 result) {
        if (x >= POW_FIXED_ONE) {
            revert Exp10FixedOutOfRange(x);
        }
        unchecked {
            result = POW_FIXED_ONE;
            if (x >= 5e49) {
                x -= 5e49;
                result = 316227766016837933199889354443271853371955513932521;
            }
            if (x >= 2.5e49) {
                x -= 2.5e49;
                result = mulDivFixedUnguarded(result, 177827941003892280122542119519268484473579052640225);
            }
            if (x >= 1.25e49) {
                x -= 1.25e49;
                result = mulDivFixedUnguarded(result, 133352143216332402567593171529533109241566796476437);
            }
            if (x >= 6.25e48) {
                x -= 6.25e48;
                result = mulDivFixedUnguarded(result, 115478198468945817966648288729550828156694804147961);
            }
            if (x >= 3.125e48) {
                x -= 3.125e48;
                result = mulDivFixedUnguarded(result, 107460782832131749721594153196434359466719822837527);
            }
            if (x >= 1.5625e48) {
                x -= 1.5625e48;
                result = mulDivFixedUnguarded(result, 103663292843769799729165172492534446770887303110100);
            }
            if (x >= 7.8125e47) {
                x -= 7.8125e47;
                result = mulDivFixedUnguarded(result, 101815172171818184147422688857883534761587963866759);
            }
            if (x >= 3.90625e47) {
                x -= 3.90625e47;
                result = mulDivFixedUnguarded(result, 100903504484144743775925442390642133138116897958823);
            }
            if (x >= 1.953125e47) {
                x -= 1.953125e47;
                result = mulDivFixedUnguarded(result, 100450736425446251566479469434131766413696548644885);
            }
            if (x >= 9.765625e46) {
                x -= 9.765625e46;
                result = mulDivFixedUnguarded(result, 100225114829291291546567363886657119245424113020822);
            }
            if (x >= 4.8828125e46) {
                x -= 4.8828125e46;
                result = mulDivFixedUnguarded(result, 100112494139987987588542643436571177327133841887328);
            }
            if (x >= 2.44140625e46) {
                x -= 2.44140625e46;
                result = mulDivFixedUnguarded(result, 100056231260220863661851136780963697869649047983110);
            }
            if (x >= 1.220703125e46) {
                x -= 1.220703125e46;
                result = mulDivFixedUnguarded(result, 100028111678778013239925736576968704561701000407571);
            }
            if (x >= 6.103515625e45) {
                x -= 6.103515625e45;
                result = mulDivFixedUnguarded(result, 100014054851694725816277118785892892480765770706773);
            }
            if (x >= 3.0517578125e45) {
                x -= 3.0517578125e45;
                result = mulDivFixedUnguarded(result, 100007027178941143553881363867653576320883673909194);
            }
            if (x >= 1.52587890625e45) {
                x -= 1.52587890625e45;
                result = mulDivFixedUnguarded(result, 100003513527746185660858233586155663318996214797054);
            }
            uint256 series = 501392883377544009807090987164215453583108663277;
            series = 1959769462647852369682789087147690310674843760584 + mulDivFixedUnguarded(series, x);
            series = 6808936507443706236540404026537606122629959236393 + mulDivFixedUnguarded(series, x);
            series = 20699584869686809669966601589738494188245922773010 + mulDivFixedUnguarded(series, x);
            series = 53938292919558141019969155571017253478007614081814 + mulDivFixedUnguarded(series, x);
            series = 117125514891226696317825761603265234076100689858139 + mulDivFixedUnguarded(series, x);
            series = 203467859229347619683099119171381053024105502647771 + mulDivFixedUnguarded(series, x);
            series = 265094905523919900528083319429700884579872503956640 + mulDivFixedUnguarded(series, x);
            series = POW_FIXED_LN10 + mulDivFixedUnguarded(series, x);
            series = POW_FIXED_ONE + mulDivFixedUnguarded(series, x);
            result = mulDivFixedUnguarded(result, series);
        }
    }
}
