// SPDX-License-Identifier: MIT

// This is the V1 of the Farming as a service factory contract.
// The contract creates a farm for you with the farming token and reward token you specify
// The farming token can be any valid ERC20 token, this includes LP tokens from UniSwap and other exchanges
// For rewardToken the contract also creates a fram with the DefiHub as a farming token
// The contract also has an option to add extra rewards to the farms.
// Adding extra rewards will happen in a 50/50 split between the DefiHub farm and your farm of choise

pragma solidity ^0.7.1;

import "./FarmAsAServiceV1.sol";
import "./IFarmAsAServiceV1.sol";

// Openzeppelin import
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract FarmAsAServiceV1Factory {

    using SafeMath for uint;

    // The native token of the DefiHub project
    address defiHubTokenAddress;

    // tokenToFarm => (tokenToFarmWith => CreatedFarm)
    mapping (address => mapping (address => address)) createdTokenFarms;
        
    // CreatedFarm => FarmAdmin
    mapping (address => address) farmAdmins;

    // CreatedFarm => DefiHubFarm
    mapping (address => address) defiHubFarmCouples;

    // Constrcutor sets the address of the native DefiHub token
    constructor(address _defiHubTokenAddress) {
        defiHubTokenAddress = _defiHubTokenAddress;
    }

    // Function to create a new farm
    function createNewFarm(
        address _rewardsToken,
        address _stakingToken,
        uint _rewardsDurationInDays,
        uint _rawardsTokenDecimals,
        uint _totalRwards
    ) external returns (address[2] memory) {
        // First we check if this farm is already created and if there are enought fund to add to the farm
        require(createdTokenFarms[_rewardsToken][_stakingToken] == address(0), 'This token farm already exists!');
        require(IERC20(_stakingToken).balanceOf(msg.sender) >= _totalRwards, 'You want to add a higher amount of tokens to farm then you seem to have...');

        // Take 20% of the rewards and reserve them for the DefiHub native ntoken farm
        uint rewardsForDefiHubFarms = _totalRwards.div(100).mul(20);
        uint rewardsForDeployerFarm = _totalRwards - rewardsForDefiHubFarms;

        // Create the farm
        FarmAsAServiceV1 createdFarm = new FarmAsAServiceV1(
            address(this),
            msg.sender,
            _rewardsToken,
            _stakingToken,
            _rewardsDurationInDays,
            _rawardsTokenDecimals,
            rewardsForDeployerFarm
        );

        // Check if there alreasy is a DefiHub farm for the _rewardsToken
        if (createdTokenFarms[_rewardsToken][defiHubTokenAddress] == address(0)) {
            // If there is no DefiHub farm create it
            FarmAsAServiceV1 defiHubFarm = new FarmAsAServiceV1(
                address(this),
                msg.sender,
                _rewardsToken,
                defiHubTokenAddress,
                _rewardsDurationInDays,
                18,
                rewardsForDefiHubFarms
            );

            // Set mappings for the created farm
            address createdDefiHubFarmAddress = address(defiHubFarm);
            createdTokenFarms[_rewardsToken][defiHubTokenAddress] = createdDefiHubFarmAddress;
            farmAdmins[createdDefiHubFarmAddress] = msg.sender;
        } else {
            // If there already is a farm add the fund to it
            IFarmAsAServiceV1(createdTokenFarms[_rewardsToken][defiHubTokenAddress]).modifyRewardAmount(rewardsForDefiHubFarms);
            emit rewardsAdded(rewardsForDefiHubFarms);
        }
        
        // Set all the mappings
        address createdFarmAddress = address(createdFarm);
        createdTokenFarms[_rewardsToken][_stakingToken] = createdFarmAddress;
        farmAdmins[createdFarmAddress] = msg.sender;
        defiHubFarmCouples[createdFarmAddress] = createdTokenFarms[_rewardsToken][defiHubTokenAddress];
        defiHubFarmCouples[createdTokenFarms[_rewardsToken][defiHubTokenAddress]] = createdFarmAddress;
        return [address(createdFarm), address(createdTokenFarms[_rewardsToken][defiHubTokenAddress])];
    }

    // Adding funds goes in a 20/80 split between the DefiHun token farm and the farm with the other token
    function addRewards(address farmToUpdate, uint extraRewards) external {
        require(farmAdmins[farmToUpdate] == msg.sender, 'You are not the admin of this farm');
        
        uint rewardsForDefiHubFarms = extraRewards.div(5);
        uint rewardsForDeployerFarm = extraRewards.sub(rewardsForDefiHubFarms);

        require(rewardsForDefiHubFarms + rewardsForDeployerFarm <= extraRewards, 'Provide an amount dividable by 5 without decimals to prevent overflow')
            
        IFarmAsAServiceV1(farmToUpdate).modifyRewardAmount(rewardsForDeployerFarm);
        IFarmAsAServiceV1(defiHubFarmCouples[farmToUpdate]).modifyRewardAmount(rewardsForDefiHubFarms);
        emit rewardsAdded(extraRewards);
    }

    /**************************
             Events 
    **************************/
    event rewardsAdded(uint amount);


}