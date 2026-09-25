// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationAbsCoefficientTest is Test {
    function testAbsCoefficientPositiveUnchanged(int256 signedCoefficient) external pure {
        signedCoefficient = bound(signedCoefficient, 0, type(int224).max);
        assertEq(LibDecimalFloatImplementation.absCoefficient(signedCoefficient), signedCoefficient);
    }

    function testAbsCoefficientNegativeNegated(int256 signedCoefficient) external pure {
        signedCoefficient = bound(signedCoefficient, type(int224).min, -1);
        assertEq(LibDecimalFloatImplementation.absCoefficient(signedCoefficient), -signedCoefficient);
    }

    /// THE REASON THIS EXISTS. The packed `abs` has to fit the magnitude back
    /// into an int224, which the most negative coefficient does not, so it
    /// raises the exponent and reverts once that is at its maximum. Here the
    /// value is already an int256, so negating an int224 is exact.
    function testAbsCoefficientMostNegativeIsExact() external pure {
        assertEq(LibDecimalFloatImplementation.absCoefficient(type(int224).min), -int256(type(int224).min));
        // And the result does not fit an int224, which is precisely why the
        // packed form cannot produce it.
        assertGt(LibDecimalFloatImplementation.absCoefficient(type(int224).min), type(int224).max);
    }

    function testAbsCoefficientZero() external pure {
        assertEq(LibDecimalFloatImplementation.absCoefficient(0), 0);
    }

    /// Idempotent: taking a magnitude twice is taking it once.
    function testAbsCoefficientIdempotent(int256 signedCoefficient) external pure {
        signedCoefficient = bound(signedCoefficient, type(int224).min, type(int224).max);
        int256 once = LibDecimalFloatImplementation.absCoefficient(signedCoefficient);
        assertEq(LibDecimalFloatImplementation.absCoefficient(once), once);
    }

    /// Never negative, for any input in range.
    function testAbsCoefficientNeverNegative(int256 signedCoefficient) external pure {
        signedCoefficient = bound(signedCoefficient, type(int224).min, type(int224).max);
        assertGe(LibDecimalFloatImplementation.absCoefficient(signedCoefficient), 0);
    }
}
