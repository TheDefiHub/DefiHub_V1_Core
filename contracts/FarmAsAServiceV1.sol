// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import './DefihubConstants.sol';
import './IFarmAsAServiceV1.sol';

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import '@openzeppelin/contracts/utils/Address.sol';

contract FarmAsAServiceV1 is ReentrancyGuard, IFarmAsAServiceV1 {
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
    uint public rewardPerTokenStored;

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    uint private _totalSupply;
    mapping(address => uint) private _balances;



    /***********************
            Modifiers 
    ***********************/

    modifier onlyFactory() {
        require(msg.sender == farmFactory, 'Only the farm factory is allowed to do this!');
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == farmAdmin, 'Only the farm admin is allowed to do this!');
        _;
    }

    modifier farmIsActive() {
        require(block.timestamp <= farmingEndDate, 'The farm has already ended, you cannot add new rewards!');
        _;
    }

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
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
        increaseRewardsAndFarmDuration(_RewardsAmount);
    }



    /**************************
           view returns 
    **************************/
    // Returns the total supply added to the farm
    function totalSupply() external view returns (uint) {
        return _totalSupply;
    }

    // Rewards left in the contract 
    function totalRewardsLeft() external view returns (uint) {
        return rewardsToken.balanceOf(address(this));
    }

    // Staked balnce of an address
    function balanceOf(address account) external view returns (uint) {
        return _balances[account];
    }

    // Returns the smallers number : current timestamp vs. farmEndDate
    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, farmingEndDate);
    }

    // Returns the reward per token stored
    function rewardPerToken() public view returns (uint) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(rawardsTokenDecimals).div(_totalSupply)
        );
    }

    // Returns the rewards earned for an address
    function earned(address _account) public view returns (uint) {
        uint calculatedEarned = _balances[_account].mul(rewardPerToken().sub(userRewardPerTokenPaid[_account])).div(rawardsTokenDecimals).add(rewards[_account]);

        // some rare case the reward can be slightly bigger than real number, we need to check against how much we have left in pool
        uint poolBalance = rewardsToken.balanceOf(address(this));
        return (calculatedEarned < poolBalance) ? calculatedEarned : poolBalance;
    }



    /**************************
             Functions 
    **************************/
    
    // Stake your tokens and start farming
    function stake(uint _amount) external farmIsActive nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Cannot stake 0");

        // Calculate the fee and the amount to stake
        uint fee = _amount.mul(DefihubConstants.FAAS_ENTRANCE_FEE_BP).div(DefihubConstants.BASE_POINTS);
        uint stakingAmount = _amount.sub(fee);

        // Add staking amount to the balance and total supply 
        _totalSupply = _totalSupply.add(stakingAmount);
        _balances[msg.sender] = _balances[msg.sender].add(stakingAmount);

        // Transfer the staking amount to the contract and the fee to the fee address
        stakingToken.safeTransferFrom(msg.sender, address(this), stakingAmount);
        stakingToken.safeTransferFrom(msg.sender, DefihubConstants.FEE_ADDRESS, fee);
        emit Staked(msg.sender, _amount);
    }

    // Withdraw your tokens from the farm and claimRewards
    function withdraw(uint _amount) public nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Cannot withdraw 0");
        require(_balances[msg.sender] >= _amount, "You want to withdraw more then you own");

        // Remove the amount from the total supply and address balance
        _totalSupply = _totalSupply.sub(_amount);
        _balances[msg.sender] = _balances[msg.sender].sub(_amount);

        // Transfer the tokens back to the address
        stakingToken.safeTransfer(msg.sender, _amount);
        claimRewards();
        emit Withdrawn(msg.sender, _amount);
    }

    // Claim rewards
    function claimRewards() public nonReentrant updateReward(msg.sender) {
        // Get the rewards ready to claim
        uint reward = rewards[msg.sender];

        // If there are rewards to claim
        if (reward > 0) {
            // Set user rewards to 0 and transfer the claimable rewards
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);

            emit RewardPaid(msg.sender, reward);
        }
    }


    /**************************
       Only factory functions 
    **************************/

    // Increase the farm rewards and reset the farm duration
    function increaseRewardsAndFarmDuration(uint _reward) public override farmIsActive onlyFactory updateReward(address(0)) {
        require(rewardsToken.balanceOf(farmAdmin) >= _reward, 'You dont have enough tokens to add!');
        
        if (rewardRate == 0) {
            rewardRate = _reward.div(rewardsDuration);
        } else {
            uint remaining = farmingEndDate.sub(block.timestamp);
            uint leftover = remaining.mul(rewardRate);
            rewardRate = _reward.add(leftover).div(rewardsDuration);
        }

        // Transfer the rewards to the contract
        rewardsToken.safeTransferFrom(farmAdmin, address(this), _reward);


        // Ensure the provided reward amount is not more than the balance in the contract + the withdrawn amount.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        require(rewardRate <= rewardsToken.balanceOf(address(this)).div(rewardsDuration), "Provided reward too high this will create overflow");

        // Set last update time and reset farmingEndDate
        lastUpdateTime = block.timestamp;
        farmingEndDate = block.timestamp.add(rewardsDuration);
    }

    // Increase the farm rewards but leave the duration as is
    function increaseRewards(uint _reward) public override farmIsActive onlyFactory updateReward(address(0)) {
        require(rewardsToken.balanceOf(farmAdmin) >= _reward, 'You dont have enough tokens to add!');
        require(rewardRate != 0, 'First add rewards before increasing the emission rate by adding more rewards!');
        
        uint remainingRewardDuration = farmingEndDate.sub(block.timestamp);
        uint leftover = remainingRewardDuration.mul(rewardRate);
        rewardRate = _reward.add(leftover).div(remainingRewardDuration);

        // Transfer the rewards to the contract
        rewardsToken.safeTransferFrom(farmAdmin, address(this), _reward);


        // Ensure the provided reward amount is not more than the balance in the contract + the withdrawn amount.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        require(rewardRate <= rewardsToken.balanceOf(address(this)).div(remainingRewardDuration), "Provided reward too high this will create overflow");

        lastUpdateTime = block.timestamp;
    }



    /**************************
       Only factory functions 
    **************************/

    // In some cases a farm can have an X amount of time with no farmers while the farm is active
    // If this is the case there will be left over rewards the admin can claim back
    // There can also be small left overs due to rondings in the calculations
    function withdrawLeftovers() public onlyAdmin {
        require(block.timestamp > farmingEndDate, 'The farm needs to have ended before you can take out leftovers!');
        require(_totalSupply == 0, 'All funds need to be withdrawn before you can claim leftovers!');
        uint amountLeft = rewardsToken.balanceOf(address(this));
        if (amountLeft > 0) {
            rewardsToken.safeTransfer(farmAdmin, amountLeft);
            emit RewardPaid(farmAdmin, amountLeft);
        }

    }


    /**************************
             Events 
    **************************/
    event Staked(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
    event RewardPaid(address indexed user, uint reward);
}