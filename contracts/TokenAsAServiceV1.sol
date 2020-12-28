// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import '@openzeppelin/contracts/utils/Address.sol';
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./ITokenLaunchPad.sol";

contract TokenAsAServiceV1 is ERC20 {
    using Address for address;
    using SafeMath for uint;

    bool initialSupplyIsMaxSupply;
    uint initialSupply;
    address public tokenOwner;
    address public factory;
    mapping (address => bool) public farmManagers;

    constructor (
        address _tokenOwner,
        address _factory,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint _initialSupply,
        uint _initialOwnerShare,
        bool _initialSupplyIsMaxSupply
    ) ERC20(_tokenName, _tokenSymbol) {
        // Set tokenOwner and factory address
        tokenOwner = _tokenOwner;
        factory = _factory;

        // Check if the owner does not want to much of the initial supply
        require(_initialOwnerShare <= 20, 'The owner is not allowed to keep more then 20% of the initial supply');
        
        // Calculate the share of tokens for the owner of the token, mint them and send the tokens to his address
        uint sharesForOwner = _initialSupply.div(100).mul(_initialOwnerShare);
        _mint(msg.sender, sharesForOwner);

        initialSupply = _initialSupply;

        // Set a boolean if the initial supply if the max supply
        // If this is not the case, the owner can issue new tokens through a farm
        initialSupplyIsMaxSupply = _initialSupplyIsMaxSupply;
        farmManagers[tokenOwner] = true;
    }

    // Function to create a farm, farms can only be created by the Token As A Service contract
    function createFarm(
        address _stakingToken, 
        uint _rewardsDurationInDays,
        uint _totalRwards
    ) public {
        require(farmManagers[msg.sender] == true, 'Only farm managers are allowed to do this');
        if (initialSupplyIsMaxSupply) {
            uint currantSupply = totalSupply();
            uint currentAfterRewards = currantSupply.add(_totalRwards);
            require(currentAfterRewards <= initialSupply, 'You want to add to much rewards, your share plus the rewards are more then the max supply!');
        }

        // Mint the tokens before creating the farm and send them to the token contract address
        // The token contract will create the farm and the funds will be send from this contract to the farm
        _mint(address(this), _totalRwards);

        ITokenLaunchPad(factory).createNewFarm(
                tokenOwner,
                address(this),
                _stakingToken,
                _rewardsDurationInDays,
                18,
                _totalRwards
        );
    }

    // Add rewards to one of the farms for this token. You can only add rewards from this contract.
    function addRewardsToFarm(
        address _tokenFarm,
        uint _extraRewards,
        bool _increaseRewardRate
    ) public {
        require(farmManagers[msg.sender] == true, 'Only farm managers are allowed to do this');

        // First check if we dont add to much token in case there is a max supply for the token
        if (initialSupplyIsMaxSupply) {
            uint currantSupply = totalSupply();
            uint currentAfterRewards = currantSupply.add(_extraRewards);
            require(currentAfterRewards <= initialSupply, 'You want to add to much rewards, your share plus the rewards are more then the max supply!');
        }

        // Mint the tokens and increase the rewards
        _mint(address(this), _extraRewards);

        if (_increaseRewardRate) {
            ITokenLaunchPad(factory).addRewardsWithoutAddingDuration(_tokenFarm, _extraRewards);
        } else {
            ITokenLaunchPad(factory).addRewardsAndDuration(_tokenFarm, _extraRewards);
        }

    }

    // CHange the token owner
    function setTokenOwner(address _owner) public {
        require(msg.sender == tokenOwner, "!Only the owner can do this");
        tokenOwner = _owner;
    }

    // Add farm managers
    function addFarmManager(address _manager) public {
        require(msg.sender == tokenOwner, "!Only the owner can add farm manager");
        farmManagers[_manager] = true;
    }

    // Remove farm managers
    function removeMinter(address _manager) public {
        require(msg.sender == tokenOwner, "!Only the owner can remove farm managers");
        farmManagers[_manager] = false;
    }
}