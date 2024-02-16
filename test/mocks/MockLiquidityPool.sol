// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "./Mock.sol";

contract MockLiquidityPool is Mock {
    constructor() {}

    function requestDeposit(uint256 assets, address receiver, address owner, bytes memory data)
        public
        returns (uint256)
    {
        values_uint256["requestDeposit_assets"] = assets;
        values_address["requestDeposit_receiver"] = receiver;
        values_address["requestDeposit_owner"] = owner;
        values_bytes["requestDeposit_data"] = data;

        return 0;
    }

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        values_uint256["deposit_assets"] = assets;
        values_address["deposit_receiver"] = receiver;

        return values_uint256_return["deposit"];
    }

    function maxDeposit(address /* owner */ ) public view returns (uint256 maxAssets) {
        maxAssets = values_uint256_return["maxDeposit"];
    }
}
