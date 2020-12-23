// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

interface IFarmAsAServiceV1 {
    function increaseRewardsAndFarmDuration(uint reward) external;
    function increaseRewards(uint reward) external;
}