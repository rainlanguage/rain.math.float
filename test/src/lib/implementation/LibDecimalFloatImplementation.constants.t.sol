// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    FIVE_INVERSE,
    POW_FIXED_ONE_ODD,
    POW_FIXED_ONE_ODD_INVERSE
} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";

/// The modular inverses the implementation divides by: each times what it
/// inverts is one modulo 2^256.
contract LibDecimalFloatImplementationConstantsTest is Test {
    function testFiveInverse() external pure {
        unchecked {
            assertEq(FIVE_INVERSE * 5, 1);
        }
    }

    function testPowFixedOneOddInverse() external pure {
        unchecked {
            assertEq(POW_FIXED_ONE_ODD_INVERSE * POW_FIXED_ONE_ODD, 1);
        }
    }
}
