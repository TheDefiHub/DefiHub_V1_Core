// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

interface ITokenLaunchPad {
    function createNewFarm(
        address _tokenOwner,
        address _rewardsToken,
        address _stakingToken,
        uint _rewardsDurationInDays,
        uint _rawardsTokenDecimals,
        uint _totalRwards
    ) external;
    function addRewardsAndDuration(address _farmToUpdate, uint _extraRewards) external;
    function addRewardsWithoutAddingDuration(address _farmToUpdate, uint _extraRewards) external;
}