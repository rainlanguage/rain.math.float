// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LOG10_RAW_ERROR, POW10_RAW_ERROR, POW_GUARD} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {
    DOCUMENTED_LOG10_RAW_ERROR,
    DOCUMENTED_POW10_RAW_ERROR,
    DOCUMENTED_POW_GUARD
} from "test/lib/LibTestErrorBound.sol";

/// The implementation's error constants are the documented ones the tests
/// bound against.
contract LibDecimalFloatImplementationDocumentedErrorsTest is Test {
    function testLog10RawErrorDocumented() external pure {
        assertEq(LOG10_RAW_ERROR, DOCUMENTED_LOG10_RAW_ERROR);
    }

    function testPow10RawErrorDocumented() external pure {
        assertEq(POW10_RAW_ERROR, DOCUMENTED_POW10_RAW_ERROR);
    }

    function testPowGuardDocumented() external pure {
        assertEq(POW_GUARD, DOCUMENTED_POW_GUARD);
    }
}
