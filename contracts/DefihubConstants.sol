// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

library DefihubConstants {
    address public constant FEE_ADDRESS = 0x0b894Caa813254e0a1e9F40Ec40685a2706178A4;

    uint public constant BASE_POINTS = 10000; // 10K basepoints for 100%
    uint public constant NFT_SHARES_FEE_BP = 50; // 0.5% (50 base points)
    uint public constant FAAS_ENTRANCE_FEE_BP = 100; // 1% (100 base points)

    uint public constant DAY_MULTIPLIER = 86400;
}