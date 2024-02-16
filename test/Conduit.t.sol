// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {MockInputConduit} from "test/mocks/MockInputConduit.sol";
import {MockOutputConduit} from "test/mocks/MockOutputConduit.sol";
import {MockLiquidityPool} from "test/mocks/MockLiquidityPool.sol";
import {Conduit} from "src/Conduit.sol";
import {ERC20} from "src/token/ERC20.sol";

contract ConduitTest is Test {

    address psm = makeAddr("PSM");

    ERC20 dai;
    ERC20 gem;
    ERC20 depositToken;

    MockOutputConduit outputConduit;
    MockInputConduit urnConduit;
    MockInputConduit jarConduit;

    address operator;
    MockLiquidityPool pool;

    address mate;
    Conduit conduit;

    function setUp() public {
        dai = new ERC20("DAI", "DAI", 18);
        gem = new ERC20("USD Coin", "USDC", 6);
        depositToken = new ERC20("Andromeda USDC Deposit", "andrUSDC", 6);

        outputConduit = new MockOutputConduit(address(gem));
        urnConduit = new MockInputConduit(address(gem));
        jarConduit = new MockInputConduit(address(gem));

        gem.rely(address(outputConduit));

        conduit = new Conduit(psm, address(dai), address(gem), address(depositToken), address(outputConduit), address(urnConduit), address(jarConduit));
        depositToken.rely(address(conduit));
        conduit.hope(operator);

        conduit.mate(mate);

        pool = new MockLiquidityPool();
        // TODO: poolManager
        vm.prank(operator);
        conduit.file("pool", address(pool), address(0));

        vm.label(address(dai), "DAI");
        vm.label(address(gem), "Gem");
        vm.label(address(depositToken), "DepositToken");
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
        assertEq(depositToken.balanceOf(address(conduit)), 0);

        vm.startPrank(mate);
        conduit.requestDeposit();

        assertEq(gem.balanceOf(address(outputConduit)), 0);
        assertEq(gem.balanceOf(address(conduit)), gemAmount);
        assertEq(depositToken.balanceOf(address(conduit)), gemAmount);

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
}
