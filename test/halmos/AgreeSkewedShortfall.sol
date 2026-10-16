// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AgreeHalmosTest} from "./Agree.halmos.t.sol";

/// `maximize` of a negative returns the shortfall one too high.
contract AgreeSkewedShortfall is AgreeHalmosTest {
    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me, int256 s) = LibDecimalFloatImplementation.maximize(c, e);
        return (m, me, c < 0 ? s + 1 : s);
    }
}
