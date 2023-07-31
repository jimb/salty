// SPDX-License-Identifier: BSL 1.1
pragma solidity =0.8.21;


interface IAccessManager
	{
	function excludedCountriesUpdated() external;
	function grantAccess() external;

	// Views
	function geoVersion() external view returns (uint256);
	function walletHasAccess(address wallet) external view returns (bool);
	}
