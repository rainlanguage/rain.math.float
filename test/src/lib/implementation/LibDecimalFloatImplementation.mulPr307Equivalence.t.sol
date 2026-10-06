// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatImplementationMulPr307} from "test/lib/LibDecimalFloatImplementationMulPr307.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

/// `mul` returns and reverts the same bytes as the #307 head it was
/// restructured from.
contract LibDecimalFloatImplementationMulPr307EquivalenceTest is Test {
    function pr307Mul(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationMulPr307.mul(a, ea, b, eb);
    }

    function liveMul(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.mul(a, ea, b, eb);
    }

    function checkSame(int256 a, int256 ea, int256 b, int256 eb) internal view {
        (bool okPr307, bytes memory pr307) = address(this).staticcall(abi.encodeCall(this.pr307Mul, (a, ea, b, eb)));
        (bool okLive, bytes memory live) = address(this).staticcall(abi.encodeCall(this.liveMul, (a, ea, b, eb)));
        assertEq(okLive, okPr307, "success");
        assertEq(live, pr307, "bytes");
    }

    function testMulPr307EquivalenceAny(int256 a, int256 ea, int256 b, int256 eb) external view {
        checkSame(a, ea, b, eb);
    }

    function testMulPr307EquivalencePacked(int224 a, int32 ea, int224 b, int32 eb) external view {
        checkSame(a, ea, b, eb);
    }

    /// Exponents straddling the fast path's [-2^253, 2^253) edges.
    function testMulPr307EquivalenceWideEdge(int256 a, int256 ea, int256 b, int256 eb, bool aNeg, bool bNeg)
        external
        view
    {
        ea = bound(ea, 2 ** 253 - 100, 2 ** 253 + 100);
        eb = bound(eb, 2 ** 253 - 100, 2 ** 253 + 100);
        checkSame(a, aNeg ? -ea : ea, b, bNeg ? -eb : eb);
    }

    /// Exponent sums near either end of int256.
    function testMulPr307EquivalenceNearBounds(int256 a, int256 ea, int256 b, int256 eb, bool top) external view {
        int256 m = type(int256).max;
        if (top) {
            ea = bound(ea, m - 200, m);
            eb = bound(eb, -200, 200);
        } else {
            ea = bound(ea, type(int256).min, type(int256).min + 200);
            eb = bound(eb, -200, 200);
        }
        checkSame(a, ea, b, eb);
        checkSame(b, eb, a, ea);
    }

    function testMulPr307EquivalenceExamples() external view {
        int256 m = type(int256).max;
        int256 n = type(int256).min;
        int256 c = type(int224).max;
        checkSame(1, m, 1, 1);
        checkSame(1, m - 78, 1, 0);
        checkSame(1, m - 77, c, 0);
        checkSame(-c, m - 100, c, 0);
        checkSame(1, n, 1, -1);
        checkSame(m, m, m, m);
        checkSame(n, n, n, n);
        checkSame(n, m, m, n);
        checkSame(7, 2 ** 253, 3, -(2 ** 253));
        checkSame(7, 2 ** 253 - 1, 3, 2 ** 253 - 1);
        checkSame(7, -(2 ** 253), 3, -(2 ** 253));
        checkSame(7, -(2 ** 253) - 1, 3, -(2 ** 253));
    }
}
