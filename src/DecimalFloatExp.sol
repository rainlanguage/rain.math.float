// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {DecimalFloat, SIGN_MASK, LibDecimalFloat, DivisionByZero} from "./DecimalFloat.sol";

/// Experimental versions of algorithms for DecimalFloat.
library LibDecimalFloatExp {
    using LibDecimalFloat for DecimalFloat;

    /// Long division logic for DecimalFloat.
    function divideLong(DecimalFloat a, DecimalFloat b) internal pure returns (DecimalFloat) {
        (int128 signedCoefficientA, int128 exponentA) = LibDecimalFloat.toParts(a);
        if (signedCoefficientA == 0) {
            return DecimalFloat.wrap(0);
        }

        (int128 signedCoefficientB, int128 exponentB) = LibDecimalFloat.toParts(b);
        if (signedCoefficientB == 0) {
            revert DivisionByZero();
        }

        uint256 unsignedCoefficientA = uint256(uint128(signedCoefficientA) & ~SIGN_MASK);
        uint256 unsignedCoefficientB = uint256(uint128(signedCoefficientB) & ~SIGN_MASK);

        int128 adjust = 0;
        int256 resultCoefficient = 0;

        unchecked {
            while (unsignedCoefficientA < unsignedCoefficientB) {
                unsignedCoefficientA *= 10;
                adjust += 1;
            }

            uint256 tensB = unsignedCoefficientB * 10;
            while (unsignedCoefficientA >= tensB) {
                unsignedCoefficientB = tensB;
                tensB *= 10;
                adjust -= 1;
            }

            uint256 tmpCoefficientA = unsignedCoefficientA;

            while (true) {
                while (tmpCoefficientA >= unsignedCoefficientB) {
                    tmpCoefficientA -= unsignedCoefficientB;
                    resultCoefficient += 1;
                }

                // Discard this round as it caused precision loss in the result.
                if (int128(resultCoefficient) != int256(resultCoefficient)) {
                    break;
                }

                unsignedCoefficientA = tmpCoefficientA;

                if (tmpCoefficientA == 0 && adjust >= 0) {
                    break;
                }

                tmpCoefficientA *= 10;
                resultCoefficient *= 10;
                adjust += 1;
            }
        }

        int256 exponent = exponentA - exponentB - adjust;

        (int256 normalizedCoefficient, int256 normalizedExponent) =
            LibDecimalFloat.normalize(resultCoefficient, exponent);
        DecimalFloat value = LibDecimalFloat.fromParts(normalizedCoefficient, normalizedExponent);

        uint256 signBit = DecimalFloat.unwrap(a) & SIGN_MASK ^ DecimalFloat.unwrap(b) & SIGN_MASK;

        return DecimalFloat.wrap(DecimalFloat.unwrap(value) & ~SIGN_MASK | signBit);
    }
}
