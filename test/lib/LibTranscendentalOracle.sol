// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

/// @dev Fixed point one for the oracle, twenty digits past the library's 1e50.
uint256 constant ORACLE_ONE = 1e70;

/// @dev ln(10) at `ORACLE_ONE`, truncated, from `bc -l` at scale 100.
uint256 constant ORACLE_LN10 = 23025850929940456840179914546843642076011014886287729760333279009675726;

/// @dev ln(2) at `ORACLE_ONE`, truncated, from `bc -l` at scale 110.
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
        uint256 scale = 10 ** p;
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

    /// 10^t at `ORACLE_ONE` for t in [0, 1] at `ORACLE_ONE`, by the Taylor
    /// series of e^(t ln 10), at most 1e3 units below and never above.
    ///
    /// y floors twice and is under 2 units low, under 20 in the sum. A term
    /// floors to within 1 + y / k of the previous term's loss, under 3 units,
    /// over under 90 nonzero terms, and the dropped tail is under 5 units.
    function exp10Unit(uint256 t) internal pure returns (uint256) {
        uint256 y = Math.mulDiv(t, ORACLE_LN10, ORACLE_ONE);
        uint256 sum = ORACLE_ONE;
        uint256 term = ORACLE_ONE;
        for (uint256 k = 1; term > 0; k++) {
            term = Math.mulDiv(term, y, ORACLE_ONE * k);
            sum += term;
        }
        return sum;
    }

    /// log10(m) at `ORACLE_ONE` for m in [1, 10) at `ORACLE_ONE`, within 1e3
    /// units, by ln(m / 2^k) = 2 atanh((y - 1) / (y + 1)) for y = m / 2^k in
    /// [1, 2).
    ///
    /// z is at most 1/3 and floors a unit, under 2.25 units of the log. Each
    /// power of z^2 is within 2.25 units, each term within 3.25, over under
    /// 75 terms, so the doubled series is within 490 units, and k ln 2 within
    /// 3. Dividing by ln 10 gives under 220 below and 1 above.
    function log10Unit(uint256 m) internal pure returns (uint256) {
        uint256 k = 0;
        while (m >= ORACLE_ONE << (k + 1)) {
            k++;
        }
        uint256 y = m >> k;
        uint256 z = Math.mulDiv(y - ORACLE_ONE, ORACLE_ONE, y + ORACLE_ONE);
        uint256 zz = Math.mulDiv(z, z, ORACLE_ONE);
        uint256 sum = 0;
        for (uint256 j = 1; z > 0; j += 2) {
            sum += z / j;
            z = Math.mulDiv(z, zz, ORACLE_ONE);
        }
        return Math.mulDiv(k * ORACLE_LN2 + 2 * sum, ORACLE_ONE, ORACLE_LN10);
    }
}
