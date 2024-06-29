// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {Addresses} from "./config/Addresses.sol";
import "../src/rewarders/RewarderFactory.sol";
import "../src/rewarders/BribeRewarder.sol";

contract CoreDeployer is Script {
    function setUp() public {}

    function run() public returns (BribeRewarder rewarderImplementation) {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        console.log("Deployer address: %s", deployer);

        vm.broadcast(deployer);
        rewarderImplementation = new BribeRewarder(Addresses.PROXY_VOTER_TESTNET);

        RewarderFactory factory = RewarderFactory(Addresses.PROXY_REWARDER_FACTORY_TESTNET);

        vm.broadcast(deployer);
        factory.setRewarderImplementation(
            IRewarderFactory.RewarderType.BribeRewarder, IRewarder(address(rewarderImplementation))
        );
    }
}
