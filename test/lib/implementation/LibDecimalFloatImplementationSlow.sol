// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

library LibDecimalFloatImplementationSlow {
    function isNormalizedSlow(int256 signedCoefficient, int256 exponent) internal pure returns (bool) {
        return (signedCoefficient < 1e38 && signedCoefficient >= 1e37)
            || (signedCoefficient > -1e38 && signedCoefficient <= -1e37) || (signedCoefficient == 0 && exponent == 0);
    }
}
