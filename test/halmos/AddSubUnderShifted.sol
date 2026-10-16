// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `maximize` stops one shift short: the product still exact and the
/// exponent still in range, the magnitude at most T10.
contract AddSubUnderShifted is AddSubRoundOnceHalmosTest {
    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me, int256 s) = LibDecimalFloatImplementation.maximize(c, e);
        return (m / 10, me + 1, s);
    }
}
