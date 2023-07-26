// SPDX-License-Identifier: BSL 1.1
pragma solidity =0.8.20;


interface IPriceFeedUniswap
	{
	function getTwapWBTC( uint256 twapInterval ) external view returns (uint256);
	function getTwapWETH( uint256 twapInterval ) external view returns (uint256);
	}