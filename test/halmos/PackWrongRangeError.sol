// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// `pack` as the library has it, except at the definite range errors: a
/// nonzero c at an exponent at most int32.min - 78 underflows and at least
/// int32.max + 68 overflows, where `rangeError` answers instead.
abstract contract PackWrongRangeError is PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c != 0 && e <= FMIN - 78) return rangeError(true, c, e);
        if (c != 0 && e >= FMAX + 68) return rangeError(false, c, e);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    function rangeError(bool underflow, int256 c, int256 e) internal pure virtual returns (Float);
}
