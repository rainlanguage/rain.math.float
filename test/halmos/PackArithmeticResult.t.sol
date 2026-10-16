// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {stdError} from "forge-std-1.17.0/src/StdError.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, ExponentUnderflow} from "../../src/error/ErrDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// Subjects for the sensitivity tests below: each breaks one component of
/// what `checkPack` asserts and keeps the rest as the library has it, so the
/// lemmas fail on it only through that component.
///
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

/// A range error returns zero.
contract PackNeverReverts is PackWrongRangeError {
    function rangeError(bool, int256, int256) internal pure override returns (Float) {
        return Float.wrap(0);
    }
}

/// A range error reverts with a word past the error's two arguments.
contract PackLongError is PackWrongRangeError {
    function rangeError(bool underflow, int256 c, int256 e) internal pure override returns (Float) {
        bytes memory data = abi.encodeWithSelector(
            underflow ? ExponentUnderflow.selector : ExponentOverflow.selector, c, e, uint256(0)
        );
        assembly ("memory-safe") {
            revert(add(data, 0x20), mload(data))
        }
    }
}

/// A range error reverts with the other error.
contract PackSwappedSelector is PackWrongRangeError {
    function rangeError(bool underflow, int256 c, int256 e) internal pure override returns (Float) {
        if (underflow) revert ExponentOverflow(c, e);
        revert ExponentUnderflow(c, e);
    }
}

/// A range error reports the coefficient one too high.
contract PackWrongErrorCoefficient is PackWrongRangeError {
    function rangeError(bool underflow, int256 c, int256 e) internal pure override returns (Float) {
        if (underflow) revert ExponentUnderflow(c + 1, e);
        revert ExponentOverflow(c + 1, e);
    }
}

/// A range error reports the exponent one too high.
contract PackWrongErrorExponent is PackWrongRangeError {
    function rangeError(bool underflow, int256 c, int256 e) internal pure override returns (Float) {
        if (underflow) revert ExponentUnderflow(c, e + 1);
        revert ExponentOverflow(c, e + 1);
    }
}

/// `pack` reverts underflow for every input.
contract PackAlwaysReverts is PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        revert ExponentUnderflow(c, e);
    }
}

/// `pack` flips the low bit of the packed coefficient.
contract PackFlippedBit is PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        return Float.wrap(bytes32(uint256(Float.unwrap(LibDecimalFloat.packArithmeticResult(c, e))) ^ 1));
    }
}

/// `pack` returns a zero coefficient at exponent 1 for a zero c.
contract PackZeroWithExponent is PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c == 0) return Float.wrap(bytes32(uint256(1) << 224));
        return LibDecimalFloat.packArithmeticResult(c, e);
    }
}

/// Forge checks on the scaffolding of `PackArithmeticResult.halmos.t.sol`. A
/// range or class split with a gap passes halmos with every job green, so
/// this holds the splits to the header's tiling claim: Below, Low, Middle,
/// High and Above tile the int256 exponents and the size classes tile the
/// int256 coefficients (`vm.expectCall` counts the nested `pack`). A
/// `checkPack` that asserts less than the header says passes too, the library
/// being correct, so the sensitivity tests run the lemmas on the subjects
/// above and expect the assertion panic: a `checkPack` that drops a conjunct
/// passes its subject and fails here.
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

    /// The revert branch of `checkPack` fails on each conjunct alone: a range
    /// error that returns, a longer revert, the other error's selector, and
    /// each reported argument off by one; through Below for an int224 and
    /// for a 68 digit coefficient, and through Above.
    function testPackLemmasFailOnEachBrokenRevertConjunct() external {
        expectPackRevertFails(new PackNeverReverts());
        expectPackRevertFails(new PackLongError());
        expectPackRevertFails(new PackSwappedSelector());
        expectPackRevertFails(new PackWrongErrorCoefficient());
        expectPackRevertFails(new PackWrongErrorExponent());
    }

    function expectPackRevertFails(PackArithmeticResultHalmosTest subject) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_packBelow(1, FMIN - 78, 0);
        vm.expectRevert(stdError.assertionError);
        subject.check_packBelow(1e68, FMIN - 78, 2);
        vm.expectRevert(stdError.assertionError);
        subject.check_packAbove(-1, FMAX + 68, 0);
    }

    /// Its success branch fails on a revert alone, on the packed coefficient
    /// off by one alone and on a zero at a nonzero exponent alone; through
    /// Middle at exponent 0, Low at int32.min and High at int32.max.
    function testPackLemmasFailOnEachBrokenResultConjunct() external {
        expectPackResultFails(new PackAlwaysReverts(), 1);
        expectPackResultFails(new PackFlippedBit(), 1);
        expectPackResultFails(new PackZeroWithExponent(), 0);
    }

    function expectPackResultFails(PackArithmeticResultHalmosTest subject, int256 c) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_packMiddle(c, 0, 0);
        vm.expectRevert(stdError.assertionError);
        subject.check_packLow(c, 0, 0);
        vm.expectRevert(stdError.assertionError);
        subject.check_packHigh(c, 10, 0);
    }
}
