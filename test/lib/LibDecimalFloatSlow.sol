// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";


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

    function invSlow(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        return LibDecimalFloat.divide(1e37, -37, signedCoefficient, exponent);
    }

    function eqSlow(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        // If the exponents are the same we compare the coefficients.
        if (exponentA == exponentB) {
            return signedCoefficientA == signedCoefficientB;
        }

        // Comparisons with zero ignore exponents.
        if (signedCoefficientA == 0 || signedCoefficientB == 0) {
            return signedCoefficientA == signedCoefficientB;
        }

        unchecked {
            int256 tmp = 0;
            while (exponentA > exponentB) {
                tmp = signedCoefficientA * 10;
                if (tmp / 10 != signedCoefficientA) {
                    return false;
                }
                signedCoefficientA = tmp;
                exponentA--;
            }

            while (exponentB > exponentA) {
                tmp = signedCoefficientB * 10;
                if (tmp / 10 != signedCoefficientB) {
                    return false;
                }
                signedCoefficientB = tmp;
                exponentB--;
            }
        }

        return eqSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function gtSlow(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        // If the exponents are the same we compare the coefficients.
        if (exponentA == exponentB) {
            return signedCoefficientA > signedCoefficientB;
        }

        // Comparisons with zero ignore exponents.
        if (signedCoefficientA == 0 || signedCoefficientB == 0) {
            return signedCoefficientA > signedCoefficientB;
        }

        unchecked {
            int256 tmp = 0;
            while (exponentA > exponentB) {
                tmp = signedCoefficientA * 10;
                if (tmp / 10 != signedCoefficientA) {
                    // A overflowed so is huge in magnitude, it's gt everything
                    // if positive and lt everything if it's negative.
                    return signedCoefficientA > 0;
                }
                signedCoefficientA = tmp;
                exponentA--;
            }

            while (exponentB > exponentA) {
                tmp = signedCoefficientB * 10;
                if (tmp / 10 != signedCoefficientB) {
                    // B overflowed so is huge in magnitude, it's gt everything
                    // if positive and lt everything if it's negative.
                    return signedCoefficientB < 0;
                }
                signedCoefficientB = tmp;
                exponentB--;
            }
        }

        return gtSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function ltSlow(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        // If the exponents are the same we compare the coefficients.
        if (exponentA == exponentB) {
            return signedCoefficientA < signedCoefficientB;
        }

        // Comparisons with zero ignore exponents.
        if (signedCoefficientA == 0 || signedCoefficientB == 0) {
            return signedCoefficientA < signedCoefficientB;
        }

        unchecked {
            int256 tmp = 0;
            while (exponentA > exponentB) {
                tmp = signedCoefficientA * 10;
                if (tmp / 10 != signedCoefficientA) {
                    // A overflowed so is huge in magnitude, it's gt everything
                    // if positive and lt everything if it's negative.
                    return signedCoefficientA < 0;
                }
                signedCoefficientA = tmp;
                exponentA--;
            }

            while (exponentB > exponentA) {
                tmp = signedCoefficientB * 10;
                if (tmp / 10 != signedCoefficientB) {
                    // B overflowed so is huge in magnitude, it's gt everything
                    // if positive and lt everything if it's negative.
                    return signedCoefficientB > 0;
                }
                signedCoefficientB = tmp;
                exponentB--;
            }
        }

        return ltSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }
}
