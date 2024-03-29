// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


contract StakingContract is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    
    IERC20 public token; // Token being staked

    // Hardcoded staking periods and APRs
    uint256 public constant THREE_MONTHS = 3 * 30 days;
    uint256 public constant SIX_MONTHS = 6 * 30 days;
    uint256 public constant TWELVE_MONTHS = 12 * 30 days;

    mapping(uint256 => uint256) public periodRates;

	// Struct representing staker data
    struct Staker {
        uint256 amount;
        uint256 stakeTime;
        uint256 reward;
        uint256 burnAmount;
        uint256 burnRate;
        uint256 stakePeriod;
        uint256 lastRewardCalculation;
        uint256 totalRewardAllocation;
        uint256 initialRewardAllocation;
    }

	// Map to keep track of stakers
    mapping(address => Staker) public stakers;

	// State variables to keep track of the total amount staked, burned, allocated and pool
    uint256 public totalStaked;
    uint256 public totalAllocated; //how many token are allocated for rewards
    uint256 public totalBurned;
    uint256 public stakingPool; //@audit FST-07 stakingPool keep count of the total amount of token in the staking pool that are not allocated and can be used for rewards

    // New mapping to store the last emergencyUnstake time for each user
    mapping(address => uint256) public lastEmergencyUnstakeTime;

    // Cooldown period after emergencyUnstake
    uint256 public cooldown = 1 days;

	uint256 public emergencyWithdrawalPenalty = 25;
    uint256 public burnRateEmergency = 40;

	// Events
    event Staked(address indexed user, uint256 amount, uint256 reward, uint256 burnAmount);
    event Unstaked(address indexed user, uint256 amount);
    event EmergencyUnstaked(address indexed user, uint256 amount);
    event Burned(uint256 amount);
	
	// Constructor that sets the token to be staked and rates
    constructor(IERC20 _token) {
        token = _token;
        periodRates[THREE_MONTHS] = 5;
        periodRates[SIX_MONTHS] = 15;
        periodRates[TWELVE_MONTHS] = 40;
    }

	// Add funds to the staking pool
    function addToStakingPool(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Amount must be greater than zero");
        uint256 balanceBefore = token.balanceOf(address(this));
        token.transferFrom(msg.sender, address(this), _amount);
        uint256 received = token.balanceOf(address(this)).sub(balanceBefore);
        assert(received == _amount);
        stakingPool += _amount; //@audit FST-07 add the fund to the staking pool
    }

    function stake(uint256 _amount, uint256 _burnRate, uint256 _stakePeriod) external nonReentrant {
        require(stakers[msg.sender].amount == 0, "Already staking, you can stake more only after current period ends");
        require(_burnRate == 25 || _burnRate == 50 || _burnRate == 75, "Invalid burn rate");
        require(periodRates[_stakePeriod] > 0, "Invalid staking period");
        
        uint256 totalRate = periodRates[_stakePeriod];
        uint256 totalRewardAllocation = _amount.mul(totalRate).div(100);

        require(stakingPool >= totalRewardAllocation, "Staking pool has not enough funds");
        token.transferFrom(msg.sender, address(this), _amount);

        uint256 burnAmount = totalRewardAllocation.mul(_burnRate).div(100);
        

        // Burn the burn amount immediately upon staking
        if (burnAmount > 0) {
            burn(burnAmount);
            emit Burned(burnAmount);
        }
        stakers[msg.sender].amount = _amount;
        stakers[msg.sender].stakeTime = block.timestamp;
        stakers[msg.sender].burnRate = _burnRate;
        stakers[msg.sender].stakePeriod = _stakePeriod;
        stakers[msg.sender].burnAmount = burnAmount;
        stakers[msg.sender].totalRewardAllocation = totalRewardAllocation.sub(burnAmount); // Update only the totalRewardAllocation
        stakers[msg.sender].initialRewardAllocation = totalRewardAllocation.sub(burnAmount);
        stakers[msg.sender].lastRewardCalculation = block.timestamp;

        totalStaked = totalStaked.add(_amount);
        totalAllocated += stakers[msg.sender].totalRewardAllocation;
        stakingPool -= totalRewardAllocation; //@audit FST-07 remove the allocated amount (w the burn amount since those token are not here anymore) from the staking pool amount
        
        emit Staked(msg.sender, _amount, stakers[msg.sender].totalRewardAllocation, stakers[msg.sender].burnAmount);
    }

    function calculateReward(address _staker) internal {
        uint256 timeElapsed;
        uint256 rewardPerSecond = stakers[_staker].initialRewardAllocation.div(stakers[_staker].stakePeriod);
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
        }

    function withdrawReward() external nonReentrant {
        require(stakers[msg.sender].amount > 0, "You are not staking");
        
        // Calculate and update the reward for the staker
        calculateReward(msg.sender);
        
        uint256 reward = stakers[msg.sender].reward;

        // Update the totalAllocated before setting the staker's reward to zero
        totalAllocated = totalAllocated.sub(reward);

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
        /* @audit FST-07 reward will be the totalRewardAllocation, that we already substracted to stackingPool in the stake function,
         since all will go to the user no need to substract it again since they are no more in the contract */

        // Update totalStaked and totalAllocated before resetting the staker's data
        totalStaked = totalStaked.sub(amount);
        totalAllocated = totalAllocated.sub(stakers[msg.sender].totalRewardAllocation);
        

        stakers[msg.sender].amount = 0;
        stakers[msg.sender].stakeTime = 0;
        stakers[msg.sender].reward = 0;
        stakers[msg.sender].burnAmount = 0;
        stakers[msg.sender].totalRewardAllocation = 0;
        stakers[msg.sender].initialRewardAllocation = 0;
        stakers[msg.sender].burnRate = 0;
        stakers[msg.sender].stakePeriod = 0;

        token.transfer(msg.sender, amount.add(reward));
        
        emit Unstaked(msg.sender, amount);
    }

    function emergencyUnstake() external nonReentrant {
        // Ensure that enough time has passed since the last emergency unstake
        require(block.timestamp > lastEmergencyUnstakeTime[msg.sender] + cooldown, "Cooldown period has not passed");
        require(stakers[msg.sender].amount > 0, "You don't have any staked amount");

        calculateReward(msg.sender); 
        uint256 uncollectedReward = stakers[msg.sender].reward; 
        uint256 total = stakers[msg.sender].amount.add(uncollectedReward); 

        uint256 penalty = total.mul(emergencyWithdrawalPenalty).div(100); 
        uint256 burnAmount = penalty.mul(burnRateEmergency).div(100); 
        uint256 poolAmount = penalty.sub(burnAmount);
        uint256 rewardLeftOver = stakers[msg.sender].totalRewardAllocation - uncollectedReward; 
        
        stakingPool +=  (poolAmount + rewardLeftOver); /* @audit FST-07 add the pool fee part and the leftOver reward back to the staking pool,
                                                                no need to remove anything since totalRewardAllocation was subtracted in stack() so we will add back just the difference */
            
        // Transfer the remaining amount after penalty to the user
        token.transfer(msg.sender, total.sub(penalty));

        // Burn the burn amount immediately from the staking pool
        if (burnAmount > 0) {
            burn(burnAmount);
            emit Burned(burnAmount);
        }

        // Update total staked and total allocated
        totalStaked = totalStaked.sub(stakers[msg.sender].amount);
        totalAllocated -= rewardLeftOver;

        // Reset staker's information
        stakers[msg.sender].amount = 0;
        stakers[msg.sender].stakeTime = 0;
        stakers[msg.sender].reward = 0;
        stakers[msg.sender].burnAmount = 0;
        stakers[msg.sender].totalRewardAllocation = 0;
        stakers[msg.sender].initialRewardAllocation = 0;
        stakers[msg.sender].burnRate = 0;
        stakers[msg.sender].stakePeriod = 0;

        // Update the last emergency unstake time
        lastEmergencyUnstakeTime[msg.sender] = block.timestamp;
    
        
        // Emit Unstaked event
        emit EmergencyUnstaked(msg.sender, total);
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
        uint256 timeElapsed;
        uint256 rewardPerSecond = stakers[_staker].initialRewardAllocation.div(stakers[_staker].stakePeriod);
        
        // Check if the current time has surpassed the staking period.
        if (block.timestamp > stakers[_staker].stakeTime.add(stakers[_staker].stakePeriod)) {
            // If so, use the staking period end time for the final reward calculation.
            timeElapsed = (stakers[_staker].stakeTime.add(stakers[_staker].stakePeriod)).sub(stakers[_staker].lastRewardCalculation);
        } else {
            // If not, calculate the time elapsed since the last reward calculation.
            timeElapsed = block.timestamp.sub(stakers[_staker].lastRewardCalculation);
        }
        
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