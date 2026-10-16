// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {LibTestFloatZero} from "./LibTestFloatZero.sol";

/// `zeroAt` places the exponent where `unpack` reads it, so the zeros the
/// floor and ceil tests feed in differ from `FLOAT_ZERO` at every exponent but
/// zero.
contract LibTestFloatZeroTest is Test {
    function testZeroAtUnpacks(int32 e) external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(LibTestFloatZero.zeroAt(e));
        assertEq(signedCoefficient, 0, "coefficient");
        assertEq(exponent, int256(e), "exponent");
    }
}
