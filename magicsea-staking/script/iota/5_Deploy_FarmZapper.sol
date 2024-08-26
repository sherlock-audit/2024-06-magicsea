// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {IMasterChef} from "../../src/interfaces/IMasterChef.sol";
import {FarmZapper} from "../../src/FarmZapper.sol";
import {Addresses} from "./config/Addresses.sol";

contract CoreDeployer is Script {
    function setUp() public {}

    function run() public returns (FarmZapper farmZapper) {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        console.log("Deployer address: %s", deployer);

        vm.broadcast(deployer);
        farmZapper = new FarmZapper(
            Addresses.ROUTER_V1_MAINNET, Addresses.PROXY_MASTERCHEF_MAINNET, Addresses.WNATIVE_MAINNET, 1000, deployer
        );

        console.log("FarmZapper address: %s", address(farmZapper));

        console.log("Update Masterchef trustee");
        vm.broadcast(deployer);
        IMasterChef(Addresses.PROXY_MASTERCHEF_MAINNET).setTrustee(address(farmZapper));
    }
}
