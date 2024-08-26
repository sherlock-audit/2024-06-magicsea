// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {MlumStaking} from "../../src/MlumStaking.sol";

contract CoreDeployer is Script {
    function setUp() public {}

    address internal mlum;
    address internal rewardToken;

    address admin = 0xdeD212B8BAb662B98f49e757CbB409BB7808dc10;

    function run() public {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        console.log("Deployer address: %s", deployer);

        if (block.chainid == 1073) {
            mlum = 0x699F410Af72905b736B171e039241f0E692D66Ea;
            rewardToken = 0x4f67E9B8e1DA5aBcb52CAb8bf5cB27034393718B;
        }

        vm.broadcast(deployer);
        MlumStaking staking = new MlumStaking(ERC20(mlum), ERC20(rewardToken));
        staking.initialize(deployer);

        console.log("MlumStaking deployed --->", address(staking));
    }
}
