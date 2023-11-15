// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "../../interfaces/IExchangeConfig.sol";
import "../../pools/interfaces/IPools.sol";
import "./ICollateralAndLiquidity.sol";


interface ILiquidizer
	{
	function setContracts(ICollateralAndLiquidity _collateralAndLiquidity, IPools _pools, IDAO _dao) external; // onlyOwner
	function shouldBurnMoreUSDS( uint256 usdsToBurn ) external;
	function performUpkeep() external;

	// Views
	function usdsThatShouldBeBurned() external returns (uint256 _usdsThatShouldBeBurned);
	}
