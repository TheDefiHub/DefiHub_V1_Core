// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import './DefihubConstants.sol';

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import '@openzeppelin/contracts/utils/Address.sol';

contract FarmAsAServiceV1 is ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    using Address for address;



    /*********************************
        Contract State variables 
    *********************************/

    address farmFactory;
    address farmAdmin;

    IERC20 public rewardsToken;
    IERC20 public stakingToken;
    uint public rawardsTokenDecimals;
    uint public farmingEndDate = 0;
    uint public rewardRate = 0;
    uint public rewardsDuration = 0;
    uint public lastUpdateTime = 0;
    uint public totalRewards = 0;
    uint public totalRewardsWithdrawn = 0;
    uint public rewardPerTokenStored;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;
    address[] public farmers;

    uint private _totalSupply;
    mapping(address => uint) private _balances;



    /***********************
            Modifiers 
    ***********************/

    modifier onlyFactory() {
        require(msg.sender == farmFactory, 'Only the farm factory is allowed to do this!');
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }



    /***********************
           Constructor 
    ***********************/

    constructor(
        address _farmFactory,
        address _farmAdmin,
        address _rewardsToken,
        address _stakingToken,
        uint _rewardsDurationInDays,
        uint _rawardsTokenDecimals,
        uint _RewardsAmount
    ) {
        // Set token
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);

        // Set farm factory and admin
        farmFactory = _farmFactory;
        farmAdmin = _farmAdmin;

        // Set farm duration
        rewardsDuration = _rewardsDurationInDays.mul(DefihubConstants.DAY_MULTIPLIER);
        farmingEndDate = block.timestamp.add(rewardsDuration);
        rawardsTokenDecimals = 10**_rawardsTokenDecimals;
        modifyRewardAmount(_RewardsAmount);
    }



    /**************************
           view returns 
    **************************/

    function totalSupply() external view returns (uint) {
        return _totalSupply;
    }

    function totalRewardsLeft() external view returns (uint) {
        return rewardsToken.balanceOf(address(this));
    }

    function balanceOf(address account) external view returns (uint) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, farmingEndDate);
    }

    function rewardPerToken() public view returns (uint) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(rawardsTokenDecimals).div(_totalSupply)
        );
    }

    function earned(address account) public view returns (uint) {
        uint calculatedEarned = _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(rawardsTokenDecimals).add(rewards[account]);

        // some rare case the reward can be slightly bigger than real number, we need to check against how much we have left in pool
        uint poolBalance = rewardsToken.balanceOf(address(this));
        return (calculatedEarned < poolBalance) ? calculatedEarned : poolBalance;
    }



    /**************************
             Functions 
    **************************/

    function stake(uint amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");

        uint fee = amount.mul(DefihubConstants.FAAS_ENTRANCE_FEE_BP).div(DefihubConstants.BASE_POINTS);
        uint stakingAmount = amount.sub(fee);

        _totalSupply = _totalSupply.add(stakingAmount);
        _balances[msg.sender] = _balances[msg.sender].add(stakingAmount);
        farmers.push(msg.sender);

        stakingToken.safeTransferFrom(msg.sender, address(this), stakingAmount);
        stakingToken.safeTransferFrom(msg.sender, DefihubConstants.FEE_ADDRESS, fee);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(_balances[msg.sender] >= amount, "You want to withdraw more then you own");

        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.safeTransfer(msg.sender, amount);
        totalRewardsWithdrawn = totalRewardsWithdrawn.add(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }



    /**************************
       Only factory functions 
    **************************/


    function modifyRewardAmount(uint reward) public onlyFactory updateReward(address(0)) {
        require(block.timestamp <= farmingEndDate, 'The farm has already ended, you cannot add new rewards!');
        require(rewardsToken.balanceOf(farmAdmin) >= reward, 'You dont have enough tokens to add!');
        
        // When we initially add the rewards we calculate the reward rate
        if (rewardRate == 0) {
            rewardRate = reward.div(rewardsDuration);
        } 
        
        // In case there are extra rewards added we adjust the duration of the farm, we dont increase the rewardRate
        // Increasing the rewardRate would mean adjusting all farmers rewards and this could become very expensive
        // This also keeps the emission stable and by doing so not creating more selling pressure on the topen price
        if (reward != 0) {
            uint durationToAdd = rewardsDuration.div(totalRewards.div(reward));
            rewardsDuration = rewardsDuration.add(durationToAdd);
        }

        // Transfer the rewards to the contract
        rewardsToken.safeTransferFrom(farmAdmin, address(this), reward);


        // Ensure the provided reward amount is not more than the balance in the contract + the withdrawn amount.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint amountForPayouts = rewardsToken.balanceOf(address(this)).add(totalRewardsWithdrawn);
        require(rewardRate <= amountForPayouts.div(rewardsDuration), "Provided reward too high this will create overflow");

        // The first time we add rewards we want to set lastUpdateTime so rewards per token will be zero untill someone stakes
        lastUpdateTime = block.timestamp;
        totalRewards = totalRewards.add(reward);
    }



    /**************************
             Events 
    **************************/
    event Staked(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
    event RewardPaid(address indexed user, uint reward);
}