// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AgreeHalmosTest} from "./Agree.halmos.t.sol";

/// `Impl.sub` of a zero subtrahend, `Impl.add` on a positive first operand and
/// `maximize` of a negative return the coefficient one too high.
contract AgreeSkewedCoefficient is AgreeHalmosTest {
    function implSub(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.sub(ca, ea, cb, eb);
        return (cb == 0 ? c + 1 : c, e);
    }

    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, cb, eb);
        return (ca > 0 ? c + 1 : c, e);
    }

    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me, int256 s) = LibDecimalFloatImplementation.maximize(c, e);
        return (c < 0 ? m + 1 : m, me, s);
    }
}
