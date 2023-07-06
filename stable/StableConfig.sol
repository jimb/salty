//// SPDX-License-Identifier: BSL 1.1
//pragma solidity ^0.8.12;
//
//import "../openzeppelin/access/Ownable.sol";
//import "./interfaces/IPriceFeed.sol";
//import "./interfaces/IStableConfig.sol";
//
//// Contract owned by the DAO with parameters modifiable only by the DAO
//contract StableConfig is IStableConfig, Ownable
//    {
//	// @dev Interface for the price feed that provides prices for both BTC and ETH
//	IPriceFeed public priceFeed;
//
//	// The reward (in collateraLP) that a user receives for instigating the liquidation process - as a percentage
//	// of the amount of collateralLP that is liquidated.
//	// Range: 5 to 10 with an adjustment of 1
//    uint256 public rewardPercentForCallingLiquidation = 5;
//
//	// The maximum reward value (in USD) that a user receives for instigating the liquidation process.
//	// Range: 100 to 500 with an adjustment of 50 ether
//    uint256 public maxRewardValueForCallingLiquidation = 300 ether;
//
//	// The minimum USD value of collateral - to borrow an initial amount of USDS.
//	// This is to help prevent saturation of the contract with small amounts of positions and to ensure that
//	// liquidating the position yields non-trivial rewards
//	// Range: 1000 to 5000 with an adjustment of 500 ether
//    uint256 public minimumCollateralValueForBorrowing = 2500 ether;
//
//    // The ratio required for initial collateral / borrowed USDS
//    // Defaults to 2.0x so that staking $1000 of BTC/ETH LP would allow you to borrow $500 of USDS
//    // Range: 150 to 300 with an adjustment of 25
//    uint256 public initialCollateralRatioPercent = 200;
//
//	// The minimum ratio of collateral / borrowed USDS that can lead to the position being liquidated
//	// and the user losing their collateral (and keeping the borrowed USDS)
//	// Range: 110 to 120 with an adjustment of 1
//	uint256 public minimumCollateralRatioPercent = 110;
//
//
//	// @dev Constructs the StableConfig contract with the specified price feed.
//	// @param _priceFeed The price feed that provides prices for both BTC and ETH.
//	constructor( IPriceFeed _priceFeed )
//		{
//		setPriceFeed( _priceFeed );
//		}
//
//
//	// @dev Sets the price feed that provides prices for both BTC and ETH.
//	// @param _priceFeed The address of the new price feed contract.
//	function setPriceFeed( IPriceFeed _priceFeed ) public onlyOwner
//		{
//		require( address(_priceFeed) != address(0), "Cannot specify a null PriceFeed" );
//		priceFeed = _priceFeed;
//		}
//
//
//	function changeRewardPercentForCallingLiquidation(bool increase) public onlyOwner
//        {
//		// Don't act if (minimumCollateralRatioPercent - rewardPercentForCallingLiquidation) is less than 105% to ensure that the position will be liquidatable for more than the originally borrowed USDS amount (assume reasonable market volatility)
//        uint256 remainingRatioAfterReward = minimumCollateralRatioPercent - rewardPercentForCallingLiquidation - 1;
//        if (increase)
//            {
//            if (remainingRatioAfterReward >= 105 && rewardPercentForCallingLiquidation < 10)
//                rewardPercentForCallingLiquidation = rewardPercentForCallingLiquidation + 1;
//            }
//        else
//            {
//            if (rewardPercentForCallingLiquidation > 5)
//                rewardPercentForCallingLiquidation = rewardPercentForCallingLiquidation - 1;
//            }
//        }
//
//
//	function changeMaxRewardValueForCallingLiquidation(bool increase) public onlyOwner
//        {
//        if (increase)
//            {
//            if (maxRewardValueForCallingLiquidation < 500 ether)
//                maxRewardValueForCallingLiquidation = maxRewardValueForCallingLiquidation + 50 ether;
//            }
//        else
//            {
//            if (maxRewardValueForCallingLiquidation > 100 ether)
//                maxRewardValueForCallingLiquidation = maxRewardValueForCallingLiquidation - 50 ether;
//            }
//        }
//
//
//	function changeMinimumCollateralValueForBorrowing(bool increase) public onlyOwner
//        {
//        if (increase)
//            {
//            if (minimumCollateralValueForBorrowing < 5000 ether)
//                minimumCollateralValueForBorrowing = minimumCollateralValueForBorrowing + 500 ether;
//            }
//        else
//            {
//            if (minimumCollateralValueForBorrowing > 1000 ether)
//                minimumCollateralValueForBorrowing = minimumCollateralValueForBorrowing - 500 ether;
//            }
//        }
//
//
//	function changeInitialCollateralRatioPercent(bool increase) public onlyOwner
//        {
//        if (increase)
//            {
//            if (initialCollateralRatioPercent < 300)
//                initialCollateralRatioPercent = initialCollateralRatioPercent + 25;
//            }
//        else
//            {
//            if (initialCollateralRatioPercent > 150)
//                initialCollateralRatioPercent = initialCollateralRatioPercent - 25;
//            }
//        }
//
//
//	function changeMinimumCollateralRatioPercent(bool increase) public onlyOwner
//        {
//        uint256 remainingRatioAfterReward = minimumCollateralRatioPercent - 1 - rewardPercentForCallingLiquidation;
//        if (increase)
//            {
//            if (minimumCollateralRatioPercent < 120)
//                minimumCollateralRatioPercent = minimumCollateralRatioPercent + 1;
//            }
//        else
//            {
//            if (remainingRatioAfterReward >= 105 && minimumCollateralRatioPercent > 110)
//                minimumCollateralRatioPercent = minimumCollateralRatioPercent - 1;
//            }
//        }
//	}