// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "./Mock.sol";

contract MockBrokenLiquidityPool is Mock {
    constructor() {}

    function requestDeposit(uint256, address, address, bytes memory) public pure returns (uint256) {
        revert();
    }

    function deposit(uint256, address) public pure returns (uint256) {
        revert();
    }

    function maxDeposit(address) public pure returns (uint256) {
        revert();
    }
}
