// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

/// Variants of `LibDecimalFloatImplementation.sqrt`, for equivalence and gas
/// comparison only.
library LibDecimalFloatSqrtVariants {
    /// The integer sqrt verbatim from 0a8065d and 7459101 on #309's branch, its
    /// residual compared in 512 bits.
    function sqrtBase(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 coefficient = uint256(signedCoefficient);
            if (coefficient < 1e75) {
                if (coefficient < 1e38) {
                    coefficient *= 1e38;
                    exponent -= 38;
                }
                if (coefficient < 1e57) {
                    coefficient *= 1e19;
                    exponent -= 19;
                }
                if (coefficient < 1e66) {
                    coefficient *= 1e10;
                    exponent -= 10;
                }
                if (coefficient < 1e71) {
                    coefficient *= 1e5;
                    exponent -= 5;
                }
                if (coefficient < 1e73) {
                    coefficient *= 1e3;
                    exponent -= 3;
                }
                if (coefficient < 1e74) {
                    coefficient *= 1e2;
                    exponent -= 2;
                }
                if (coefficient < 1e75) {
                    coefficient *= 10;
                    exponent -= 1;
                }
            }
            uint256 scale;
            uint256 estimate;
            uint256 estimateScale;
            bool odd = exponent & 1 == 1;
            if (coefficient < 1e76) {
                (scale, estimate, estimateScale) = odd ? (1e5, coefficient / 10, 1e3) : (1e6, coefficient, 1e3);
            } else {
                (scale, estimate, estimateScale) = odd ? (1e5, coefficient / 10, 1e3) : (1e4, coefficient, 1e2);
            }
            exponent = (exponent - (odd ? int256(5) : (coefficient < 1e76 ? int256(6) : int256(4)))) / 2;
            uint256 root;
            assembly ("memory-safe") {
                root := add(shr(1, shr(125, estimate)), shl(124, 1))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := sub(root, gt(root, div(estimate, root)))
            }
            root = (root + 2) * estimateScale;
            root = (root + LibDecimalFloatImplementation.mulDiv(coefficient, scale, root)) >> 1;
            (uint256 high, uint256 low) = LibDecimalFloatImplementation.mul512(coefficient, scale);
            (uint256 rootHigh, uint256 rootLow) = LibDecimalFloatImplementation.mul512(root, root);
            if (rootHigh > high || (rootHigh == high && rootLow > low)) {
                root -= 1;
                (rootHigh, rootLow) = LibDecimalFloatImplementation.mul512(root, root);
            }
            assembly ("memory-safe") {
                let differenceLow := sub(low, rootLow)
                let differenceHigh := sub(sub(high, rootHigh), lt(low, rootLow))
                root := add(root, or(gt(differenceHigh, 0), gt(differenceLow, root)))
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return (int256(root), exponent);
        }
    }

    /// The library's sqrt with its Newton iterations in plain Solidity.
    function sqrtPlainNewton(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.scaleUp(signedCoefficient, exponent);
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 coefficient = uint256(signedCoefficient);
            uint256 scale = 1e6;
            uint256 estimate = coefficient;
            if (exponent & 1 == 1) {
                scale = 1e5;
                estimate = coefficient / 10;
            }
            exponent = (exponent - (scale == 1e5 ? int256(5) : int256(6))) / 2;
            uint256 root = (estimate >> 126) + (1 << 124);
            root = (root + estimate / root) >> 1;
            root = (root + estimate / root) >> 1;
            root = (root + estimate / root) >> 1;
            root = (root + estimate / root) >> 1;
            root = (root + estimate / root) >> 1;
            root = (root + estimate / root) >> 1;
            root *= 1e3;
            root = (root + LibDecimalFloatImplementation.mulDiv(coefficient, scale, root)) >> 1;
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 residual = int256(coefficient * scale - root * root);
            // forge-lint: disable-next-line(unsafe-typecast)
            if (residual > int256(root)) {
                root += 1;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return (int256(root), exponent);
        }
    }

    /// The library's sqrt with its residual rounding in assembly.
    function sqrtAsmResidual(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.scaleUp(signedCoefficient, exponent);
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 coefficient = uint256(signedCoefficient);
            uint256 scale = 1e6;
            uint256 estimate = coefficient;
            if (exponent & 1 == 1) {
                scale = 1e5;
                estimate = coefficient / 10;
            }
            exponent = (exponent - (scale == 1e5 ? int256(5) : int256(6))) / 2;
            uint256 root;
            assembly ("memory-safe") {
                root := add(shr(126, estimate), shl(124, 1))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
            }
            root *= 1e3;
            root = (root + LibDecimalFloatImplementation.mulDiv(coefficient, scale, root)) >> 1;
            assembly ("memory-safe") {
                let residual := sub(mul(coefficient, scale), mul(root, root))
                root := add(root, sgt(residual, root))
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return (int256(root), exponent);
        }
    }
}
