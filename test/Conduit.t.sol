// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {MockInputConduit} from "test/mocks/MockInputConduit.sol";
import {MockOutputConduit} from "test/mocks/MockOutputConduit.sol";
import {MockLiquidityPool} from "test/mocks/MockLiquidityPool.sol";
import {MockPoolManager} from "test/mocks/MockPoolManager.sol";
import {Conduit} from "src/Conduit.sol";
import {ERC20} from "src/token/ERC20.sol";

contract ConduitTest is Test {

    address psm = makeAddr("PSM");

    ERC20 dai;
    ERC20 gem;
    ERC20 depositAsset;

    MockOutputConduit outputConduit;
    MockInputConduit urnConduit;
    MockInputConduit jarConduit;

    address operator;
    bytes32 depositRecipient;
    MockLiquidityPool pool;
    MockPoolManager poolManager;

    address mate = makeAddr("Mate");
    Conduit conduit;

    function setUp() public {
        dai = new ERC20("DAI", "DAI", 18);
        gem = new ERC20("USD Coin", "USDC", 6);
        depositAsset = new ERC20("Andromeda USDC Deposit", "andrUSDC", 6);

        outputConduit = new MockOutputConduit(address(gem));
        urnConduit = new MockInputConduit(address(gem));
        jarConduit = new MockInputConduit(address(gem));

        gem.rely(address(outputConduit));

        conduit = new Conduit(psm, address(dai), address(gem), address(depositAsset), address(outputConduit), address(urnConduit), address(jarConduit));
        depositAsset.rely(address(conduit));
        conduit.hope(operator);

        conduit.mate(mate);

        pool = new MockLiquidityPool();
        poolManager = new MockPoolManager();
        depositRecipient = "DepositRecipient";
        vm.prank(operator);
        conduit.file("pool", address(pool), address(poolManager));

        vm.label(address(dai), "DAI");
        vm.label(address(gem), "Gem");
        vm.label(address(depositAsset), "depositAsset");
        vm.label(address(outputConduit), "OutputConduit");
        vm.label(address(urnConduit), "UrnConduit");
        vm.label(address(jarConduit), "JarConduit");
        vm.label(address(conduit), "Conduit");
    }

    function testWardSetup(address notDeployer) public {
        vm.assume(address(this) != notDeployer);

        assertEq(conduit.wards(address(this)), 1);
        assertEq(conduit.wards(notDeployer), 0);
    }

    function testRequestDeposit(address notMate, uint256 gemAmount) public {
        vm.assume(mate != notMate);
        assertEq(conduit.may(notMate), 0);

        vm.expectRevert(bytes("AndromedaPaymentConduit/not-mate"));
        vm.prank(notMate);
        conduit.requestDeposit();

        outputConduit.setPush(gemAmount);
        assertEq(gem.balanceOf(address(outputConduit)), gemAmount);
        assertEq(gem.balanceOf(address(conduit)), 0);
        assertEq(depositAsset.balanceOf(address(conduit)), 0);

        vm.startPrank(mate);
        conduit.requestDeposit();

        assertEq(gem.balanceOf(address(outputConduit)), 0);
        assertEq(gem.balanceOf(address(conduit)), gemAmount);
        assertEq(depositAsset.balanceOf(address(conduit)), gemAmount);

        assertEq(pool.values_uint256("requestDeposit_assets"), gemAmount);
        assertEq(pool.values_address("requestDeposit_receiver"), address(conduit));
        assertEq(pool.values_address("requestDeposit_owner"), address(conduit));
        assertEq(pool.values_bytes("requestDeposit_data"), "");
    }

    function testClaimDeposit(uint256 gemAmount) public {
        outputConduit.setPush(gemAmount);
        pool.setReturn("maxDeposit", gemAmount);
        
        vm.prank(mate);
        conduit.requestDeposit();
        
        conduit.claimDeposit();

        assertEq(pool.values_uint256("deposit_assets"), gemAmount);
        assertEq(pool.values_address("deposit_receiver"), address(conduit));
    }

    function testWithdrawFromPool(address notMate, address withdrawal, uint256 gemAmount) public {
        vm.assume(mate != notMate);
        vm.assume(withdrawal != address(0));

        outputConduit.setPush(gemAmount);
        pool.setReturn("maxDeposit", gemAmount);
        
        vm.expectRevert(bytes("AndromedaPaymentConduit/not-mate"));
        vm.prank(notMate);
        conduit.withdrawFromPool();
        
        vm.prank(mate);
        vm.expectRevert(bytes("AndromedaPaymentConduit/withdrawal-is-zero"));
        conduit.withdrawFromPool();

        conduit.file("withdrawal", withdrawal);
        vm.startPrank(mate);
        conduit.requestDeposit();

        assertEq(depositAsset.balanceOf(address(conduit)), gemAmount);
        assertEq(depositAsset.totalSupply(), gemAmount);
        assertEq(gem.balanceOf(address(conduit)), gemAmount);
        assertEq(gem.balanceOf(address(withdrawal)), 0);

        conduit.withdrawFromPool();

        assertEq(depositAsset.balanceOf(address(conduit)), 0);
        assertEq(depositAsset.totalSupply(), 0);
        assertEq(gem.balanceOf(address(conduit)), 0);
        assertEq(gem.balanceOf(address(withdrawal)), gemAmount);
    }

    function testRequestRedeem(address notMate, uint256 gemAmount) public {
        vm.assume(mate != notMate);

        outputConduit.setPush(gemAmount);
        pool.setReturn("maxDeposit", gemAmount);
        conduit.file("withdrawal", makeAddr("Withdrawal"));

        vm.startPrank(mate);
        conduit.requestDeposit();
        conduit.withdrawFromPool();
        vm.stopPrank();

        // Assumes price = 1.0
        uint256 shareAmount = gemAmount;

        vm.expectRevert(bytes("AndromedaPaymentConduit/not-mate"));
        vm.prank(notMate);
        conduit.requestRedeem(shareAmount);
        
        vm.startPrank(mate);
        conduit.requestRedeem(shareAmount);
        assertEq(pool.values_uint256("requestRedeem_shares"), shareAmount);
        assertEq(pool.values_address("requestRedeem_receiver"), address(conduit));
        assertEq(pool.values_address("requestRedeem_owner"), address(conduit));
        assertEq(pool.values_bytes("requestRedeem_data"), "");
    }

    function testDepositIntoPool(address notMate, uint256 gemAmount) public {
        vm.assume(mate != notMate);
        gemAmount = bound(gemAmount, 0, type(uint128).max);

        vm.expectRevert(bytes("AndromedaPaymentConduit/not-mate"));
        vm.prank(notMate);
        conduit.depositIntoPool();
        
        vm.startPrank(mate);
        vm.expectRevert(bytes("AndromedaPaymentConduit/deposit-recipient-is-zero"));
        conduit.depositIntoPool();
        assertEq(gem.balanceOf(address(conduit)), 0);
        assertEq(depositAsset.balanceOf(address(conduit)), 0);
        vm.stopPrank();

        vm.startPrank(operator);
        conduit.file("depositRecipient", depositRecipient);
        vm.stopPrank();

        gem.mint(address(conduit), gemAmount);
        assertEq(gem.balanceOf(address(conduit)), gemAmount);
        assertEq(depositAsset.balanceOf(address(conduit)), 0);
        
        vm.startPrank(mate);
        conduit.depositIntoPool();
        assertEq(gem.balanceOf(address(conduit)), gemAmount);
        assertEq(depositAsset.balanceOf(address(conduit)), gemAmount);

        assertEq(poolManager.values_address("transfer_currency"), address(depositAsset));
        assertEq(poolManager.values_bytes32("transfer_recipient"), depositRecipient);
        assertEq(poolManager.values_uint128("transfer_amount"), uint128(gemAmount));
    }
}
