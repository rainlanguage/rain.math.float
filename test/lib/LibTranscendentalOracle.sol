// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

/// @dev Fixed point one for the oracle, twenty digits past the library's 1e50.
uint256 constant ORACLE_ONE = 1e70;

/// @dev ln(10) at `ORACLE_ONE`, truncated, from `bc -l` at scale 100.
uint256 constant ORACLE_LN10 = 23025850929940456840179914546843642076011014886287729760333279009675726;

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
}
