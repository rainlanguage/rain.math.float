// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

/// @dev Fixed point one for the oracle, twenty digits past the library's 1e50.
uint256 constant ORACLE_ONE = 1e70;

/// @dev ln(10) at `ORACLE_ONE`, truncated, from `bc -l` at scale 100.
uint256 constant ORACLE_LN10 = 23025850929940456840179914546843642076011014886287729760333279009675726;

/// @dev ln(2) at `ORACLE_ONE`, truncated, from `bc -l` at scale 120.
uint256 constant ORACLE_LN2 = 6931471805599453094172321214581765680755001343602552541206800094933936;

/// Reference values for log10 and 10^x, independent of the library: plain
/// Taylor series over OpenZeppelin's `mulDiv`, against `bc` constants.
library LibTranscendentalOracle {
    /// log10 of the primes the tests raise, at `ORACLE_ONE`, truncated, from
    /// `bc -l` at scale 100.
    function log10Prime(uint256 prime) internal pure returns (uint256) {
        if (prime == 2) {
            return 3010299956639811952137388947244930267681898814621085413104274611271081;
        } else if (prime == 3) {
            return 4771212547196624372950279032551153092001288641906958648298656403052291;
        } else if (prime == 7) {
            return 8450980400142568307122162585926361934835723963239654065036349537182534;
        }
        revert("prime");
    }

    /// The largest j with prime^j below 1e30.
    function maxPower(uint256 prime) internal pure returns (uint256) {
        if (prime == 2) {
            return 99;
        } else if (prime == 3) {
            return 62;
        }
        return 35;
    }

    /// ln(1 + u) / u at `ORACLE_ONE` for u = d / 10^p, negated when `negative`,
    /// by the Taylor series of ln(1 + u), for |u| at most 1e-3.
    function lnOnePlusOverU(uint256 d, uint256 p, bool negative) internal pure returns (uint256) {
        return lnOnePlusOverRatio(d, 10 ** p, negative);
    }

    /// ln(1 + u) / u at `ORACLE_ONE` for u = d / scale, negated when
    /// `negative`, for |u| at most 1.1e-3. Within 50 units of 1e-70: under 25
    /// terms are nonzero, each power floors a unit plus 1.1e-3 of the previous
    /// power's loss, and each divide floors one more.
    function lnOnePlusOverRatio(uint256 d, uint256 scale, bool negative) internal pure returns (uint256) {
        uint256 sum = ORACLE_ONE;
        uint256 power = ORACLE_ONE;
        for (uint256 k = 2; power > 0; k++) {
            power = Math.mulDiv(power, d, scale);
            // ln(1 - u) / -u has every term positive, ln(1 + u) / u alternates.
            if (negative || k % 2 == 1) {
                sum += power / k;
            } else {
                sum -= power / k;
            }
        }
        return sum;
    }

    /// log10(1 + u) at `ORACLE_ONE` for u = d / 10^p, negated when `negative`.
    /// Only valid while d * 1e70 / 10^p is exact, i.e. p at most 70.
    function log10OnePlus(uint256 d, uint256 p, bool negative) internal pure returns (int256) {
        uint256 u = Math.mulDiv(d, ORACLE_ONE, 10 ** p);
        int256 log = int256(Math.mulDiv(u, lnOnePlusOverU(d, p, negative), ORACLE_LN10));
        return negative ? -log : log;
    }

    /// 10^x at `ORACLE_ONE` for |x| at most 1e-3, x at `ORACLE_ONE`, by the
    /// Taylor series of e^(x ln 10).
    function exp10Small(int256 x) internal pure returns (uint256) {
        bool negative = x < 0;
        uint256 y = Math.mulDiv(uint256(negative ? -x : x), ORACLE_LN10, ORACLE_ONE);
        uint256 sum = ORACLE_ONE;
        uint256 term = ORACLE_ONE;
        for (uint256 k = 1; term > 0; k++) {
            term = Math.mulDiv(term, y, ORACLE_ONE * k);
            if (negative && k % 2 == 1) {
                sum -= term;
            } else {
                sum += term;
            }
        }
        return sum;
    }

    /// ln(x / ORACLE_ONE) at `ORACLE_ONE` for x in [ORACLE_ONE, 2 ORACLE_ONE),
    /// by 2 atanh((x - 1) / (x + 1)).
    function lnNearOne(uint256 x) internal pure returns (uint256) {
        uint256 z = Math.mulDiv(x - ORACLE_ONE, ORACLE_ONE, x + ORACLE_ONE);
        uint256 zSquared = Math.mulDiv(z, z, ORACLE_ONE);
        uint256 term = z;
        uint256 sum = 0;
        for (uint256 k = 1; term > 0; k += 2) {
            sum += term / k;
            term = Math.mulDiv(term, zSquared, ORACLE_ONE);
        }
        return 2 * sum;
    }

    /// log10(coefficient 10^exponent) for a positive coefficient, as
    /// characteristic + fraction / `ORACLE_ONE`, fraction in [0, ORACLE_ONE),
    /// within 1e-67.
    ///
    /// In units of 1e-70: the mantissa x in [1, 2) is within 4 below after its
    /// floor and up to three halvings, so z = (x - 1) / (x + 1), at most 1/3,
    /// is within 3 and 2 atanh(z) within 6.75. z^2 is within 3, so each
    /// power of z^2 is within 3 and each of the at most 74 terms within 4
    /// after its divide, 592 doubled. The truncated ln 2 adds 3, and dividing
    /// by ln 10, itself under 1e-70 relative low, leaves under 265.
    function log10(uint256 coefficient, int256 exponent) internal pure returns (int256, uint256) {
        uint256 digits = 0;
        for (uint256 rest = coefficient; rest >= 10; rest /= 10) {
            digits++;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 characteristic = int256(digits) + exponent;
        uint256 mantissa = digits <= 70 ? coefficient * 10 ** (70 - digits) : coefficient / 10 ** (digits - 70);
        uint256 halvings = 0;
        while (mantissa >= 2 * ORACLE_ONE) {
            mantissa /= 2;
            halvings++;
        }
        uint256 fraction = Math.mulDiv(halvings * ORACLE_LN2 + lnNearOne(mantissa), ORACLE_ONE, ORACLE_LN10);
        if (fraction >= ORACLE_ONE) {
            fraction -= ORACLE_ONE;
            characteristic += 1;
        }
        return (characteristic, fraction);
    }

    /// 10^(signedCoefficient 10^exponent) as power 10^powerExponent, power in
    /// [ORACLE_ONE, 10 ORACLE_ONE], within 1e-67 relative, for an integer part
    /// that fits int256.
    ///
    /// Relative, in units of 1e-70: the fraction f floors under a unit, 2.31
    /// of the power. y = f ln 10 / 16, at most 0.144, is within 2 below, so
    /// e^y within 2.4. Each of the at most 45 Taylor terms floors a unit plus
    /// 0.144 of the previous term's loss, under 53. Four squarings each double
    /// the error and floor a unit: 16 (2.31 + 2.4 + 53) + 15, under 1e-67.
    function exp10(int256 signedCoefficient, int256 exponent) internal pure returns (uint256, int256) {
        int256 integer;
        uint256 fraction;
        if (exponent >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            integer = signedCoefficient * int256(10 ** uint256(exponent));
        } else if (exponent >= -76) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 unit = int256(10 ** uint256(-exponent));
            integer = signedCoefficient / unit;
            int256 remainder = signedCoefficient % unit;
            if (remainder < 0) {
                integer -= 1;
                remainder += unit;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            fraction = Math.mulDiv(uint256(remainder), ORACLE_ONE, uint256(unit));
        } else {
            // |x| is below 1, and its digits past 1e-70 are dropped.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 shift = uint256(-70 - exponent);
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 magnitude = signedCoefficient < 0 ? uint256(-signedCoefficient) : uint256(signedCoefficient);
            fraction = shift > 77 ? 0 : magnitude / 10 ** shift;
            if (signedCoefficient < 0 && fraction > 0) {
                integer = -1;
                fraction = ORACLE_ONE - fraction;
            }
        }
        uint256 reduced = Math.mulDiv(fraction, ORACLE_LN10, ORACLE_ONE << 4);
        uint256 sum = ORACLE_ONE;
        uint256 term = ORACLE_ONE;
        for (uint256 k = 1; term > 0; k++) {
            term = Math.mulDiv(term, reduced, ORACLE_ONE * k);
            sum += term;
        }
        for (uint256 i = 0; i < 4; i++) {
            sum = Math.mulDiv(sum, sum, ORACLE_ONE);
        }
        return (sum, integer - 70);
    }
}
