// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AgreeHalmosTest} from "./Agree.halmos.t.sol";

/// `Impl.add` reverts on a positive first operand.
contract AgreeAddReverts is AgreeHalmosTest {
    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        if (ca > 0) revert();
        return LibDecimalFloatImplementation.add(ca, ea, cb, eb);
    }
}
