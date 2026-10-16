// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, ExponentUnderflow} from "../../src/error/ErrDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// Forge checks on the scaffolding of `PackArithmeticResult.halmos.t.sol`. A
/// range or class split with a gap passes halmos with every job green, so
/// this holds the splits to the header's tiling claim: Below, Low, Middle,
/// High and Above tile the int256 exponents and the size classes tile the
/// int256 coefficients (`vm.expectCall` counts the nested `pack`). A weakened
/// `checkPack` assertion passes halmos too, so the harness contracts below
/// each override `pack` to be wrong in one way and check the lemma rejects
/// it.
contract PackArithmeticResultCoverTest is Test, PackArithmeticResultHalmosTest {
    /// The bits Low and High split their exponent index from, and every
    /// lemma its class index.
    uint256 internal constant EXPONENT_BITS = 7;
    uint256 internal constant CLASS_BITS = 4;
    /// The int224 bounds: class 0's last magnitude in each sign.
    int256 internal constant INT224_MAX = 2 ** 223 - 1;
    int256 internal constant INT224_MIN = -(2 ** 223);

    /// Both ends of the five exponent ranges: int256.min and int32.min - 78
    /// (Below), int32.min - 77 and int32.min (Low), int32.min + 1 and
    /// int32.max - 11 (Middle), int32.max - 10 and int32.max + 67 (High),
    /// int32.max + 68 and int256.max (Above).
    function exponentEdges() internal pure returns (int256[10] memory) {
        return [
            type(int256).min,
            FMIN - 78,
            FMIN - 77,
            FMIN,
            FMIN + 1,
            FMAX - 11,
            FMAX - 10,
            FMAX + 67,
            FMAX + 68,
            type(int256).max
        ];
    }

    /// Zero and both ends of every size class in both signs: class 0 is the
    /// int224s, class 1 the 68-digit magnitudes past them, class i in [2, 9]
    /// the 66 + i digit magnitudes, and class 10 the 77-digit ones up to the
    /// int256 extremes.
    function classEdges() internal pure returns (int256[45] memory cs) {
        cs[0] = 0;
        cs[1] = 1;
        cs[2] = -1;
        cs[3] = INT224_MAX;
        cs[4] = INT224_MIN;
        cs[5] = INT224_MAX + 1;
        cs[6] = INT224_MIN - 1;
        cs[7] = 1e68 - 1;
        cs[8] = -(1e68 - 1);
        uint256 n = 9;
        for (uint256 i = 2; i <= 9; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 low = int256(10 ** (66 + i));
            int256 high = low * 10 - 1;
            cs[n++] = low;
            cs[n++] = high;
            cs[n++] = -low;
            cs[n++] = -high;
        }
        cs[n++] = 1e76;
        cs[n++] = type(int256).max;
        cs[n++] = -1e76;
        cs[n++] = type(int256).min;
        assertEq(n, cs.length);
    }

    /// At every exponent edge, every class edge reaches `pack(c, e)` in
    /// exactly one lemma at one of the case indices its bits give.
    function testEveryExponentAndClassReachesPackOnce() external {
        int256[10] memory es = exponentEdges();
        int256[45] memory cs = classEdges();
        for (uint256 a = 0; a < cs.length; a++) {
            int256 c = cs[a];
            for (uint256 b = 0; b < es.length; b++) {
                vm.expectCall(address(this), abi.encodeCall(this.pack, (c, es[b])), 1);
            }
            for (uint256 i = 0; i < 2 ** CLASS_BITS; i++) {
                for (uint256 b = 0; b < es.length; b++) {
                    this.check_packBelow(c, es[b], i);
                    this.check_packMiddle(c, es[b], i);
                    this.check_packAbove(c, es[b], i);
                }
                for (uint256 j = 0; j < 2 ** EXPONENT_BITS; j++) {
                    this.check_packLow(c, j, i);
                    this.check_packHigh(c, j, i);
                }
            }
        }
    }

    /// The oracle's back-step threshold. With L the int224 bound of c's sign
    /// and Q = floor((L - 1) / 10) + 1, Q 10 is L + 3 for positive c and
    /// L + 2 for negative, so |c| = Q 10^k shedding k digits is exactly
    /// Q 10^k, at most L one exponent up, and is not stepped back to L; one
    /// below it is. Both sides of the threshold for every shed count in
    /// Middle, at exponent zero and at the floor where the back-step lands on
    /// int32.min.
    function testBackStepThreshold() external view {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 qPos = (uint256(INT224_MAX) - 1) / 10 + 1;
        uint256 qNeg = (uint256(2 ** 223) - 1) / 10 + 1;
        for (uint256 k = 1; k <= 9; k++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 pos = int256(qPos * 10 ** k);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 neg = -int256(qNeg * 10 ** k);
            int256[6] memory cs = [pos, pos - 1, pos + 1, neg, neg + 1, neg - 1];
            for (uint256 a = 0; a < cs.length; a++) {
                for (uint256 i = 1; i <= 10; i++) {
                    this.check_packMiddle(cs[a], 0, i);
                    this.check_packMiddle(cs[a], FMIN + 1, i);
                }
            }
        }
    }
}

