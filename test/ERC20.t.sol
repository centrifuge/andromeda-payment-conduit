// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {ERC20} from "src/token/ERC20.sol";
import "forge-std/Test.sol";

/// @author Modified from https://github.com/makerdao/xdomain-dss/blob/master/src/test/Dai.t.sol
contract ERC20Test is Test {
    ERC20 token;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setUp() public {
        token = new ERC20("Name", "SYMBOL", 18);
    }

    function testMint() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(0xBEEF), 1e18);
        token.mint(address(0xBEEF), 1e18);

        assertEq(token.totalSupply(), 1e18);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testMintBadAddress() public {
        vm.expectRevert("ERC20/invalid-address");
        token.mint(address(0), 1e18);
        vm.expectRevert("ERC20/invalid-address");
        token.mint(address(token), 1e18);
    }

    function testBurn() public {
        token.mint(address(0xBEEF), 1e18);
        token.rely(address(0xBEEF));

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0xBEEF), address(0), 0.9e18);
        vm.prank(address(0xBEEF));
        token.burn(address(0xBEEF), 0.9e18);

        assertEq(token.totalSupply(), 1e18 - 0.9e18);
        assertEq(token.balanceOf(address(0xBEEF)), 0.1e18);
    }

    function testBurnWithAllowance() public {
        address from = address(0xABCD);

        token.mint(address(0xBEEF), 1e18);
        token.rely(address(from));

        vm.prank(address(from));
        vm.expectRevert(bytes("ERC20/insufficient-allowance"));
        token.burn(address(0xBEEF), 0.9e18);
        
        vm.prank(address(0xBEEF));
        token.approve(address(from), 1e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0xBEEF), address(0), 0.9e18);
        vm.prank(address(from));
        token.burn(address(0xBEEF), 0.9e18);
    }

    function testApprove() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(address(this), address(0xBEEF), 1e18);
        assertTrue(token.approve(address(0xBEEF), 1e18));

        assertEq(token.allowance(address(this), address(0xBEEF)), 1e18);
    }

    function testTransfer() public {
        token.mint(address(this), 1e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), address(0xBEEF), 1e18);
        assertTrue(token.transfer(address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferBadAddress() public {
        token.mint(address(this), 1e18);

        vm.expectRevert("ERC20/invalid-address");
        token.transfer(address(0), 1e18);
        vm.expectRevert("ERC20/invalid-address");
        token.transfer(address(token), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        token.mint(from, 1e18);

        vm.prank(from);
        token.approve(address(this), 1e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, address(0xBEEF), 1e18);
        assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.allowance(from, address(this)), 0);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFromBadAddress() public {
        token.mint(address(this), 1e18);

        vm.expectRevert("ERC20/invalid-address");
        token.transferFrom(address(this), address(0), 1e18);
        vm.expectRevert("ERC20/invalid-address");
        token.transferFrom(address(this), address(token), 1e18);
    }

    function testInfiniteApproveTransferFrom() public {
        address from = address(0xABCD);

        token.mint(from, 1e18);

        vm.prank(from);
        vm.expectEmit(true, true, true, true);
        emit Approval(from, address(this), type(uint256).max);
        token.approve(address(this), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, address(0xBEEF), 1e18);
        assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.allowance(from, address(this)), type(uint256).max);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferInsufficientBalance() public {
        token.mint(address(this), 0.9e18);
        vm.expectRevert("ERC20/insufficient-balance");
        token.transfer(address(0xBEEF), 1e18);
    }

    function testTransferFromInsufficientAllowance() public {
        address from = address(0xABCD);

        token.mint(from, 1e18);

        vm.prank(from);
        token.approve(address(this), 0.9e18);

        vm.expectRevert("ERC20/insufficient-allowance");
        token.transferFrom(from, address(0xBEEF), 1e18);
    }

    function testTransferFromInsufficientBalance() public {
        address from = address(0xABCD);

        token.mint(from, 0.9e18);

        vm.prank(from);
        token.approve(address(this), 1e18);

        vm.expectRevert("ERC20/insufficient-balance");
        token.transferFrom(from, address(0xBEEF), 1e18);
    }

    function testMint(address to, uint256 amount) public {
        if (to != address(0) && to != address(token)) {
            vm.expectEmit(true, true, true, true);
            emit Transfer(address(0), to, amount);
        } else {
            vm.expectRevert("ERC20/invalid-address");
        }
        token.mint(to, amount);

        if (to != address(0) && to != address(token)) {
            assertEq(token.totalSupply(), amount);
            assertEq(token.balanceOf(to), amount);
        }
    }

    function testBurn(address from, uint256 mintAmount, uint256 burnAmount) public {
        if (from == address(0) || from == address(token)) return;

        burnAmount = bound(burnAmount, 0, mintAmount);

        token.mint(from, mintAmount);
        token.rely(from);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, address(0), burnAmount);
        vm.prank(from);
        token.burn(from, burnAmount);

        assertEq(token.totalSupply(), mintAmount - burnAmount);
        assertEq(token.balanceOf(from), mintAmount - burnAmount);
    }

    function testApprove(address to, uint256 amount) public {
        vm.expectEmit(true, true, true, true);
        emit Approval(address(this), to, amount);
        assertTrue(token.approve(to, amount));

        assertEq(token.allowance(address(this), to), amount);
    }

    function testTransfer(address to, uint256 amount) public {
        if (to == address(0) || to == address(token)) return;

        token.mint(address(this), amount);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), to, amount);
        assertTrue(token.transfer(to, amount));
        assertEq(token.totalSupply(), amount);

        if (address(this) == to) {
            assertEq(token.balanceOf(address(this)), amount);
        } else {
            assertEq(token.balanceOf(address(this)), 0);
            assertEq(token.balanceOf(to), amount);
        }
    }

    function testTransferFrom(address to, uint256 approval, uint256 amount) public {
        if (to == address(0) || to == address(token)) return;

        amount = bound(amount, 0, approval);

        address from = address(0xABCD);

        token.mint(from, amount);

        vm.prank(from);
        token.approve(address(this), approval);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, amount);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.totalSupply(), amount);

        uint256 app = from == address(this) || approval == type(uint256).max ? approval : approval - amount;
        assertEq(token.allowance(from, address(this)), app);

        if (from == to) {
            assertEq(token.balanceOf(from), amount);
        } else {
            assertEq(token.balanceOf(from), 0);
            assertEq(token.balanceOf(to), amount);
        }
    }

    function testBurnInsufficientBalance(address to, uint256 mintAmount, uint256 burnAmount) public {
        if (to == address(0) || to == address(token)) return;

        if (mintAmount == type(uint256).max) mintAmount -= 1;
        burnAmount = bound(burnAmount, mintAmount + 1, type(uint256).max);

        token.mint(to, mintAmount);
        vm.expectRevert("ERC20/insufficient-balance");
        token.burn(to, burnAmount);
    }

    function testTransferInsufficientBalance(address to, uint256 mintAmount, uint256 sendAmount) public {
        if (to == address(0) || to == address(token)) return;

        if (mintAmount == type(uint256).max) mintAmount -= 1;
        sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

        token.mint(address(this), mintAmount);
        vm.expectRevert("ERC20/insufficient-balance");
        token.transfer(to, sendAmount);
    }

    function testTransferFromInsufficientAllowance(address to, uint256 approval, uint256 amount) public {
        if (to == address(0) || to == address(token)) return;

        if (approval == type(uint256).max) approval -= 1;
        amount = bound(amount, approval + 1, type(uint256).max);

        address from = address(0xABCD);

        token.mint(from, amount);

        vm.prank(from);
        token.approve(address(this), approval);

        vm.expectRevert("ERC20/insufficient-allowance");
        token.transferFrom(from, to, amount);
    }

    function testTransferFromInsufficientBalance(address to, uint256 mintAmount, uint256 sendAmount) public {
        if (to == address(0) || to == address(token)) return;

        if (mintAmount == type(uint256).max) mintAmount -= 1;
        sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

        address from = address(0xABCD);

        token.mint(from, mintAmount);

        vm.prank(from);
        token.approve(address(this), sendAmount);

        vm.expectRevert("ERC20/insufficient-balance");
        token.transferFrom(from, to, sendAmount);
    }
}
