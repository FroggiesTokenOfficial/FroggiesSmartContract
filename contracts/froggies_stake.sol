// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract StakingContract is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    
    IERC20 public token; // Token being staked

	// Struct representing staker data
    struct Staker {
        uint256 amount;
        uint256 stakeTime;
        uint256 reward;
        uint256 burnAmount;
        uint256 rewardRate;
        uint256 burnRate;
        uint256 stakePeriod;
        uint256 lastRewardCalculation;
        uint256 totalRewardAllocation;
    }

	// Map to keep track of stakers
    mapping(address => Staker) public stakers;

	// State variables to keep track of the total amount staked, burned, allocated and pool
    uint256 public totalStaked;
    uint256 public totalAllocated;
    uint256 public totalBurned;
    uint256 public stakingPool;

	// Map to keep track of the reward rates based on staking period
    mapping(uint256 => uint256) public periodRates;

    // New mapping to store the last emergencyUnstake time for each user
    mapping(address => uint256) public lastEmergencyUnstakeTime;

    // Cooldown period after emergencyUnstake
    uint256 public cooldown = 1 days;

	// Variables to define the penalty, burn rate and pool rate in case of emergency unstake
    uint256 public emergencyWithdrawalPenalty = 25;
    uint256 public burnRateEmergency = 40;
    uint256 public poolRateEmergency = 60;

	// Events
    event Staked(address indexed user, uint256 amount, uint256 reward, uint256 burnAmount);
    event Unstaked(address indexed user, uint256 amount);
    event EmergencyUnstaked(address indexed user, uint256 amount);
    event Burned(uint256 amount);
    event EmergencyRatesUpdated(uint256 penalty, uint256 burnRate, uint256 poolRate);
	
	// Constructor that sets the token to be staked
    constructor(IERC20 _token) {
        token = _token;
    }
	
	// Set the reward rate for a specific period - can set multiple periods and rates
	function setPeriodRates(uint256 _period, uint256 _rate) external onlyOwner {
        periodRates[_period] = _rate;
    }

	// Add funds to the staking pool
    function addToStakingPool(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Amount must be greater than zero");
        uint256 balanceBefore = token.balanceOf(address(this));
        token.transferFrom(msg.sender, address(this), _amount);
        uint256 received = token.balanceOf(address(this)).sub(balanceBefore);
        assert(received == _amount);
        stakingPool = stakingPool.add(_amount);
    }

    function stake(uint256 _amount, uint256 _rewardRate, uint256 _burnRate, uint256 _stakePeriod) external nonReentrant {
        require(stakers[msg.sender].amount == 0, "Already staking, you can stake more only after current period ends");
        require(_rewardRate.add(_burnRate) <= 100, "The total of reward and burn rates must be less than or equal to 100");
        require(periodRates[_stakePeriod] > 0, "Invalid staking period");
        
        uint256 totalRate = periodRates[_stakePeriod];
        uint256 totalAllocation = _amount.mul(totalRate).div(100);

        require(stakingPool >= totalAllocation, "Staking pool has not enough funds");

        token.transferFrom(msg.sender, address(this), _amount);

        uint256 burnAmount = totalAllocation.mul(_burnRate).div(100);

        stakers[msg.sender].amount = _amount;
        stakers[msg.sender].stakeTime = block.timestamp;
        stakers[msg.sender].rewardRate = _rewardRate;
        stakers[msg.sender].burnRate = _burnRate;
        stakers[msg.sender].stakePeriod = _stakePeriod;
        stakers[msg.sender].burnAmount = burnAmount;
        stakers[msg.sender].totalRewardAllocation = totalAllocation.sub(burnAmount); // Update only the totalRewardAllocation
        stakers[msg.sender].lastRewardCalculation = block.timestamp;

        totalStaked = totalStaked.add(_amount);
        totalAllocated = totalAllocated.add(stakers[msg.sender].totalRewardAllocation);
        totalBurned = totalBurned.add(burnAmount);
        stakingPool = stakingPool.sub(totalAllocation);

        emit Staked(msg.sender, _amount, stakers[msg.sender].totalRewardAllocation, stakers[msg.sender].burnAmount);
    }

    function calculateReward(address _staker) internal {
        uint256 timeElapsed;
        uint256 rewardPerSecond = stakers[_staker].totalRewardAllocation.div(stakers[_staker].stakePeriod);
        uint256 newReward;

        // Check if the current time has surpassed the staking period.
        if (block.timestamp > stakers[_staker].stakeTime.add(stakers[_staker].stakePeriod)) {
            // If so, use the staking period end time for the final reward calculation.
            timeElapsed = (stakers[_staker].stakeTime.add(stakers[_staker].stakePeriod)).sub(stakers[_staker].lastRewardCalculation);
        } else {
            // If not, calculate the time elapsed since the last reward calculation.
            timeElapsed = block.timestamp.sub(stakers[_staker].lastRewardCalculation);
        }

        newReward = rewardPerSecond.mul(timeElapsed);
        stakers[_staker].reward = stakers[_staker].reward.add(newReward);
        stakers[_staker].lastRewardCalculation = block.timestamp;
        totalAllocated = totalAllocated.add(newReward);
    }

    function withdrawReward() external nonReentrant {
        require(stakers[msg.sender].amount > 0, "You are not staking");
        
        // Calculate and update the reward for the staker
        calculateReward(msg.sender);
        
        uint256 reward = stakers[msg.sender].reward;
        
        // Update the staker's reward and total reward allocation
        stakers[msg.sender].reward = 0;
        stakers[msg.sender].totalRewardAllocation = stakers[msg.sender].totalRewardAllocation.sub(reward);
        
        // Transfer the reward tokens to the staker
        token.transfer(msg.sender, reward);
    }

    function unstake() external nonReentrant {
        require(stakers[msg.sender].amount > 0, "You are not staking");
        require(block.timestamp >= stakers[msg.sender].stakeTime.add(stakers[msg.sender].stakePeriod), "Staking period has not ended");

        calculateReward(msg.sender);

        uint256 amount = stakers[msg.sender].amount;
        uint256 reward = stakers[msg.sender].reward;
        uint256 burnAmount = stakers[msg.sender].burnAmount;

        stakers[msg.sender].amount = 0;
        stakers[msg.sender].stakeTime = 0;
        stakers[msg.sender].reward = 0;
        stakers[msg.sender].burnAmount = 0;
        stakers[msg.sender].totalRewardAllocation = 0;

        totalStaked = totalStaked.sub(amount);
        totalAllocated = totalAllocated.sub(reward); // Update only the reward amount
        totalBurned = totalBurned.add(burnAmount);

        burn(burnAmount);
        token.transfer(msg.sender, amount.add(reward));

        emit Unstaked(msg.sender, amount);
        emit Burned(burnAmount);
    }

    function emergencyUnstake() external nonReentrant {
        // Ensure that enough time has passed since the last emergency unstake
        require(block.timestamp > lastEmergencyUnstakeTime[msg.sender] + cooldown, "Cooldown period has not passed");
        require(stakers[msg.sender].amount > 0, "You don't have any staked amount");

        calculateReward(msg.sender);
        uint256 uncollectedReward = stakers[msg.sender].totalRewardAllocation.sub(stakers[msg.sender].reward);

        uint256 total = stakers[msg.sender].amount.add(uncollectedReward);
        uint256 penalty = total.mul(emergencyWithdrawalPenalty).div(100);
        uint256 burnAmount = penalty.mul(burnRateEmergency).div(100);
        burnAmount = burnAmount.add(stakers[msg.sender].burnAmount);
        uint256 poolAmount = penalty.sub(burnAmount);

        // Transfer the remaining amount after penalty to the user
        token.transfer(msg.sender, total.sub(penalty));

        // Burn the burn amount immediately from the staking pool
        if (burnAmount > 0) {
            burn(burnAmount);
            emit Burned(burnAmount);
        }

        // Add the pool amount back to the staking pool
        stakingPool = stakingPool.add(poolAmount);

        // Update total staked and total allocated
        totalStaked = totalStaked.sub(stakers[msg.sender].amount);
        totalAllocated = totalAllocated.sub(uncollectedReward).add(poolAmount);

        // Reset staker's information
        stakers[msg.sender].amount = 0;
        stakers[msg.sender].stakeTime = 0;
        stakers[msg.sender].reward = 0;
        stakers[msg.sender].burnAmount = 0;
        stakers[msg.sender].totalRewardAllocation = 0;

        // Update the last emergency unstake time
        lastEmergencyUnstakeTime[msg.sender] = block.timestamp;

        // Emit Unstaked event
        emit EmergencyUnstaked(msg.sender, total);
    }

    // Function for the owner to set the rates
    function setEmergencyWithdrawalRates(uint256 _penalty, uint256 _burnRate, uint256 _poolRate) external onlyOwner {
        require(_penalty <= 25, "Penalty should not be more than 25%");
        require(_burnRate.add(_poolRate) == 100, "Sum of burn and pool rates should be equal to 100");
        emergencyWithdrawalPenalty = _penalty;
        burnRateEmergency = _burnRate;
        poolRateEmergency = _poolRate;
        emit EmergencyRatesUpdated(_penalty, _burnRate, _poolRate);
    }

    function burn(uint256 amount) private {
        // The `publicBurn` function must take one `uint256` argument, which is the 
        // amount to burn, and return a `bool` value, indicating the success or failure of the operation
        (bool success, ) = address(token).call(abi.encodeWithSignature("publicBurn(uint256)", amount));
        require(success, "Burn failed");
        totalBurned = totalBurned.add(amount);
    }

	// Get the accumulated reward of a staker based on the time elapsed
    function getAccumulatedReward(address _staker) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp.sub(stakers[_staker].lastRewardCalculation);
        uint256 rewardPerSecond = stakers[_staker].totalRewardAllocation.div(stakers[_staker].stakePeriod);
        uint256 accumulatedReward = rewardPerSecond.mul(timeElapsed);
        return accumulatedReward.add(stakers[_staker].reward);
    }

    // Get the staking details of a specific user (Returns a tuple)
    function getStakeDetails(address _staker) public view returns(uint256 stakedAmount, uint256 burnedAmount, uint256 currentReward, uint256 totalRewardAllocation, uint256 stakeTime) {
        uint256 accumulatedReward = getAccumulatedReward(_staker);
        return (stakers[_staker].amount, stakers[_staker].burnAmount, accumulatedReward, stakers[_staker].totalRewardAllocation, stakers[_staker].stakeTime);
    }

    // Check the remaining balance of the staking pool
    function getRemainingStakePool() public view returns(uint256) {
        return stakingPool;
    }

    // Check total burned amount by all
    function getTotalBurned() public view returns(uint256) {
        return totalBurned;
    }
}