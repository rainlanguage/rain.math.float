// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// Logs the gas of `unabsUnsignedMulOrDivLossy` per input, measured inside the
/// call so ABI overhead is excluded. Run with `-vv` on two trees to compare
/// them.
contract LibDecimalFloatImplementationUnabsUnsignedMulOrDivLossyGasTest is Test {
    function implGas(int256 a, int256 b, uint256 c, int256 e) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, e);
        g -= gasleft();
    }

    function testUnabsUnsignedMulOrDivLossyGas() external view {
        uint256 fits = 12345;
        uint256 min = uint256(type(int256).max) + 1;
        uint256 shed = type(uint256).max;
        console2.log("same fits", this.implGas(3, 5, fits, -7));
        console2.log("mixed fits", this.implGas(-3, 5, fits, -7));
        console2.log("mixed 2^255", this.implGas(-3, 5, min, -7));
        console2.log("same shed", this.implGas(3, 5, shed, -7));
        console2.log("mixed shed", this.implGas(-3, 5, shed, -7));
    }
}
