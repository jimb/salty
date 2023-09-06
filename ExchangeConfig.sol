// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.21;

import "./openzeppelin/access/Ownable.sol";
import "./interfaces/IExchangeConfig.sol";
import "./rewards/interfaces/IRewardsEmitter.sol";
import "./rewards/interfaces/ISaltRewards.sol";
import "./interfaces/IUpkeep.sol";
import "./launch/interfaces/IInitialDistribution.sol";


// Contract owned by the DAO with parameters modifiable only by the DAO
contract ExchangeConfig is IExchangeConfig, Ownable
    {
	ISalt immutable public salt;
	IERC20 immutable public wbtc;
	IERC20 immutable public weth;
	IERC20 immutable public dai;
	IUSDS immutable public usds;

	IDAO public dao; // can only be set once
	IUpkeep public upkeep; // can only be set once

	IRewardsEmitter public stakingRewardsEmitter;
	IRewardsEmitter public liquidityRewardsEmitter;
	IAccessManager public accessManager;
	IInitialDistribution public initialDistribution;

	address public teamWallet;
	address public teamVestingWallet;	// can only be set once
	address public daoVestingWallet;		// can only be set once


	constructor( ISalt _salt, IERC20 _wbtc, IERC20 _weth, IERC20 _dai, IUSDS _usds, address _teamWallet )
		{
		require( address(_salt) != address(0), "_salt cannot be address(0)" );
		require( address(_wbtc) != address(0), "_wbtc cannot be address(0)" );
		require( address(_weth) != address(0), "_weth cannot be address(0)" );
		require( address(_dai) != address(0), "_dai cannot be address(0)" );
		require( address(_usds) != address(0), "_usds cannot be address(0)" );
		require( address(_teamWallet) != address(0), "_teamWallet cannot be address(0)" );

		salt = _salt;
		wbtc = _wbtc;
		weth = _weth;
		dai = _dai;
		usds = _usds;
		teamWallet = _teamWallet;
        }


	function setDAO( IDAO _dao ) public onlyOwner
		{
		require( address(dao) == address(0), "setDAO can only be called once" );
		require( address(_dao) != address(0), "_dao cannot be address(0)" );

		dao = _dao;
		}


	function setUpkeep( IUpkeep _upkeep ) public onlyOwner
		{
		require( address(upkeep) == address(0), "setUpkeep can only be called once" );
		require( address(_upkeep) != address(0), "_upkeep cannot be address(0)" );

		upkeep = _upkeep;
		}


	function setAccessManager( IAccessManager _accessManager ) public onlyOwner
		{
		require( address(_accessManager) != address(0), "_accessManager cannot be address(0)" );

		accessManager = _accessManager;
		}


	function setStakingRewardsEmitter( IRewardsEmitter _rewardsEmitter ) public onlyOwner
		{
		require( address(_rewardsEmitter) != address(0), "_rewardsEmitter cannot be address(0)" );

		stakingRewardsEmitter = _rewardsEmitter;
		}


	function setLiquidityRewardsEmitter( IRewardsEmitter _rewardsEmitter ) public onlyOwner
		{
		require( address(_rewardsEmitter) != address(0), "_rewardsEmitter cannot be address(0)" );

		liquidityRewardsEmitter = _rewardsEmitter;
		}


	function setTeamWallet( address _teamWallet ) public
		{
		require( msg.sender == teamWallet, "Only the current team can change the teamWallet" );

		teamWallet = _teamWallet;
		}


	function setVestingWallets( address _teamVestingWallet, address _daoVestingWallet ) public
		{
		require( address(teamVestingWallet) == address(0), "setVestingWallets can only be called once" );
		require( address(_teamVestingWallet) != address(0), "_teamVestingWallet cannot be address(0)" );
		require( address(_daoVestingWallet) != address(0), "_daoVestingWallet cannot be address(0)" );

		teamVestingWallet = _teamVestingWallet;
		daoVestingWallet = _daoVestingWallet;
		}


	function setInitialDistribution( IInitialDistribution _initialDistribution ) public
		{
		require( address(initialDistribution) == address(0), "setInitialDistribution can only be called once" );
		require( address(_initialDistribution) != address(0), "_initialDistribution cannot be address(0)" );

		initialDistribution = _initialDistribution;
		}


	// Provide access to the protocol components that require it and then look to the AccessManager to determine if a wallet should have access.
	function walletHasAccess( address wallet ) public view returns (bool)
		{
		// The dao should always have access, even if it didn't register with the AccessManager
		if ( wallet == address(dao) )
			return true;

		return accessManager.walletHasAccess( wallet );
		}
    }