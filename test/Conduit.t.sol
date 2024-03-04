// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {MockInputConduit} from "test/mocks/MockInputConduit.sol";
import {MockOutputConduit} from "test/mocks/MockOutputConduit.sol";
import {MockLiquidityPool} from "test/mocks/MockLiquidityPool.sol";
import {MockBrokenLiquidityPool} from "test/mocks/MockBrokenLiquidityPool.sol";
import {MockPoolManager} from "test/mocks/MockPoolManager.sol";
import {Conduit} from "src/Conduit.sol";
import {ERC20} from "src/token/ERC20.sol";

contract ConduitTest is Test {

    address psm = makeAddr("PSM");
    address urn = makeAddr("Urn");
    address jar = makeAddr("Jar");

    ERC20 dai;
    ERC20 gem;
    ERC20 depositAsset;

    MockOutputConduit outputConduit;
    MockInputConduit urnConduit;
    MockInputConduit jarConduit;

    address operator;
    address withdrawal = makeAddr("Withdrawal");

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
        urnConduit = new MockInputConduit(address(gem), address(urn));
        jarConduit = new MockInputConduit(address(gem), address(jar));

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

    function testPermissions(address anotherWard) public {
        vm.assume(anotherWard != address(this));

        conduit.nope(operator);
        assertEq(conduit.can(operator), 0);
        conduit.hope(operator);
        assertEq(conduit.can(operator), 1);

        conduit.hate(mate);
        assertEq(conduit.may(mate), 0);
        conduit.mate(mate);
        assertEq(conduit.may(mate), 1);

        conduit.rely(anotherWard);
        assertEq(conduit.wards(anotherWard), 1);
        conduit.deny(anotherWard);
        assertEq(conduit.wards(anotherWard), 0);
    }

    function testFile(address anotherWithdrawal, address anotherPool, address anotherPoolManager, bytes32 anotherDepositRecipient) public {
        vm.expectRevert(bytes("AndromedaPaymentConduit/unrecognised-param"));
        conduit.file("withdrawal2", anotherWithdrawal);

        conduit.file("withdrawal", anotherWithdrawal);
        assertEq(conduit.withdrawal(), anotherWithdrawal);

        vm.startPrank(operator);

        vm.expectRevert(bytes("AndromedaPaymentConduit/unrecognised-param"));
        conduit.file("pool2", anotherPool, anotherPoolManager);

        conduit.file("pool", anotherPool, anotherPoolManager);
        assertEq(address(conduit.pool()), anotherPool);
        assertEq(address(conduit.poolManager()), anotherPoolManager);

        vm.expectRevert(bytes("AndromedaPaymentConduit/unrecognised-param"));
        conduit.file("depositRecipient2", anotherDepositRecipient);

        conduit.file("depositRecipient", anotherDepositRecipient);
        assertEq(conduit.depositRecipient(), anotherDepositRecipient);

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
        assertEq(depositAsset.allowance(address(conduit), address(pool)), gemAmount);

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

    function testWithdrawFromPool(address notMate, uint256 gemAmount) public {
        vm.assume(mate != notMate);
        vm.assume(gemAmount > 0);

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
        vm.assume(gemAmount > 0);

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

    function testDepositIntoPoolOverflow(uint256 gemAmount) public {
        vm.assume(gemAmount > type(uint128).max);

        vm.startPrank(operator);
        conduit.file("depositRecipient", depositRecipient);
        vm.stopPrank();

        gem.mint(address(conduit), gemAmount);
        
        vm.startPrank(mate);
        vm.expectRevert(bytes("AndromedaPaymentConduit/uint128-overflow"));
        conduit.depositIntoPool();
    }

    function testClaimRedeem(address notMate, uint256 gemAmount, uint256 shareAmount) public {
        vm.assume(mate != notMate);

        pool.setReturn("redeem", gemAmount);
        pool.setReturn("maxRedeem", shareAmount);
        depositAsset.mint(address(conduit), gemAmount);
        
        vm.expectRevert(bytes("AndromedaPaymentConduit/not-mate"));
        vm.prank(notMate);
        conduit.claimRedeem();
        
        assertEq(depositAsset.balanceOf(address(conduit)), gemAmount);

        vm.startPrank(mate);
        conduit.claimRedeem();

        assertEq(depositAsset.balanceOf(address(conduit)), 0);

        assertEq(pool.values_uint256("redeem_shares"), shareAmount);
        assertEq(pool.values_address("redeem_receiver"), address(conduit));
        assertEq(pool.values_address("redeem_owner"), address(conduit));
    }

    function testRepay() public {
        // todo
    }

    function testRepayBrokenLiquidityPool(uint256 jarRepayAmount, uint256 urnRepayAmount) public {
        jarRepayAmount = bound(jarRepayAmount, 0, type(uint128).max);
        urnRepayAmount = bound(urnRepayAmount, 0, type(uint128).max);

        conduit.file("withdrawal", withdrawal);

        // Liquidity Pool is broken (always reverting)
        MockBrokenLiquidityPool brokenPool = new MockBrokenLiquidityPool();
        vm.prank(operator);
        conduit.file("pool", address(brokenPool), address(poolManager));

        // On-ramp to exchange agent
        gem.mint(address(withdrawal), jarRepayAmount + urnRepayAmount);

        // Send to conduit
        vm.prank(withdrawal);
        gem.transfer(address(conduit), jarRepayAmount + urnRepayAmount);

        assertEq(gem.balanceOf(address(jar)), 0);
        assertEq(gem.balanceOf(address(urn)), 0);

        // Repay to jar & urn
        vm.startPrank(mate);
        conduit.repayToJar(jarRepayAmount);
        conduit.repayToUrn(urnRepayAmount);

        assertEq(gem.balanceOf(address(jar)), jarRepayAmount);
        assertEq(gem.balanceOf(address(urn)), urnRepayAmount);
    }

    function testAuthMint(address notMate, uint256 amount) public {
        vm.assume(mate != notMate);

        vm.expectRevert(bytes("AndromedaPaymentConduit/not-mate"));
        vm.prank(notMate);
        conduit.authMint(amount);
        
        assertEq(depositAsset.balanceOf(address(conduit)), 0);

        vm.startPrank(mate);
        conduit.authMint(amount);

        assertEq(depositAsset.balanceOf(address(conduit)), amount);
    }

    function testAuthLockUnlock(address notMate) public {
        vm.assume(mate != notMate);
        assert(conduit.unlockActive() == false);

        vm.expectRevert(bytes("AndromedaPaymentConduit/not-mate"));
        vm.prank(notMate);
        conduit.unlock();
        assert(conduit.unlockActive() == false);

        vm.prank(mate);
        conduit.unlock();
        assert(conduit.unlockActive() == true);

        vm.expectRevert(bytes("AndromedaPaymentConduit/not-mate"));
        vm.prank(notMate);
        conduit.lock();
        assert(conduit.unlockActive() == true);

        vm.prank(mate);
        conduit.lock();
        assert(conduit.unlockActive() == false);
    }

    function testAuthBurn(address notMate, uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mate != notMate);
        burnAmount = bound(burnAmount, 0, mintAmount);

        vm.startPrank(mate);
        conduit.authMint(mintAmount);
        vm.stopPrank();

        vm.expectRevert(bytes("AndromedaPaymentConduit/not-mate"));
        vm.prank(notMate);
        conduit.authBurn(burnAmount);
        
        assertEq(depositAsset.balanceOf(address(conduit)), mintAmount);

        vm.startPrank(mate);
        conduit.authBurn(burnAmount);

        assertEq(depositAsset.balanceOf(address(conduit)), mintAmount - burnAmount);
    }
}
