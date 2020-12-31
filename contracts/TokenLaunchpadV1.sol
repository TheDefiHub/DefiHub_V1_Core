// SPDX-License-Identifier: MIT

// This is the V1 of the token launch pad contract.
// The contract can create a token for you and can create farms for that token
// The contract creates a farm for you with the farming token and reward token you specify
// The farming token can be any valid ERC20 token, this includes LP tokens from UniSwap and other exchanges
// For rewardToken the contract also creates a fram with the DefiHub as a farming token
// The contract also has an option to add extra rewards to the farms.
// Adding extra rewards will happen in a 50/50 split between the DefiHub farm and your farm of choise

pragma solidity ^0.7.1;

import "./FarmAsAServiceV1.sol";
import "./interfaces/IFarmAsAServiceV1.sol";
import "./interfaces/ITokenAsAServiceV1Factory.sol";
import "./interfaces/ITokenLaunchPad.sol";

// Openzeppelin import
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract TokenLaunchpadV1 is ITokenLaunchPad {

    using SafeMath for uint;

    // The native token of the DefiHub project
    address defiHubTokenAddress;

    address tokenFactory;

    // tokenToFarm => (tokenToFarmWith => CreatedFarm)
    mapping (address => mapping (address => address)) createdTokenFarms;

    // CreatedFarm => DefiHubFarm
    mapping (address => address) defiHubFarmCouples;

    // TokenAddress => bool
    mapping (address => bool) tokenAsAServiceTokens;

    modifier onlyDefiHubTokens(address addr) {
        require(tokenAsAServiceTokens[addr] == true, 'Only DefiHub tokens are allowed');
        _;
    }

    // Constrcutor sets the address of the native DefiHub token
    constructor(address _defiHubTokenAddress, address _tokenFactory) {
        defiHubTokenAddress = _defiHubTokenAddress;
        tokenFactory = _tokenFactory;
    }

    function createToken(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint _initialSupply,
        uint _initialOwnerShare,
        bool _initialSupplyIsMaxSupply
    ) external {
        address token = ITokenAsAServiceV1Factory(tokenFactory).createNewToken(           
            msg.sender,
            address(this),
            _tokenName,
            _tokenSymbol,
            _initialSupply,
            _initialOwnerShare,
            _initialSupplyIsMaxSupply
        );


        tokenAsAServiceTokens[address(token)] = true;

        emit tokenCreated(address(token));
    }

    // Function to create a new farm
    function createNewFarm(
        address _tokenOwner,
        address _rewardsToken,
        address _stakingToken,
        uint _rewardsDurationInDays,
        uint _rawardsTokenDecimals,
        uint _totalRwards
    ) external override onlyDefiHubTokens(msg.sender) returns (address[2] memory) {

        // Check if the farm gets created by a Token As A Service token
        require(msg.sender == _rewardsToken, 'Not alloed');

        // First we check if this farm is already created and if there are enought fund to add to the farm
        require(createdTokenFarms[_rewardsToken][_stakingToken] == address(0), 'Farm already exists');
        require(IERC20(_rewardsToken).balanceOf(msg.sender) >= _totalRwards, 'Not enough funds');

        // Take 20% of the rewards and reserve them for the DefiHub native ntoken farm
        uint rewardsForDefiHubFarms = _totalRwards.div(100).mul(20);
        uint rewardsForDeployerFarm = _totalRwards - rewardsForDefiHubFarms;

        // Create the farm
        FarmAsAServiceV1 createdFarm = new FarmAsAServiceV1(
            address(this),
            _tokenOwner,
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
                _tokenOwner,
                _rewardsToken,
                defiHubTokenAddress,
                _rewardsDurationInDays,
                18,
                rewardsForDefiHubFarms
            );

            // Set mappings for the created farm
            address createdDefiHubFarmAddress = address(defiHubFarm);
            createdTokenFarms[_rewardsToken][defiHubTokenAddress] = createdDefiHubFarmAddress;
        } else {
            // If there already is a farm add the fund to it
            IFarmAsAServiceV1(createdTokenFarms[_rewardsToken][defiHubTokenAddress]).increaseRewards(rewardsForDefiHubFarms);
            emit rewardsAdded(rewardsForDefiHubFarms);
        }
        
        // Set all the mappings
        address createdFarmAddress = address(createdFarm);
        createdTokenFarms[_rewardsToken][_stakingToken] = createdFarmAddress;
        defiHubFarmCouples[createdFarmAddress] = createdTokenFarms[_rewardsToken][defiHubTokenAddress];
        defiHubFarmCouples[createdTokenFarms[_rewardsToken][defiHubTokenAddress]] = createdFarmAddress;
        return [createdFarmAddress, createdTokenFarms[_rewardsToken][defiHubTokenAddress]];
    }

    // Adding funds goes in a 20/80 split between the DefiHun token farm and the farm with the other token
    // This function will also reset the farm duration to its initial duration.
    // So if the farm lastes for 100 days, that will now run a 100 days after you called this function and added rewards
    function addRewardsAndDuration(address _farmToUpdate, uint _extraRewards) external override onlyDefiHubTokens(msg.sender) {
        uint rewardsForDefiHubFarms = _extraRewards.div(5);
        uint rewardsForDeployerFarm = _extraRewards.sub(rewardsForDefiHubFarms);

        require(rewardsForDefiHubFarms + rewardsForDeployerFarm <= _extraRewards, 'Overflow danger, change amount');
            
        IFarmAsAServiceV1(_farmToUpdate).increaseRewardsAndFarmDuration(rewardsForDeployerFarm);
        IFarmAsAServiceV1(defiHubFarmCouples[_farmToUpdate]).increaseRewardsAndFarmDuration(rewardsForDefiHubFarms);
        emit rewardsAdded(_extraRewards);
    }

    // Adding funds goes in a 20/80 split between the DefiHun token farm and the farm with the other token
    // You will add funds and increase the rewardRate with this function, the lefotover duration of the farm stays as is
    function addRewardsWithoutAddingDuration(address _farmToUpdate, uint _extraRewards) external override onlyDefiHubTokens(msg.sender) {        
        uint rewardsForDefiHubFarms = _extraRewards.div(5);
        uint rewardsForDeployerFarm = _extraRewards.sub(rewardsForDefiHubFarms);

        require(rewardsForDefiHubFarms + rewardsForDeployerFarm <= _extraRewards, 'Provide an amount dividable by 5 without decimals to prevent overflow');
            
        IFarmAsAServiceV1(_farmToUpdate).increaseRewards(rewardsForDeployerFarm);
        IFarmAsAServiceV1(defiHubFarmCouples[_farmToUpdate]).increaseRewards(rewardsForDefiHubFarms);
        emit rewardsAdded(_extraRewards);
    }

    /**************************
             Events 
    **************************/
    event rewardsAdded(uint _amount);
    event tokenCreated(address _tokenAddress);


}