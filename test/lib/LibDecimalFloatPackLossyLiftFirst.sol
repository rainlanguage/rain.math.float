// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";

/// `packLossy` verbatim from `src/lib/LibDecimalFloat.sol` at
/// 4d2d1e8ea388257fb9a5526748f15ea935c82002, which lifts an exponent above
/// int32.max before any shedding. Equivalence tests only.
library LibDecimalFloatPackLossyLiftFirst {
    function packLossy(int256 signedCoefficient, int256 exponent) internal pure returns (Float float, bool lossless) {
        unchecked {
            int256 initialSignedCoefficient = signedCoefficient;
            int256 initialExponent = exponent;

            // Above the ceiling, lower the exponent by multiplying the
            // coefficient by ten per step, which is exact, while int224 has the
            // headroom. A non-zero int224 coefficient has at most 68 digits, so
            // an excess of 68 or more never has it, and a coefficient that does
            // not fit int224 has none at all. Lifting before any shedding means
            // the exponent is at most int32.max from here on, so the unchecked
            // additions below cannot wrap.
            if (exponent > type(int32).max && signedCoefficient != 0) {
                int256 excess = exponent - type(int32).max;
                if (excess > 67) {
                    revert ExponentOverflow(initialSignedCoefficient, initialExponent);
                }
                // excess is in [1, 67] so 10 ** excess fits int256 and the
                // casts cannot truncate.
                // forge-lint: disable-next-line(unsafe-typecast)
                int256 scale = int256(10 ** uint256(excess));
                if (
                    initialSignedCoefficient > type(int224).max / scale
                        || initialSignedCoefficient < type(int224).min / scale
                ) {
                    revert ExponentOverflow(initialSignedCoefficient, initialExponent);
                }
                signedCoefficient = initialSignedCoefficient * scale;
                exponent = type(int32).max;
            }

            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            bool fits = int224(signedCoefficient) == signedCoefficient;

            if (!fits) {
                if (signedCoefficient / 1e72 != 0) {
                    signedCoefficient /= 1e5;
                    exponent += 5;
                }

                // truncation here is intentional if it happens as that is what we
                // are testing for.
                // forge-lint: disable-next-line(unsafe-typecast)
                while (int224(signedCoefficient) != signedCoefficient) {
                    signedCoefficient /= 10;
                    ++exponent;
                }
            } else {
                if (signedCoefficient == 0) {
                    // The literal is the bool this function returns, not a condition operand.
                    //forge-lint: disable-next-line(boolean-cst)
                    return (LibDecimalFloat.FLOAT_ZERO, true);
                }
            }

            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (int32(exponent) != exponent) {
                // Shedding to fit int224 pushed the exponent past the ceiling,
                // so the magnitude exceeds every representable Float.
                if (exponent > 0) {
                    revert ExponentOverflow(initialSignedCoefficient, initialExponent);
                }

                // The exponent is below the int32 floor. Every division of the
                // coefficient by ten raises the exponent by one, so the
                // shortfall is exactly the number of digits to shed. The
                // coefficient fits int224 here, so it has at most 68 decimal
                // digits and a shortfall of 68 or more sheds every one of
                // them: that is zero without computing it. `exponent` is
                // negative here and below int32.min, so the subtraction cannot
                // overflow and the shortfall is positive.
                int256 shortfall = int256(type(int32).min) - exponent;
                if (shortfall > 67) {
                    // The literal is the bool this function returns, not a condition operand.
                    //forge-lint: disable-next-line(boolean-cst)
                    return (LibDecimalFloat.FLOAT_ZERO, false);
                }
                // shortfall is in [1, 67] so 10 ** shortfall fits int256 and the
                // casts cannot truncate.
                // forge-lint: disable-next-line(unsafe-typecast)
                signedCoefficient /= int256(10 ** uint256(shortfall));
                if (signedCoefficient == 0) {
                    // Every digit was shed: the value is smaller in magnitude
                    // than any representable Float, so this is the underflow
                    // zero and it is not a lossless conversion.
                    // The literal is the bool this function returns, not a condition operand.
                    //forge-lint: disable-next-line(boolean-cst)
                    return (LibDecimalFloat.FLOAT_ZERO, false);
                }
                exponent = type(int32).min;
            }

            // Lossless iff every digit shed was a zero, which is iff the
            // original coefficient is an exact multiple of ten to the number of
            // digits shed. Shedding only raises the exponent and lifting only
            // lowers it, and never both, so an exponent at or below the initial
            // one shed nothing. Otherwise the number shed is the rise, which is
            // in [1, 76] for any non-zero result (an int256 has at most 77
            // digits and at least one survived), so the power fits int256.
            if (exponent <= initialExponent) {
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(boolean-cst)
                lossless = true;
            } else {
                // The rise is in [1, 76] so the casts cannot truncate.
                // forge-lint: disable-next-line(unsafe-typecast)
                lossless = initialSignedCoefficient % int256(10 ** uint256(exponent - initialExponent)) == 0;
            }

            // Need a mask to zero out the bits that could be set to 1 if the
            // coefficient is negative.
            uint256 mask = type(uint224).max;
            assembly ("memory-safe") {
                float := or(and(signedCoefficient, mask), shl(0xe0, exponent))
            }
        }
    }
}
