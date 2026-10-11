// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal, U512} from "test/lib/LibTestExactDecimal.sol";

contract LibTestExactDecimalQuotientTest is Test {
    /// `quotient` is `|a / b|` truncated to 71 or 72 digits: q × |b| ≤ |a| × 10^k < (q + 1) × |b|.
    function checkQuotient(int224 ca, int32 ea, int224 cb, int32 eb) internal pure {
        vm.assume(cb != 0);
        (U512 memory q, int256 e) = LibTestExactDecimal.quotient(ca, ea, cb, eb);
        U512 memory a = LibTestExactDecimal.u512(LibTestExactDecimal.abs(ca));
        uint256 b = LibTestExactDecimal.abs(cb);
        if (ca == 0) {
            assertTrue(LibTestExactDecimal.isZero(q), "zero");
            return;
        }
        assertEq(q.hi, 0, "q fits");
        int256 d = LibTestExactDecimal.digits(q);
        assertTrue(d == 71 || d == 72, "digits");
        assertLe(LibTestExactDecimal.cmpScaled(LibTestExactDecimal.mul(q.lo, b), e + eb, a, ea), 0, "q not above");
        assertGt(LibTestExactDecimal.cmpScaled(LibTestExactDecimal.mul(q.lo + 1, b), e + eb, a, ea), 0, "q + 1 above");
    }

    function testQuotientTruncates(int224 ca, int32 ea, int224 cb, int32 eb) external pure {
        checkQuotient(ca, ea, cb, eb);
    }

    /// The digit-count extremes of both operands and their signs.
    function testQuotientExtremes() external pure {
        int224[8] memory c = [
            type(int224).max,
            type(int224).min,
            int224(1),
            int224(-1),
            int224(9),
            int224(10),
            int224(1e67),
            int224(1e67 - 1)
        ];
        for (uint256 i = 0; i < c.length; i++) {
            for (uint256 j = 0; j < c.length; j++) {
                checkQuotient(c[i], type(int32).max, c[j], type(int32).min);
            }
        }
    }
}
