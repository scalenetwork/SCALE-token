pragma solidity ^0.4.24;

/**************************************************************
 * @title Scale Token Contract
 * @file Scale.sol
 * @author Jared Downing and Kane Thomas of the Scale Network
 * @version 1.0
 *
 * @section DESCRIPTION
 *
 * This is an ERC20-based token with staking and inflationary functionality.
 *
 *************************************************************/

//////////////////////////////////
/// OpenZeppelin library imports
//////////////////////////////////

import "../openzeppelin-solidity/contracts/token/ERC20/MintableToken.sol";
import "../openzeppelin-solidity/contracts/ownership/HasNoEther.sol";

//////////////////////////////////
/// Scale Token
//////////////////////////////////

contract Scale is MintableToken, HasNoEther {

    // Libraries
    using SafeMath for uint;

    //////////////////////
    // Token Information
    //////////////////////
    string public constant name = "SCALE";
    string public constant symbol = "SCALE";
    uint8 public constant  decimals = 18;

    ///////////////////////////////////////////////////////////
    // Variables For Staking and Pooling
    ///////////////////////////////////////////////////////////

    // -- Pool Minting Rates and Percentages -- //
    // Pool for Scale distribution to rewards pool
    // Set to 0 to prohibit issuing to the pool before it is assigned
    address public pool = address(0);

    // Pool and Owner minted tokens per second
    uint public poolMintRate;
    uint public ownerMintRate;

    // Amount of Scale to be staked to the pool, staking, and mint, as calculated through their percentages
    uint public poolMintAmount;
    uint public stakingMintAmount;
    uint public ownerMintAmount;

    // Scale distribution percentages
    uint public poolPercentage = 70;
    uint public ownerPercentage = 5;
    uint public stakingPercentage = 25;

    // Last time minted for owner and pool
    uint public ownerTimeLastMinted;
    uint public poolTimeLastMinted;

    // -- Staking -- //
    // Minted tokens per second
    uint public stakingMintRate;

    // Total Scale currently staked
    uint public totalScaleStaked;

    // Mapping of the timestamp => totalStaking that is created each time an address stakes or unstakes
    mapping (uint => uint) totalStakingHistory;

    // Variable for staking accuracy. Set to 86400 for seconds in a day so that staking gains are based on the day an account begins staking.
    uint timingVariable = 86400;

    // Address staking information
    struct AddressStakeData {
        uint stakeBalance;
        uint initialStakeTime;
    }

    // Track all tokens staked
    mapping (address => AddressStakeData) public stakeBalances;

    // -- Inflation -- //
    // Inflation rate begins at 100% per year and decreases by 15% per year until it reaches 10% where it decreases by 0.5% per year
    uint256 inflationRate = 1000;

    // Used to manage when to inflate. Allowed to inflate once per year until the rate reaches 1%.
    uint256 public lastInflationUpdate;

    // -- Events -- //
    // Fired when tokens are staked
    event Stake(address indexed staker, uint256 value);
    // Fired when tokens are unstaked
    event Unstake(address indexed unstaker, uint256 stakedAmount, uint256 stakingGains);

    //////////////////////////////////////////////////
    /// Scale Token Functionality
    //////////////////////////////////////////////////

    /** 
     * @dev Scale token constructor
     */
    constructor() public {
        // Assign owner
        owner = msg.sender;

        // Assign initial owner supply
        uint _initOwnerSupply = 10000000 ether;
        // Mint given to owner only one-time
        bool _success = mint(msg.sender, _initOwnerSupply);
        // Require minting success
        require(_success);

        // Set pool and owner last minted to ensure extra coins are not minted by either
        ownerTimeLastMinted = now;
        poolTimeLastMinted = now;

        // Set minting amount for pool, staking, and owner over the course of 1 year
        poolMintAmount = _initOwnerSupply.mul(poolPercentage).div(100);
        ownerMintAmount = _initOwnerSupply.mul(ownerPercentage).div(100);
        stakingMintAmount = _initOwnerSupply.mul(stakingPercentage).div(100);

        // One year in seconds
        uint _oneYearInSeconds = 31536000 ether;

        // Set the rate of coins minted per second for the pool, owner, and global staking
        poolMintRate = calculateFraction(poolMintAmount, _oneYearInSeconds, decimals);
        ownerMintRate = calculateFraction(ownerMintAmount, _oneYearInSeconds, decimals);
        stakingMintRate = calculateFraction(stakingMintAmount, _oneYearInSeconds, decimals);

        // Set the last time inflation was update to now so that the next time it can be updated is 1 year from now
        lastInflationUpdate = now;
    }

    /////////////
    // Inflation
    /////////////
    /** 
     * @dev the inflation rate begins at 100% and decreases by 15% every year until it reaches 10%
     * at 10% the rate begins to decrease by 0.5% until it reaches 1%
     */
    function adjustInflationRate() private {


      // Make sure adjustInflationRate cannot be called for at least another year
      lastInflationUpdate = now;

      // Decrease inflation rate by 15% each year
      if (inflationRate > 100) {

        inflationRate = inflationRate.sub(300);
      }
      // Inflation rate reaches 10%. Decrease inflation rate by 0.5% from here on out until it reaches 1%.
      else if (inflationRate > 10) {

        inflationRate = inflationRate.sub(5);
      }

      // Calculate new mint amount of Scale that should be created per year.
      // Example Inflation Past Year 1 for the poolMintAmount: 16M * 0.85 * 0.7 = 9,520,000
      poolMintAmount = totalSupply.mul(inflationRate).div(1000).mul(poolPercentage).div(100);
      ownerMintAmount = totalSupply.mul(inflationRate).div(1000).mul(ownerPercentage).div(100);
      stakingMintAmount = totalSupply.mul(inflationRate).div(1000).mul(stakingPercentage).div(100);

        // Adjust Scale created per-second for each rate
        poolMintRate = calculateFraction(poolMintAmount, 31536000 ether, decimals);
        ownerMintRate = calculateFraction(ownerMintAmount, 31536000 ether, decimals);
        stakingMintRate = calculateFraction(stakingMintAmount, 31536000 ether, decimals);
    }
    /** 
     * @dev anyone can call this function to update the inflation rate yearly
     */
    function updateInflationRate() public {

      // Require 1 year to have passed for every inflation adjustment
      require(now.sub(lastInflationUpdate) >= 31536000);

      adjustInflationRate();

    }

    /////////////
    // Staking
    /////////////

    /** 
     * @dev staking function which allows users to stake an amount of tokens to gain interest for up to 30 days
     * @param _stakeAmount how many tokens a user wants to stake
     */
    function stakeScale(uint _stakeAmount) external {

        // Require that tokens are staked successfully
        require(stake(msg.sender, _stakeAmount));
    }
    /**
     * @dev stake for a seperate address
     * @param _stakeAmount how many tokens a user wants to stake
     */
    function stakeFor(address _user, uint _stakeAmount) external {

      // You can only stake tokens for another user if they have not already staked tokens
      require(stakeBalances[_user].stakeBalance == 0);

      // Transfer Scale from to the user
      transfer( _user, _stakeAmount);

      // Stake for the user
      stake(_user, _stakeAmount);
    }
    /**
      * @dev stake function reduces the user's total available balance and adds it to their staking balance
      * @param _value how many tokens a user wants to stake
      */
    function stake(address _user, uint256 _value) private returns (bool success) {

        // You can only stake as many tokens as you have
        require(_value <= balances[_user]);
        // You can only stake tokens if you have not already staked tokens
        require(stakeBalances[_user].stakeBalance == 0);

        // Subtract stake amount from regular token balance
        balances[_user] = balances[_user].sub(_value);

        // Add stake amount to staked balance
        stakeBalances[_user].stakeBalance = _value;

        // Increment the staking staked tokens value
        totalScaleStaked = totalScaleStaked.add(_value);

        // Save the time that the stake started
        stakeBalances[_user].initialStakeTime = now.div(timingVariable);

        // Set the new staking history
        setTotalStakingHistory();

        // Fire an event to tell the world of the newly staked tokens
        emit Stake(_user, _value);

        return true;
    }
    /**
      * @dev returns how much Scale a user has earned so far
      * @param _now is passed in to allow for a gas-free analysis
      * @return staking gains based on the amount of time passed since staking began
      */
    function getStakingGains(uint _now) view public returns (uint) {

        if (stakeBalances[msg.sender].stakeBalance == 0) {

          return 0;
        }

        return calculateStakeGains(_now);
    }
    
    /**
     * @dev allows users to reclaim any staked tokens
     * @return bool on success
     */
    function unstake() external returns (bool) {

        // Require that there was some amount vested
        require(stakeBalances[msg.sender].stakeBalance > 0);

        // Require that at least 7 timing variables have passed (days)
        require(now.div(timingVariable).sub(stakeBalances[msg.sender].initialStakeTime) >= 7);

        // Calculate tokens to mint
        uint _tokensToMint = calculateStakeGains(now);

        balances[msg.sender] = balances[msg.sender].add(stakeBalances[msg.sender].stakeBalance);

        // Subtract stake balance from totalScaleStaked
        totalScaleStaked = totalScaleStaked.sub(stakeBalances[msg.sender].stakeBalance);

        // Mint the new tokens to the sender
        mint(msg.sender, _tokensToMint);

        // Scale unstaked event
        emit Unstake(msg.sender, stakeBalances[msg.sender].stakeBalance, _tokensToMint);

        // Clear out stored data from mapping
        stakeBalances[msg.sender].stakeBalance = 0;
        stakeBalances[msg.sender].initialStakeTime = 0;

        // Set this every time someone adjusts the totalScaleStaking amount
        setTotalStakingHistory();

        return true;
    }

    /**
     * @dev Helper function to claimStake that modularizes the minting via staking calculation
     * @param _now when the user stopped staking. Passed in as a variable to allow for checking without using gas from the getStakingGains function.
     * @return uint for total coins to be minted
     */
    function calculateStakeGains(uint _now) view private returns (uint mintTotal)  {

      uint _nowAsTimingVariable = _now.div(timingVariable);    // Today as a unique value in unix time
      uint _initialStakeTimeInVariable = stakeBalances[msg.sender].initialStakeTime; // When the user started staking as a unique day in unix time
      uint _timePassedSinceStakeInVariable = _nowAsTimingVariable.sub(_initialStakeTimeInVariable); // How much time has passed, in days, since the user started staking.
      uint _stakePercentages = 0; // Keeps an additive track of the user's staking percentages over time
      uint _tokensToMint = 0; // How many new Scale tokens to create
      uint _lastUsedVariable;  // Last day the totalScaleStaked was updated

      // Average this msg.sender's relative percentage ownership of totalScaleStaked throughout each day since they started staking
      for (uint i = _initialStakeTimeInVariable; i < _nowAsTimingVariable; i++) {

        // If the day exists add it to the percentages
        if (totalStakingHistory[i] != 0) {

           // If the day does exist add it to the number to be later averaged as a total average percentage of total staking
          _stakePercentages = _stakePercentages.add(calculateFraction(stakeBalances[msg.sender].stakeBalance, totalStakingHistory[i], decimals));

          // Set this as the last day someone staked
          _lastUsedVariable = totalStakingHistory[i];
        }
        else {

          // Use the last day found in the totalStakingHistory mapping
          _stakePercentages = _stakePercentages.add(calculateFraction(stakeBalances[msg.sender].stakeBalance, _lastUsedVariable, decimals));
        }

      }

        // Get the account's average percentage staked of the total stake over the course of all days they have been staking
        uint _stakePercentageAverage = calculateFraction(_stakePercentages, _timePassedSinceStakeInVariable, 0);

        // Calculate this account's mint rate per second while staking
        uint _finalMintRate = stakingMintRate.mul(_stakePercentageAverage);

        // Account for 18 decimals when calculating the amount of tokens to mint
        _finalMintRate = _finalMintRate.div(1 ether);

        // Calculate total tokens to be minted. Multiply by timingVariable to convert back to seconds.
        if (_timePassedSinceStakeInVariable >= 365) {

          // Tokens were staked for the maximum amount of time, one year. Give them one year's worth of tokens. ( this limit is placed to avoid gas limits)
          _tokensToMint = calculateMintTotal(timingVariable.mul(365), _finalMintRate);
        }
        else {

          // Tokens were staked for less than the maximum amount of time
          _tokensToMint = calculateMintTotal(_timePassedSinceStakeInVariable.mul(timingVariable), _finalMintRate);
        }

        return  _tokensToMint;
    }
     /**
      * @dev set the new totalStakingHistory mapping to the current timestamp and totalScaleStaked
      */
    function setTotalStakingHistory() private {

      // Get now in terms of the variable staking accuracy (days in Scale's case)
      uint _nowAsTimingVariable = now.div(timingVariable);

      // Set the totalStakingHistory as a timestamp of the totalScaleStaked today
      totalStakingHistory[_nowAsTimingVariable] = totalScaleStaked;
    }

    /**
      * @dev Allows user to check their staked balance
      * @return staked balance
      */
    function getStakedBalance() view external returns (uint stakedBalance) {

        return stakeBalances[msg.sender].stakeBalance;
    }

    /////////////
    // Scale Owner Claiming
    /////////////

    /**
     * @dev allows contract owner to claim their mint
     */
    function ownerClaim() external onlyOwner {

        require(now > ownerTimeLastMinted);

        uint _timePassedSinceLastMint; // The amount of time passed since the owner claimed in seconds
        uint _tokenMintCount; // The amount of new tokens to mint
        bool _mintingSuccess; // The success of minting the new Scale tokens

        // Calculate the number of seconds that have passed since the owner last took a claim
        _timePassedSinceLastMint = now.sub(ownerTimeLastMinted);

        assert(_timePassedSinceLastMint > 0);

        // Determine the token mint amount, determined from the number of seconds passed and the ownerMintRate
        _tokenMintCount = calculateMintTotal(_timePassedSinceLastMint, ownerMintRate);

        // Mint the owner's tokens; this also increases totalSupply
        _mintingSuccess = mint(msg.sender, _tokenMintCount);

        require(_mintingSuccess);

        // New minting was a success. Set last time minted to current block.timestamp (now)
        ownerTimeLastMinted = now;
    }

    ////////////////////////////////
    // Scale Pool Distribution
    ////////////////////////////////

    /**
      * @dev anyone can call this function that mints Scale to the pool dedicated to Scale distribution to rewards pool
      */
    function poolIssue() public {

        // Do not allow tokens to be minted to the pool until the pool is set
        require(pool != address(0));

        // Make sure time has passed since last minted to pool
        require(now > poolTimeLastMinted);
        require(pool != address(0));

        uint _timePassedSinceLastMint; // The amount of time passed since the pool claimed in seconds
        uint _tokenMintCount; // The amount of new tokens to mint
        bool _mintingSuccess; // The success of minting the new Scale tokens

        // Calculate the number of seconds that have passed since the owner last took a claim
        _timePassedSinceLastMint = now.sub(poolTimeLastMinted);

        assert(_timePassedSinceLastMint > 0);

        // Determine the token mint amount, determined from the number of seconds passed and the ownerMintRate
        _tokenMintCount = calculateMintTotal(_timePassedSinceLastMint, poolMintRate);

        // Mint the owner's tokens; this also increases totalSupply
        _mintingSuccess = mint(pool, _tokenMintCount);

        require(_mintingSuccess);

        // New minting was a success! Set last time minted to current block.timestamp (now)
        poolTimeLastMinted = now;
    }
    /**
     * @dev sets the address for the rewards pool
     * @param _newAddress pool Address
     */
    function setPool(address _newAddress) public onlyOwner {

        pool = _newAddress;
    }

    ////////////////////////////////
    // Helper Functions
    ////////////////////////////////
    /**
      * @dev calculateFraction allows us to better handle the Solidity ugliness of not having decimals as a native type
      * @param _numerator is the top part of the fraction we are calculating
      * @param _denominator is the bottom part of the fraction we are calculating
      * @param _precision tells the function how many significant digits to calculate out to
      * @return quotient returns the result of our fraction calculation
      */
    function calculateFraction(uint _numerator, uint _denominator, uint _precision) pure private returns(uint quotient) {
        // Take passed value and expand it to the required precision
        _numerator = _numerator.mul(10 ** (_precision + 1));
        // Handle last-digit rounding
        uint _quotient = ((_numerator.div(_denominator)) + 5) / 10;
        return (_quotient);
    }

    /**
      * @dev Determines the amount of Scale to create based on the number of seconds that have passed
      * @param _timeInSeconds is the time passed in seconds to mint for
      * @return uint with the calculated number of new tokens to mint
     */
    function calculateMintTotal(uint _timeInSeconds, uint _mintRate) pure private returns(uint mintAmount) {
        // Calculates the amount of tokens to mint based upon the number of seconds passed
        return(_timeInSeconds.mul(_mintRate));
    }

}