/// `pack` reverting with the other error: `ExponentOverflow` below the
/// exponent floor and `ExponentUnderflow` above the ceiling.
contract PackArithmeticResultSwappedErrorsTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c != 0 && e <= FMIN - 78) revert ExponentOverflow(c, e);
        if (c != 0 && e >= FMAX + 68) revert ExponentUnderflow(c, e);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: a zero result for nonzero c is `ExponentUnderflow`.
    function testPackRejectsOverflowForUnderflow() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packBelow(1, FMIN - 78, 0);
    }

    /// PACK: a value past every Float is `ExponentOverflow`.
    function testPackRejectsUnderflowForOverflow() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packAbove(1, FMAX + 68, 0);
    }
}

/// `pack` reporting the exponent one above in its revert.
contract PackArithmeticResultErrorExponentTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c != 0 && e <= FMIN - 78) revert ExponentUnderflow(c, e + 1);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: the error carries e.
    function testPackRejectsAWrongErrorExponent() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packBelow(1, FMIN - 78, 0);
    }
}

/// `pack` reporting the coefficient one above in its revert.
contract PackArithmeticResultErrorCoefficientTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c != 0 && e <= FMIN - 78) revert ExponentUnderflow(c + 1, e);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: the error carries c.
    function testPackRejectsAWrongErrorCoefficient() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packBelow(1, FMIN - 78, 0);
    }
}

/// `pack` reverting with a word appended to the right error.
contract PackArithmeticResultErrorTrailingBytesTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c != 0 && e <= FMIN - 78) {
            bytes memory data = abi.encodePacked(abi.encodeWithSelector(ExponentUnderflow.selector, c, e), bytes32(0));
            assembly ("memory-safe") {
                revert(add(data, 0x20), mload(data))
            }
        }
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: the error is exactly a selector and two words.
    function testPackRejectsALongerError() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packBelow(1, FMIN - 78, 0);
    }
}

/// `pack` returning a zero coefficient at exponent one for zero.
contract PackArithmeticResultNonCanonicalZeroTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c == 0) return Float.wrap(bytes32(uint256(1) << 224));
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: zero is all bits zero.
    function testPackRejectsANonCanonicalZero() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packMiddle(0, 5, 0);
    }
}

/// `pack` returning zero where the value is below every Float.
contract PackArithmeticResultNoUnderflowTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c != 0 && e <= FMIN - 78) return Float.wrap(bytes32(0));
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: a zero result for nonzero c reverts.
    function testPackRejectsAMissingRevert() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packBelow(1, FMIN - 78, 0);
    }
}

/// `pack` reverting where the value is a Float, with the error the selector
/// check takes at status 0, so only the status check rejects it.
contract PackArithmeticResultSpuriousRevertTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c == 1 && e == 0) revert ExponentOverflow(c, e);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: a Float packs.
    function testPackRejectsASpuriousRevert() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packMiddle(1, 0, 0);
    }
}

/// `pack` returning the next Float up.
contract PackArithmeticResultWrongValueTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c == 1 && e == 0) return LibDecimalFloat.packLossless(2, 0);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: the result's value is the oracle's.
    function testPackRejectsAWrongValue() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packMiddle(1, 0, 0);
    }
}
