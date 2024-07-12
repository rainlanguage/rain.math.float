// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

library LibDecimalFloatSlow {
    function multiplySlow(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        unchecked {
            int256 signedCoefficient = signedCoefficientA * signedCoefficientB;
            int256 exponent = exponentA + exponentB;

            // If the expected signed coefficient is 0 then everything is just
            // normalized 0.
            if (signedCoefficient == 0) {
                return (0, 0);
            }
            // If nothing overflowed then our expected outcome is correct.
            else if (signedCoefficient / signedCoefficientA == signedCoefficientB && exponent - exponentA == exponentB)
            {
                return (signedCoefficient, exponent);
            }
            // If something overflowed then we have to normalize and try again.
            else {
                (signedCoefficientA, exponentA) = LibDecimalFloatImplementation.normalize(signedCoefficientA, exponentA);
                (signedCoefficientB, exponentB) = LibDecimalFloatImplementation.normalize(signedCoefficientB, exponentB);

                signedCoefficient = signedCoefficientA * signedCoefficientB;
                exponent = exponentA + exponentB;

                return (signedCoefficient, exponent);
            }
        }
    }
}
