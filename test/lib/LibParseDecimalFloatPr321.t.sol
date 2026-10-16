// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {LibParseDecimalFloatPr321} from "./LibParseDecimalFloatPr321.sol";
import {ExponentOverflow} from "../../src/error/ErrDecimalFloat.sol";
import {ParseDecimalPrecisionLoss} from "../../src/error/ErrParse.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";

/// The frozen parse copy's own paths. The live-vs-baseline equivalence tests
/// compare only literals that are exactly a Float, so the copy's lossy,
/// overflow and shedding results are pinned here as its NatSpec states them.
contract LibParseDecimalFloatPr321Test is Test {
    function parseFrozen(string memory text) external pure returns (bytes4, Float) {
        return LibParseDecimalFloatPr321.parseDecimalFloat(text);
    }

    /// The equivalence tests' `checkParse` skips literals that are no Float, so
    /// this pins the copy's
    /// own lossy and overflow paths as its NatSpec states them: a literal
    /// that is not exactly a Float is `ParseDecimalPrecisionLoss` with a zero
    /// Float, and one past every Float reverts `ExponentOverflow` from packing.
    function testParsePr321BaseNonFloatLiterals() external {
        string[5] memory lossy = [
            "13479973333575319897333507543509815336818572211270286240551805124608",
            "13479973333575319897333507543509815336818572211270286240551805124608e2147483647",
            "1e-2147483649",
            "11e-2147483649",
            "1e-2147483716"
        ];
        for (uint256 i = 0; i < lossy.length; i++) {
            (bytes4 errorSelector, Float parsed) = this.parseFrozen(lossy[i]);
            assertEq(errorSelector, ParseDecimalPrecisionLoss.selector, lossy[i]);
            assertEq(Float.unwrap(parsed), bytes32(0), lossy[i]);
        }
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(2), int256(2147483714)));
        this.parseFrozen("2e2147483714");
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(-2), int256(2147483714)));
        this.parseFrozen("-2e2147483714");
    }

    /// 2^223 is one past int224.max, so the frozen packer's nearest-bound
    /// path reports precision loss at a representable exponent and at the
    /// ceiling, where the bound exponent is still int32.max.
    function testFrozenNearestBoundErrors() external pure {
        string memory digits = Strings.toString(uint256(1) << 223);
        string[2] memory texts = [digits, string.concat(digits, "e2147483647")];
        for (uint256 i = 0; i < texts.length; i++) {
            (bytes4 error, Float result) = LibParseDecimalFloatPr321.parseDecimalFloat(texts[i]);
            assertEq(error, ParseDecimalPrecisionLoss.selector);
            assertEq(Float.unwrap(result), bytes32(0));
        }
    }

    /// 2^223 at int32.max + 1: one shed puts the nearest bound at
    /// int32.max + 1 too, so the copy skips it and the lift reverts, as a shed
    /// coefficient has no headroom.
    function testFrozenNearestBoundPastCeiling() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1) << 223, int256(2147483648)));
        this.parseFrozen(string.concat(Strings.toString(uint256(1) << 223), "e2147483648"));
    }

    /// 2^223 + 2 ends in 0, so one shed leaves int224.max / 10 + 1 with no
    /// digit lost: one past the nearest-bound window, either sign packs
    /// exactly at exponent 1.
    function testFrozenNearestBoundWindowUpperEdge() external pure {
        int256 coefficient = int256(type(int224).max) / 10 + 1;
        for (uint256 i = 0; i < 2; i++) {
            int256 signedCoefficient = i == 0 ? coefficient : -coefficient;
            string memory text = Strings.toStringSigned(signedCoefficient * 10);
            (bytes4 error, Float result) = LibParseDecimalFloatPr321.parseDecimalFloat(text);
            assertEq(error, bytes4(0), text);
            // The coefficient's two's complement bits, masked to the low 224
            // as a Float packs a negative coefficient.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 packedCoefficient = uint256(signedCoefficient) & uint256(type(uint224).max);
            assertEq(Float.unwrap(result), bytes32(packedCoefficient | (uint256(1) << 224)), text);
        }
    }

    /// Coefficients past int224 that start at or below the ceiling and shed
    /// past it, so the ceiling branch is reached by shedding alone: 2^223 + 20
    /// at int32.max sheds one digit to int224.max / 10 + 2, past the
    /// nearest-bound window, at int32.max + 1, 1e76 at int32.max - 7 sheds
    /// nine to 1e67 at int32.max + 2, and 2e76 at int32.max - 9 sheds ten, the
    /// most any int256 sheds, to 2e66 at int32.max + 1 (shed counts from bc).
    /// A shed coefficient has no headroom to lift, so each reverts with its
    /// original inputs.
    function testFrozenShedPastCeilingReverts() external {
        int256 pastWindow = (int256(1) << 223) + 20;
        int256[4] memory coefficients = [pastWindow, -pastWindow, int256(1e76), int256(2e76)];
        int256[4] memory exponents =
            [int256(type(int32).max), type(int32).max, int256(type(int32).max) - 7, int256(type(int32).max) - 9];
        for (uint256 i = 0; i < coefficients.length; i++) {
            string memory text =
                string.concat(Strings.toStringSigned(coefficients[i]), "e", Strings.toStringSigned(exponents[i]));
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, coefficients[i], exponents[i]));
            this.parseFrozen(text);
        }
    }

    /// 1e76 at int256.max sheds nine digits, which wraps the exponent through
    /// int256.max to int256.min + 8. The ceiling branch still owns it: a shed
    /// coefficient has no headroom, so either sign reverts with its original
    /// inputs and never reaches the floor path as precision loss.
    function testFrozenShedWrapsThroughInt256MaxReverts() external {
        int256[2] memory coefficients = [int256(1e76), -int256(1e76)];
        for (uint256 i = 0; i < coefficients.length; i++) {
            string memory text =
                string.concat(Strings.toStringSigned(coefficients[i]), "e", Strings.toStringSigned(type(int256).max));
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, coefficients[i], type(int256).max));
            this.parseFrozen(text);
        }
    }

    /// A 77-digit coefficient sheds 10 digits to fit int224 and the 67 left to
    /// reach the int32 floor, so it underflows to zero and is loss. Past the
    /// shed-to-zero return, the rise of 77 would wrap `int256(10 ** 77)` to
    /// -(2^256 - 10^77), which this coefficient is twice, and the lossless
    /// test would accept the zero.
    function testFrozenFloorShedsAllAfterFit() external pure {
        (bytes4 errorSelector, Float parsed) = LibParseDecimalFloatPr321.parseDecimalFloat(
            "31584178474632390847141970017375815706539969331281128078915168015826259279872e-2147483725"
        );
        assertEq(errorSelector, ParseDecimalPrecisionLoss.selector);
        assertEq(Float.unwrap(parsed), bytes32(0));
    }

    /// Below the int32 floor the frozen packer sheds exactly the shortfall in
    /// digits, for one, seven and 67 digits, and an underflow to zero is loss.
    /// Expected bits follow the Float representation, not the live packer.
    function testFrozenFloorPacking() external pure {
        string[4] memory texts = [
            "10e-2147483649",
            "100e-2147483649",
            "10000000e-2147483655",
            string.concat(Strings.toString(10 ** 67), "e-2147483715")
        ];
        uint256[4] memory coefficients = [uint256(1), 10, 1, 1];
        // The exponent's two's complement bits, as the top 32 bits of a Float.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 floorExponent = uint256(uint32(type(int32).min)) << 224;
        for (uint256 i = 0; i < texts.length; i++) {
            (bytes4 error, Float result) = LibParseDecimalFloatPr321.parseDecimalFloat(texts[i]);
            assertEq(error, bytes4(0));
            assertEq(Float.unwrap(result), bytes32(coefficients[i] | floorExponent));
        }
        (bytes4 underflowError, Float underflowResult) = LibParseDecimalFloatPr321.parseDecimalFloat("1e-2147483649");
        assertEq(underflowError, ParseDecimalPrecisionLoss.selector);
        assertEq(Float.unwrap(underflowResult), bytes32(0));
    }

    /// One past the ceiling, lifting by ten: `int224.max / 10 + 1` of either
    /// sign overflows int224 and reverts with the original inputs, while one
    /// less lifts exactly to int32.max.
    function testFrozenCeilingHeadroom() external {
        int256 firstOverflow = int256(type(int224).max) / 10 + 1;
        int256 exponent = int256(type(int32).max) + 1;
        for (uint256 i = 0; i < 2; i++) {
            int256 coefficient = i == 0 ? firstOverflow : -firstOverflow;
            string memory text = string.concat(Strings.toStringSigned(coefficient), "e2147483648");
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, coefficient, exponent));
            this.parseFrozen(text);
            coefficient = i == 0 ? firstOverflow - 1 : -(firstOverflow - 1);
            text = string.concat(Strings.toStringSigned(coefficient), "e2147483648");
            (bytes4 error, Float result) = LibParseDecimalFloatPr321.parseDecimalFloat(text);
            assertEq(error, bytes4(0));
            // The lifted coefficient's two's complement bits, masked to the
            // low 224 as a Float packs a negative coefficient.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 packedCoefficient = uint256(coefficient * 10) & uint256(type(uint224).max);
            uint256 packedExponent = uint256(uint32(type(int32).max)) << 224;
            assertEq(Float.unwrap(result), bytes32(packedCoefficient | packedExponent));
        }
    }
}
