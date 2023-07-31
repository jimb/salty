// SPDX-License-Identifier: BSL 1.1
pragma solidity =0.8.21;

import "../staking/interfaces/IStaking.sol";
import "../staking/interfaces/IStakingConfig.sol";
import "../pools/interfaces/IPoolsConfig.sol";
import "../rewards/interfaces/IRewardsEmitter.sol";
import "../interfaces/ISalt.sol";
import "../interfaces/IExchangeConfig.sol";
import "./interfaces/IEmissions.sol";
import "../openzeppelin/security/ReentrancyGuard.sol";


// Responsible for storing the SALT emissions at launch and then distributing them over time.
// The emissions are gradually distributed to the stakingRewardsEmitter and liquidityRewardsEmitter on performUpkeep.
// Default rate of emissions is 0.50% of the remaining SALT balance per week (interpolated based on the time elapsed since the last performUpkeep call).

contract Emissions is IEmissions, ReentrancyGuard
    {
	IStaking immutable public staking;
	IExchangeConfig immutable public exchangeConfig;
	IStakingConfig immutable public stakingConfig;
	IPoolsConfig immutable public poolsConfig;
	IRewardsConfig immutable public rewardsConfig;
	ISalt immutable public salt;

	// A special pool that represents staked SALT that is not associated with any particular pool.
	bytes32 public constant STAKED_SALT = bytes32(uint256(0));


    constructor( IStaking _staking, IExchangeConfig _exchangeConfig, IPoolsConfig _poolsConfig, IStakingConfig _stakingConfig, IRewardsConfig _rewardsConfig )
		{
		require( address(_staking) != address(0), "_staking cannot be address(0)" );

		require( address(_exchangeConfig) != address(0), "_exchangeConfig cannot be address(0)" );
		require( address(_poolsConfig) != address(0), "_poolsConfig cannot be address(0)" );
		require( address(_stakingConfig) != address(0), "_stakingConfig cannot be address(0)" );
		require( address(_rewardsConfig) != address(0), "_rewardsConfig cannot be address(0)" );

		staking = _staking;

		exchangeConfig = _exchangeConfig;
		stakingConfig = _stakingConfig;
		poolsConfig = _poolsConfig;
		rewardsConfig = _rewardsConfig;

		// Cached for efficiency
		salt = _exchangeConfig.salt();
		}


	// Transfer the specified amount of SALT rewards from this contract to the liquidityRewardsEmitter proportional to the number of votes received by each of the pools.
	function _performUpkeepForLiquidityHolderEmissions( uint256 amountToSend ) internal
		{
		bytes32[] memory pools = poolsConfig.whitelistedPools();

		// Votes will be based on staked xSALT.
		uint256[] memory votesForPools = staking.totalSharesForPools( pools );

		// Determine the total pool votes so we can calculate proportional voting percentages
		uint256 totalPoolVotes = 0;
		for( uint256 i = 0; i < votesForPools.length; i++ )
			totalPoolVotes += votesForPools[i];

		// No votes means nothing to send
		if ( totalPoolVotes == 0 )
			return;

		// Send the specified amountToSend SALT proportional to the votes received by each pool
		uint256 totalRewards;

		AddedReward[] memory addedRewards = new AddedReward[]( votesForPools.length );
		for( uint256 i = 0; i < addedRewards.length; i++ )
			{
			uint256 rewardsForPool = ( amountToSend * votesForPools[i] ) / totalPoolVotes;
			totalRewards += rewardsForPool;

			addedRewards[i] = AddedReward( pools[i], rewardsForPool );
			}

		// Send the SALT rewards to the LiquidityRewardsEmitter for the liquidity providers
		IRewardsEmitter liquidityRewardsEmitter = exchangeConfig.liquidityRewardsEmitter();
		salt.approve( address(liquidityRewardsEmitter), totalRewards );

		liquidityRewardsEmitter.addSALTRewards( addedRewards );
		}


	// Transfer a percent (default 0.50% per week) of the currently held SALT to stakingRewardsEmitter and liquidityRewardsEmitter
	// The percentage to transfer is interpolated from how long it's been since the last performUpkeep()
	function performUpkeep( uint256 timeSinceLastUpkeep ) public
		{
		require( msg.sender == address(exchangeConfig.dao()), "Emissions.performUpkeep only callable from the DAO contract" );

		if ( timeSinceLastUpkeep == 0 )
			return;

		uint256 saltBalance = salt.balanceOf( address( this ) );

		// Cap the timeSinceLastUpkeep at one week (if for some reason it has been longer).
		// This will cap the emitted rewards at a default of 0.50% in this transaction.
		if ( timeSinceLastUpkeep >= 1 weeks )
			timeSinceLastUpkeep = 1 weeks;

		// Target a certain percentage of rewards per week and base what we need to distribute now on how long it has been since the last distribution
		uint256 saltToSend = ( saltBalance * timeSinceLastUpkeep * rewardsConfig.emissionsWeeklyPercentTimes1000() ) / ( 100 * 1000 weeks );
		if ( saltToSend == 0 )
			return;

		// Split the emissions between xSALT Holders and Liquidity Providers
		uint256 xsaltHoldersAmount = ( saltToSend * rewardsConfig.rewardsXSaltHoldersPercent() ) / 100;
		uint256 liquidityHoldersRewardsAmount = saltToSend - xsaltHoldersAmount;

		// Send SALT rewards to the stakingRewardsEmitter
		AddedReward[] memory addedRewards = new AddedReward[](1);
		addedRewards[0] = AddedReward( STAKED_SALT, xsaltHoldersAmount );

		IRewardsEmitter stakingRewardsEmitter = exchangeConfig.stakingRewardsEmitter();
		salt.approve( address(stakingRewardsEmitter), xsaltHoldersAmount );
		stakingRewardsEmitter.addSALTRewards( addedRewards );

		// Send the remaining SALT rewards to the liquidity providers (proportional to the votes received by each pool)
		_performUpkeepForLiquidityHolderEmissions( liquidityHoldersRewardsAmount );
		}
	}
