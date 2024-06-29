// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

/**
 * Sends tokens from source (operator) wallet to Lock Staking pool
 */
contract FeeSender is Script {
    using SafeERC20 for IERC20;

    address constant TESTNET_POOL = 0x97635fc30c89D35F60ae997081cE321251406239;
    address constant TESTNET_FEE_TOKEN = 0x4f67E9B8e1DA5aBcb52CAb8bf5cB27034393718B; // USDC
    uint256 constant TESTNET_SEND_AMOUNT = 2e6;

    function run() public {
        address targetPool;
        uint256 amount;
        IERC20 feeToken;

        if (block.chainid == 1073) {
            targetPool = TESTNET_POOL;
            amount = TESTNET_SEND_AMOUNT;
            feeToken = IERC20(TESTNET_FEE_TOKEN);
        }

        address operator = vm.rememberKey(vm.envUint("FEE_OPERATOR_PRIVATE_KEY"));

        console.log("Operator: ", operator);

        // check if operator wallet as enough balance
        if (feeToken.balanceOf(operator) >= amount) {
            console.log("Sending amount %s to %s", amount, targetPool);

            vm.startBroadcast(operator);

            feeToken.approve(targetPool, amount);
            feeToken.safeTransfer(targetPool, amount);

            vm.stopBroadcast();
        } else {
            console.log("Not enough balance");
        }
    }
}
