// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "./Mock.sol";

contract MockPoolManager is Mock {
    constructor() {}

    function transfer(address currency, bytes32 recipient, uint128 amount) external {
        values_address["transfer_currency"] = currency;
        values_bytes32["transfer_recipient"] = recipient;
        values_uint128["transfer_amount"] = amount;
    }
}
