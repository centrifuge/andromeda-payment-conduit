// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "./Mock.sol";

interface ERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address user) external returns (uint256 amount);
    function mint(address user, uint256 amount) external;
}

contract MockInputConduit is Mock {
    ERC20Like gem;
    address to;

    constructor(address gem_, address to_) {
        gem = ERC20Like(gem_);
        to = to_;
    }

    function push() public {
        gem.transfer(to, gem.balanceOf(address(this)));
    }

    function setPush(uint256 amount) public {
        gem.mint(address(this), amount);
    }
}
