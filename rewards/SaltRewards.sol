// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.21;

import "../openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../rewards/interfaces/IRewardsEmitter.sol";
import "../rewards/interfaces/IRewardsConfig.sol";
import "../interfaces/ISalt.sol";
import "../interfaces/IExchangeConfig.sol";
import "./interfaces/ISaltRewards.sol";
import "../pools/PoolUtils.sol";
import "../openzeppelin/security/ReentrancyGuard.sol";


// Temporarily holds SALT rewards from emissions and arbitrage profits during performUpkeep().
// Sends them to the stakingRewardsEmitter and liquidityRewardsEmitter (with proportions for the latter based on a pool's share in generating the recent arbitrage profits).
contract SaltRewards is ISaltRewards, ReentrancyGuard
    {
	using SafeERC20 for ISalt;

	IExchangeConfig immutable public exchangeConfig;
	IRewardsConfig immutable public rewardsConfig;

	ISalt immutable public salt;
	IUSDS immutable public usds;

    uint256 public pendingRewardsSaltUSDS;
    uint256 public pendingStakingRewards;
	uint256 public pendingLiquidityRewards;


    constructor( IExchangeConfig _exchangeConfig, IRewardsConfig _rewardsConfig )
		{
		require( address(_exchangeConfig) != address(0), "_exchangeConfig cannot be address(0)" );
		require( address(_rewardsConfig) != address(0), "_rewardsConfig cannot be address(0)" );

		exchangeConfig = _exchangeConfig;
		rewardsConfig = _rewardsConfig;

		// Cached for efficiency
		salt = _exchangeConfig.salt();
		usds = _exchangeConfig.usds();
		}


	// Add SALT rewards and keep track of the amount pending for each pool based on RewardsConfig.stakingRewardsPercent
	function addSALTRewards(uint256 amount) public nonReentrant
		{
		if ( amount == 0 )
			return;

		// Determine how much of the SALT rewards will be directly sent to the SALT/USDS pool.
		// This is because SALT/USDS is important, but not included in other arbitrage trades - which would yield additional rewards for the pool by being part of arbitrage.
		uint256 amountSaltUSDS = ( amount * rewardsConfig.percentRewardsSaltUSDS() ) / 100;
		pendingRewardsSaltUSDS += amountSaltUSDS;

		uint256 remainingAmount = amount - amountSaltUSDS;

		// Divide up the remaining rewards between SALT stakers and liquidity providers
		uint256 stakingAmount = ( remainingAmount * rewardsConfig.stakingRewardsPercent() ) / 100;
		uint256 liquidityAmount = remainingAmount - stakingAmount;

		pendingStakingRewards += stakingAmount;
		pendingLiquidityRewards += liquidityAmount;

		salt.safeTransferFrom( msg.sender, address(this), amount );
		}


	// Send the pending SALT rewards to the stakingRewardsEmitter
	function _sendStakingRewards() internal
		{
		AddedReward[] memory addedRewards = new AddedReward[](1);
		addedRewards[0] = AddedReward( PoolUtils.STAKED_SALT, pendingStakingRewards );

		IRewardsEmitter stakingRewardsEmitter = exchangeConfig.stakingRewardsEmitter();
		salt.approve( address(stakingRewardsEmitter), pendingStakingRewards );
		stakingRewardsEmitter.addSALTRewards( addedRewards );

		// Mark the pendingStakingRewards as sent
		pendingStakingRewards = 0;
		}


	// Transfer SALT rewards to the liquidityRewardsEmitter proportional to pool shares in generating recent arb profits.
	function _sendLiquidityRewards( bytes32[] memory poolIDs, uint256[] memory profitsForPools ) internal
		{
		// Determine the total profits so we can calculate proportional share
		uint256 totalProfits = 0;
		for( uint256 i = 0; i < poolIDs.length; i++ )
			totalProfits += profitsForPools[i];

		// Can't send rewards with no profits
		if ( totalProfits == 0 )
			return;

		(bytes32 saltUSDS,) = PoolUtils.poolID(salt, usds);

		// Send SALT rewards (with an amount of pendingLiquidityRewards) proportional to the profits generated by each pool
		AddedReward[] memory addedRewards = new AddedReward[]( poolIDs.length );
		for( uint256 i = 0; i < addedRewards.length; i++ )
			{
			bytes32 poolID = poolIDs[i];
			uint256 rewardsForPool = ( pendingLiquidityRewards * profitsForPools[i] ) / totalProfits;

			// The SALT/USDS is entitled to additional rewards - as specified by RewardsConfig.percentRewardsSaltUSDS
			if ( poolID == saltUSDS )
				rewardsForPool += pendingRewardsSaltUSDS;

			addedRewards[i] = AddedReward( poolID, rewardsForPool );
			}

		// Send the SALT rewards to the LiquidityRewardsEmitter
		IRewardsEmitter liquidityRewardsEmitter = exchangeConfig.liquidityRewardsEmitter();
		salt.approve( address(liquidityRewardsEmitter), pendingLiquidityRewards + pendingRewardsSaltUSDS );

		liquidityRewardsEmitter.addSALTRewards( addedRewards );

		// Update pending rewards
		pendingLiquidityRewards = 0;
		pendingRewardsSaltUSDS = salt.balanceOf(address(this));
		}


	function _sendInitialLiquidityRewards( uint256 liquidityBootstrapAmount, bytes32[] memory poolIDs ) internal
		{
		// Divide the liquidityBootstrapAmount evenly across all the initial pools
		uint256 amountPerPool = liquidityBootstrapAmount / poolIDs.length;

		AddedReward[] memory addedRewards = new AddedReward[]( poolIDs.length );
		for( uint256 i = 0; i < addedRewards.length; i++ )
			addedRewards[i] = AddedReward( poolIDs[i], amountPerPool );

		// Send the liquidity bootstrap rewards to the liquidityRewardsEmitter
		IRewardsEmitter liquidityRewardsEmitter = exchangeConfig.liquidityRewardsEmitter();
		salt.approve( address(liquidityRewardsEmitter), liquidityBootstrapAmount );

		liquidityRewardsEmitter.addSALTRewards( addedRewards );
		}


	function _sendInitialStakingRewards( uint256 stakingBootstrapAmount ) internal
		{
		// Send the stakingBootstrapAmount to the stakingRewardsEmitter
		AddedReward[] memory addedRewards = new AddedReward[](1);
		addedRewards[0] = AddedReward( PoolUtils.STAKED_SALT, stakingBootstrapAmount );

		IRewardsEmitter stakingRewardsEmitter = exchangeConfig.stakingRewardsEmitter();
		salt.approve( address(stakingRewardsEmitter), stakingBootstrapAmount );
		stakingRewardsEmitter.addSALTRewards( addedRewards );
		}


    // Sends 5 million SALT to the liquidityRewardsEmitter (evenly divided amongst the pools) and 3 million SALT to the stakingRewardsEmitter.
	function sendInitialSaltRewards( uint256 liquidityBootstrapAmount, uint256 stakingBootstrapAmount, bytes32[] memory poolIDs ) public
		{
		require( msg.sender == address(exchangeConfig.initialDistribution()), "SaltRewards.sendInitialRewards is only callable from the InitialDistribution contract" );

		_sendInitialLiquidityRewards(liquidityBootstrapAmount, poolIDs);
		_sendInitialStakingRewards(stakingBootstrapAmount);
		}


	function performUpkeep( bytes32[] memory poolIDs, uint256[] memory profitsForPools ) public
		{
		require( msg.sender == address(exchangeConfig.upkeep()), "SaltRewards.performUpkeep is only callable from the Upkeep contract" );

		if ( (pendingStakingRewards == 0) || (pendingLiquidityRewards == 0) )
			return;

		_sendStakingRewards();
		_sendLiquidityRewards(poolIDs, profitsForPools);
		}
	}
