// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../../abstract/LogTest.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationLookupLogTableValTest is LogTest {
    function checkLookupLogTableVal(uint256 idx, uint256 expectedResult) internal {
        address tables = logTables();
        uint256 result = LibDecimalFloatImplementation.lookupLogTableVal(tables, idx);
        assertEq(result, expectedResult);
    }

    function testLookupLogTableVal() external {
        checkLookupLogTableVal(0, 0);
        checkLookupLogTableVal(10, 43);
        checkLookupLogTableVal(100, 414);
        checkLookupLogTableVal(200, 792);
        checkLookupLogTableVal(300, 1139);
        checkLookupLogTableVal(400, 1461);
        checkLookupLogTableVal(500, 1761);
        checkLookupLogTableVal(600, 2041);
        checkLookupLogTableVal(700, 2304);
        checkLookupLogTableVal(800, 2553);
        checkLookupLogTableVal(900, 2788);
        checkLookupLogTableVal(1000, 3010);
        checkLookupLogTableVal(1100, 3222);
        checkLookupLogTableVal(1200, 3424);
        checkLookupLogTableVal(1300, 3617);
        checkLookupLogTableVal(1400, 3802);
        checkLookupLogTableVal(1500, 3979);
        checkLookupLogTableVal(1600, 4150);
        checkLookupLogTableVal(1700, 4314);
        checkLookupLogTableVal(1800, 4472);
        checkLookupLogTableVal(1900, 4624);
        checkLookupLogTableVal(2000, 4771);
        checkLookupLogTableVal(2100, 4914);
        checkLookupLogTableVal(2200, 5051);
        checkLookupLogTableVal(2300, 5185);
        checkLookupLogTableVal(2400, 5315);
        checkLookupLogTableVal(2500, 5441);
        checkLookupLogTableVal(2600, 5563);
        checkLookupLogTableVal(2700, 5682);
        checkLookupLogTableVal(2800, 5798);
        checkLookupLogTableVal(2900, 5911);
        checkLookupLogTableVal(3000, 6021);
        checkLookupLogTableVal(3100, 6128);
        checkLookupLogTableVal(3200, 6232);
        checkLookupLogTableVal(3300, 6335);
        checkLookupLogTableVal(3400, 6435);
        checkLookupLogTableVal(3500, 6532);
        checkLookupLogTableVal(3600, 6628);
        checkLookupLogTableVal(3700, 6721);
        checkLookupLogTableVal(3800, 6812);
        checkLookupLogTableVal(3900, 6902);
        checkLookupLogTableVal(4000, 6990);
        checkLookupLogTableVal(4100, 7076);
        checkLookupLogTableVal(4200, 7160);
        checkLookupLogTableVal(4300, 7243);
        checkLookupLogTableVal(4400, 7324);
        checkLookupLogTableVal(4500, 7404);
        checkLookupLogTableVal(4600, 7482);
        checkLookupLogTableVal(4700, 7559);
        checkLookupLogTableVal(4800, 7634);
        checkLookupLogTableVal(4900, 7709);
        checkLookupLogTableVal(5000, 7782);
        checkLookupLogTableVal(5100, 7853);
        checkLookupLogTableVal(5200, 7924);
        checkLookupLogTableVal(5300, 7993);
        checkLookupLogTableVal(5400, 8062);
        checkLookupLogTableVal(5500, 8129);
        checkLookupLogTableVal(5600, 8195);
        checkLookupLogTableVal(5700, 8261);
        checkLookupLogTableVal(5800, 8325);
        checkLookupLogTableVal(5900, 8388);
        checkLookupLogTableVal(6000, 8451);
        checkLookupLogTableVal(6100, 8513);
        checkLookupLogTableVal(6200, 8573);
        checkLookupLogTableVal(6300, 8633);
        checkLookupLogTableVal(6400, 8692);
        checkLookupLogTableVal(6500, 8751);
        checkLookupLogTableVal(6600, 8808);
        checkLookupLogTableVal(6700, 8865);
        checkLookupLogTableVal(6800, 8921);
        checkLookupLogTableVal(6900, 8976);
        checkLookupLogTableVal(7000, 9031);
        checkLookupLogTableVal(7100, 9085);
        checkLookupLogTableVal(7200, 9138);
        checkLookupLogTableVal(7300, 9191);
        checkLookupLogTableVal(7400, 9243);
        checkLookupLogTableVal(7500, 9294);
        checkLookupLogTableVal(7600, 9345);
        checkLookupLogTableVal(7700, 9395);
        checkLookupLogTableVal(7800, 9445);
        checkLookupLogTableVal(7900, 9494);
        checkLookupLogTableVal(8000, 9542);
        checkLookupLogTableVal(8100, 9590);
        checkLookupLogTableVal(8200, 9638);
        checkLookupLogTableVal(8300, 9685);
        checkLookupLogTableVal(8400, 9731);
        checkLookupLogTableVal(8500, 9777);
        checkLookupLogTableVal(8600, 9823);
        checkLookupLogTableVal(8700, 9868);
        checkLookupLogTableVal(8800, 9912);
        checkLookupLogTableVal(8900, 9956);
        checkLookupLogTableVal(8999, 10000);
    }
}
