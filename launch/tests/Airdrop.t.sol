// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.21;

import "forge-std/Test.sol";
import "../../dev/Deployment.sol";
import "../../root_tests/TestERC20.sol";
import "../../ExchangeConfig.sol";
import "../../pools/Pools.sol";
import "../../staking/Liquidity.sol";
import "../../staking/Staking.sol";
import "../../stable/Collateral.sol";
import "../../rewards/RewardsEmitter.sol";
import "../../price_feed/tests/IForcedPriceFeed.sol";
import "../../pools/PoolsConfig.sol";
import "../../price_feed/PriceAggregator.sol";
import "../../AccessManager.sol";
import "../InitialDistribution.sol";
import "../../Upkeep.sol";
import "../../dao/Proposals.sol";
import "../../dao/DAO.sol";


contract TestAirdrop is Deployment
	{
	uint256 constant public MILLION_ETHER = 1000000 ether;


	// User wallets for testing
    address public constant alice = address(0x1111);
    address public constant bob = address(0x2222);


	constructor()
		{
		// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
		// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
		if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
			{
			// Transfer the salt from the original initialDistribution to the DEPLOYER
			vm.prank(address(initialDistribution));
			salt.transfer(DEPLOYER, 100 * MILLION_ETHER);

			vm.startPrank(DEPLOYER);

			poolsConfig = new PoolsConfig();
			usds = new USDS(wbtc, weth);

			exchangeConfig = new ExchangeConfig(salt, wbtc, weth, dai, usds, teamWallet );

			priceAggregator = new PriceAggregator();
			priceAggregator.setInitialFeeds( IPriceFeed(address(forcedPriceFeed)), IPriceFeed(address(forcedPriceFeed)), IPriceFeed(address(forcedPriceFeed)) );

			pools = new Pools(exchangeConfig, poolsConfig);
			staking = new Staking( exchangeConfig, poolsConfig, stakingConfig );
			liquidity = new Liquidity( pools, exchangeConfig, poolsConfig, stakingConfig );
			collateral = new Collateral(pools, exchangeConfig, poolsConfig, stakingConfig, stableConfig, priceAggregator);

			stakingRewardsEmitter = new RewardsEmitter( staking, exchangeConfig, poolsConfig, rewardsConfig );
			liquidityRewardsEmitter = new RewardsEmitter( liquidity, exchangeConfig, poolsConfig, rewardsConfig );

			emissions = new Emissions( saltRewards, exchangeConfig, rewardsConfig );

			poolsConfig.whitelistPool(pools, salt, wbtc);
			poolsConfig.whitelistPool(pools, salt, weth);
			poolsConfig.whitelistPool(pools, salt, usds);
			poolsConfig.whitelistPool(pools, wbtc, usds);
			poolsConfig.whitelistPool(pools, weth, usds);
			poolsConfig.whitelistPool(pools, wbtc, dai);
			poolsConfig.whitelistPool(pools, weth, dai);
			poolsConfig.whitelistPool(pools, usds, dai);
			poolsConfig.whitelistPool(pools, wbtc, weth);

			proposals = new Proposals( staking, exchangeConfig, poolsConfig, daoConfig );

			address oldDAO = address(dao);
			dao = new DAO( pools, proposals, exchangeConfig, poolsConfig, stakingConfig, rewardsConfig, stableConfig, daoConfig, priceAggregator, liquidityRewardsEmitter);

			airdrop = new Airdrop(exchangeConfig, staking);

			accessManager = new AccessManager(dao);

			exchangeConfig.setAccessManager( accessManager );
			exchangeConfig.setStakingRewardsEmitter( stakingRewardsEmitter);
			exchangeConfig.setLiquidityRewardsEmitter( liquidityRewardsEmitter);
			exchangeConfig.setDAO( dao );
			exchangeConfig.setAirdrop(airdrop);

			saltRewards = new SaltRewards(exchangeConfig, rewardsConfig);

			upkeep = new Upkeep(pools, exchangeConfig, poolsConfig, daoConfig, priceAggregator, saltRewards, liquidity, emissions);
			exchangeConfig.setUpkeep(upkeep);

			initialDistribution = new InitialDistribution(salt, poolsConfig, emissions, bootstrapBallot, dao, daoVestingWallet, teamVestingWallet, airdrop, saltRewards, liquidity);
			exchangeConfig.setInitialDistribution(initialDistribution);

			pools.setDAO(dao);

			usds.setContracts(collateral, pools, exchangeConfig );

			// Transfer ownership of the newly created config files to the DAO
			Ownable(address(exchangeConfig)).transferOwnership( address(dao) );
			Ownable(address(poolsConfig)).transferOwnership( address(dao) );
			Ownable(address(priceAggregator)).transferOwnership(address(dao));
			vm.stopPrank();

			vm.startPrank(address(oldDAO));
			Ownable(address(stakingConfig)).transferOwnership( address(dao) );
			Ownable(address(rewardsConfig)).transferOwnership( address(dao) );
			Ownable(address(stableConfig)).transferOwnership( address(dao) );
			Ownable(address(daoConfig)).transferOwnership( address(dao) );
			vm.stopPrank();

			// Transfer SALT to the new InitialDistribution contract
			vm.startPrank(DEPLOYER);
			salt.transfer(address(initialDistribution), 100 * MILLION_ETHER);
			vm.stopPrank();
			}

		vm.prank(DEPLOYER);
		airdrop.whitelistWallet(alice);
		}


	// A unit test to check if the constructor reverts with any zero address arguments
	function testAirdropConstructor() public
    	{
    	IExchangeConfig _exchangeConfigZero = IExchangeConfig(address(0));
    	IStaking _stakingZero = IStaking(address(0));

    	vm.expectRevert("_exchangeConfig cannot be address(0)");
    	new Airdrop(_exchangeConfigZero, staking);

    	vm.expectRevert("_staking cannot be address(0)");
    	new Airdrop(exchangeConfig, _stakingZero);
    	}


	// A unit test to ensure the `whitelistWallet` function successfully adds a non-zero address to the `_whitelist` and verify that the function reverts when `claimingAllowed` is true.
	function testWhitelistWallet() external {
    	// Check that Alice is already whitelisted
    	assertTrue(airdrop.whitelisted(alice), "Alice should be whitelisted");

    	// Whitelist Bob
    	vm.prank(DEPLOYER);
    	airdrop.whitelistWallet(bob);
    	assertTrue(airdrop.whitelisted(bob), "Bob should be whitelisted");

    	// Try to whitelist when claimingAllowed is true, expect to revert
    	vm.prank(address(initialDistribution));
    	airdrop.allowClaiming();

    	vm.expectRevert("Cannot whitelist after claiming is allowed");
    	vm.prank(DEPLOYER);
    	airdrop.whitelistWallet(bob);
    }


	// A unit test to examine that the `whitelistWallets` function properly adds multiple non-zero addresses to the `_whitelist` and confirm that the function reverts when `claimingAllowed` is true.
	function testWhitelistWallets() external {
        // Whitelist Bob and Alice
        address[] memory wallets = new address[](2);
        wallets[0] = alice;
        wallets[1] = bob;
        vm.prank(DEPLOYER);
        airdrop.whitelistWallets(wallets);
        assertTrue(airdrop.whitelisted(alice), "Alice should be whitelisted");
        assertTrue(airdrop.whitelisted(bob), "Bob should be whitelisted");

        // Verify the number of whitelisted wallets
        assertEq(airdrop.numberWhitelisted(), 2, "The number of whitelisted wallets should be 2");

        // Try to whitelist when claimingAllowed is true, expect to revert
        vm.prank(address(initialDistribution));
        airdrop.allowClaiming();

        vm.expectRevert("Cannot whitelist after claiming is allowed");
        vm.prank(DEPLOYER);
        airdrop.whitelistWallets(wallets);
    }


	// A unit test to confirm that the `unwhitelistWallet` function successfully removes an already whitelisted address from the `_whitelist`.
	function testUnwhitelistWallet() external {
		// Check that Alice is already whitelisted
		assertTrue(airdrop.whitelisted(alice), "Alice should already be whitelisted");

		// Unwhitelist Alice
		vm.prank(DEPLOYER);
		airdrop.unwhitelistWallet(alice);
		assertFalse(airdrop.whitelisted(alice), "Alice should now be unwhitelisted");
	}


	// A unit test to verify that the `allowClaiming` function sets `claimingAllowed` to true and calculate `saltAmountForEachUser` correctly when the number of whitelisted addresses is more than zero and the caller is the `InitialDistribution` contract.
	function testAllowClaiming() external {
        // Check that claiming is initially not allowed
        assertFalse(airdrop.claimingAllowed(), "Claiming should not be allowed initially");

        vm.prank(address(bootstrapBallot));
        initialDistribution.distributionApproved();

        // Get initial salt balance of Airdrop contract
        uint256 initialSaltBalance = salt.balanceOf(address(airdrop));
        assertEq( initialSaltBalance, 5000000 ether);

        // Check that claiming is now allowed
        assertTrue(airdrop.claimingAllowed(), "Claiming should be allowed after calling allowClaiming");

        // Call `allowClaiming` function from InitialDistribution contract
        vm.expectRevert( "Claiming is already allowed" );
        vm.prank(address(initialDistribution));
        airdrop.allowClaiming();

        // Check that saltAmountForEachUser is calculated correctly
        uint256 expectedSaltAmountForEachUser = initialSaltBalance / airdrop.numberWhitelisted();
        assertEq(airdrop.saltAmountForEachUser(), expectedSaltAmountForEachUser, "saltAmountForEachUser should be calculated correctly");
    }


	// A unit test to confirm that the `allowClaiming` function reverts when the number of whitelisted addresses is zero or the caller is not the `InitialDistribution` contract.
	function testAllowClaimingRevert() external {
        // Check that claiming is initially not allowed
        assertFalse(airdrop.claimingAllowed(), "Claiming should not be allowed initially");

        // Try to allow claiming when the number of whitelisted addresses is zero, expect to revert with the message "No addresses whitelisted to claim airdrop."
        // Ensure all whitelisted wallets are unwhitelisted.
        for (uint256 i = 0; i < airdrop.numberWhitelisted(); i++)
        	{
            address wallet = airdrop.whitelistedWallets()[i];
            vm.prank(DEPLOYER);
            airdrop.unwhitelistWallet(wallet);
        	}

        vm.expectRevert("No addresses whitelisted to claim airdrop.");
        vm.prank(address(initialDistribution));
        airdrop.allowClaiming();

        // Whitelist a wallet.
        vm.prank(DEPLOYER);
        airdrop.whitelistWallet(alice);

        // Try to allow claiming when caller is not the `InitialDistribution` contract, expect to revert
        vm.expectRevert("Airdrop.allowClaiming can only be called by the InitialDistribution contract");
        airdrop.allowClaiming();
    }


	// A unit test to ensure the `claimAirdrop` function properly marks an address as claimed and verifies that the address was eligible to claim the airdrop (was whitelisted, has not claimed yet, claiming is allowed and the wallet has exchange access).
	function testClaimAirdrop() external {

		// Revert as claiming is not allowed yet
    	vm.prank(bob);
    	vm.expectRevert("Claiming is not allowed yet");
    	airdrop.claimAirdrop();

		// Whitelist
    	vm.prank(DEPLOYER);
    	airdrop.whitelistWallet(bob);

    	// Approve the distribution to allow claiming
    	vm.prank(address(bootstrapBallot));
    	initialDistribution.distributionApproved();
    	assertTrue(airdrop.claimingAllowed(), "Claiming should be allowed for the test");

    	// Check revert for no exchange access
    	vm.prank(bob);
    	vm.expectRevert("Sender does not have exchange access");
    	airdrop.claimAirdrop();

    	// Grant access
    	vm.prank(bob);
    	accessManager.grantAccess();
    	assertTrue(exchangeConfig.walletHasAccess(bob), "Bob should have exchange access for the test");

    	// Make sure bob has not claimed yet
    	assertFalse(airdrop.claimed(bob), "Bob should not have claimed for the test");

    	// Claim airdrop
    	vm.prank(bob);
    	airdrop.claimAirdrop();

    	// Verify that Bob successfully claimed
    	assertTrue(airdrop.claimed(bob), "Bob should have successfully claimed the airdrop");

    	// Claim airdrop again (expect to revert)
    	vm.prank(bob);
    	vm.expectRevert("Wallet already claimed the airdrop");
    	airdrop.claimAirdrop();
    }


	// A unit test to verify that the `whitelisted` function returns true for a whitelisted address and false for a non-whitelisted address.
	function testWhitelistedFunction() public {
        // Whitelist Alice
        vm.prank(DEPLOYER);
        airdrop.whitelistWallet(alice);

        // Verify the Alice is whitelisted
        assertTrue(airdrop.whitelisted(alice), "Alice should be whitelisted");

        // Verify that the Bob is not whitelisted
        assertFalse(airdrop.whitelisted(bob), "Bob should not be whitelisted");
    }


	// A unit test to confirm that the `numberWhitelisted` function returns the correct number of whitelisted addresses.
	    // A unit test to confirm that the `numberWhitelisted` function returns the correct number of whitelisted addresses.
    	function testNumberWhitelisted() external {
    		// Before whitelisting Bob, there should only be one whitelisted address (Alice)
    		assertEq(airdrop.numberWhitelisted(), 1, "There should be 1 whitelisted address initially");

    		// Whitelist Bob
    		vm.prank(DEPLOYER);
    		airdrop.whitelistWallet(bob);

    		// After whitelisting Bob, there should be two whitelisted addresses
    		assertEq(airdrop.numberWhitelisted(), 2, "There should be 2 whitelisted addresses after adding Bob");

    		// unwhitelist Bob
    		vm.prank(DEPLOYER);
    		airdrop.unwhitelistWallet(bob);

    		// After unwhitelisting Bob, there should be one whitelisted addresses (Alice)
    		assertEq(airdrop.numberWhitelisted(), 1, "There should be 1 whitelisted address after unwhitelisting Bob");
    	}


	// A unit test to ensure that the `whitelistedWallets` function returns an array of all whitelisted addresses.
	function testWhitelistedWallets() external {
        // Whitelist Alice and Bob
        address[] memory wallets = new address[](2);
        wallets[0] = alice;
        wallets[1] = bob;
        vm.prank(DEPLOYER);
        airdrop.whitelistWallets(wallets);

        // Fetch the list of whitelisted wallets
        address[] memory whitelistedWallets = airdrop.whitelistedWallets();
        assertEq(whitelistedWallets.length, 2, "There should be two whitelisted wallets");

        // Check if Alice and Bob are in the list
        bool isAliceFound = false;
        bool isBobFound = false;
        for (uint256 i = 0; i < whitelistedWallets.length; i++) {
            if (whitelistedWallets[i] == alice) {
                isAliceFound = true;
            } else if (whitelistedWallets[i] == bob) {
                isBobFound = true;
            }
        }
        assertTrue(isAliceFound, "Alice should be in the list of whitelisted wallets");
        assertTrue(isBobFound, "Bob should be in the list of whitelisted wallets");
    }


	// A unit test to ensure that the `claimed` mapping returns true for an address after it has successfully claimed the airdrop.
	function testClaimAirdrop2() external {
        // Ensure Alice is whitelisted and claiming is allowed
        vm.startPrank(DEPLOYER);
        airdrop.whitelistWallet(alice);
        vm.stopPrank();

    	vm.prank(address(bootstrapBallot));
    	initialDistribution.distributionApproved();

        // Check that claimed mapping initially return false for Alice
        assertFalse(airdrop.claimed(alice), "Alice should not have claimed initially");

        // Get initial xSALT balance of Alice
        uint256 initialXSaltBalance = staking.userXSalt(alice);

        // Claim airdrop for Alice
        vm.startPrank(alice);
        accessManager.grantAccess();
        airdrop.claimAirdrop();
        vm.stopPrank();

        // Get final xSALT balance of Alice
        uint256 finalXSaltBalance = staking.userXSalt(alice);

        // Check that the final xSALT balance of Alice is the initial xSALT balance plus saltAmountForEachUser
        assertEq(finalXSaltBalance, initialXSaltBalance + airdrop.saltAmountForEachUser(), "Claim Airdrop did not function correctly");


        // Check that claimed mapping now returns true for Alice
        assertTrue(airdrop.claimed(alice), "Alice should have claimed after claiming airdrop");
    }


	// A unit test to check if the `claimed` mapping returns false for an address that hasn't claimed the airdrop yet.
	function testNotYetClaimed() public {
        assertFalse(airdrop.claimed(alice), "Alice should not have claimed the airdrop yet");
    }


	// A unit test to check that onlyOwner functions revert when not called by the owner.
	function testOnlyOwnerFunctionsRevertWhenNotByOwner() external {
		// Attempt to whitelist an address from a non-owner address and expect to revert
		vm.expectRevert("Ownable: caller is not the owner");
		airdrop.whitelistWallet(bob);

		// Attempt to whitelist multiple addresses from a non-owner address and expect to revert
		vm.expectRevert("Ownable: caller is not the owner");
		address[] memory wallets = new address[](1);
		wallets[0] = bob;
		airdrop.whitelistWallets(wallets);

		// Attempt to unwhitelist an address from a non-owner address and expect to revert
		vm.expectRevert("Ownable: caller is not the owner");
		airdrop.unwhitelistWallet(alice);
	}
	}