// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

library LibDecimalFloatSlow {
    using LibDecimalFloat for Float;

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

    function gteSlow(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        return !ltSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function lteSlow(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        return !gtSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
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

    function maximizeSlow(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            if (signedCoefficient == 0) {
                return (0, 0);
            }
            int256 trySignedCoefficient = signedCoefficient * 10;
            while (trySignedCoefficient / 10 == signedCoefficient) {
                signedCoefficient = trySignedCoefficient;
                exponent--;
                trySignedCoefficient *= 10;
            }
            return (signedCoefficient, exponent);
        }
    }
}
