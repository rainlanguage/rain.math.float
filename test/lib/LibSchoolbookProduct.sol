// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// The 512 bit product of two words by schoolbook multiplication of 128 bit
/// limbs, independent of the CRT trick `mul512` uses.
library LibSchoolbookProduct {
    uint256 internal constant LIMB_MASK = type(uint128).max;

    function product(uint256 a, uint256 b) internal pure returns (uint256 high, uint256 low) {
        uint256 lowLow = (a & LIMB_MASK) * (b & LIMB_MASK);
        uint256 lowHigh = (a & LIMB_MASK) * (b >> 128);
        uint256 highLow = (a >> 128) * (b & LIMB_MASK);
        uint256 highHigh = (a >> 128) * (b >> 128);
        uint256 middle = (lowLow >> 128) + (lowHigh & LIMB_MASK) + (highLow & LIMB_MASK);
        low = (lowLow & LIMB_MASK) | ((middle & LIMB_MASK) << 128);
        high = highHigh + (lowHigh >> 128) + (highLow >> 128) + (middle >> 128);
    }
}
