// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy} from "../../src/transparent/TransparentUpgradeableProxy2Step.sol";
import "../../src/transparent/ProxyAdmin2Step.sol";

import {ILum} from "../../src/interfaces/ILum.sol";
import {IVoter} from "../../src/interfaces/IVoter.sol";
import {IMlumStaking} from "../../src/interfaces/IMlumStaking.sol";
import {IRewarderFactory} from "../../src/interfaces/IRewarderFactory.sol";
import {IMasterChefRewarder} from "../../src/interfaces/IMasterChefRewarder.sol";

import "../../src/MasterChefV2.sol";

import "../../src/FarmLens.sol";

import {Addresses} from "./config/Addresses.sol";

contract Deployer is Script {
    function run() public returns (FarmLens farmLens) {
        vm.createSelectFork("iota");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer -->", deployer);

        vm.broadcast(pk);
        farmLens = new FarmLens(
            IMasterChef(Addresses.PROXY_MASTERCHEF_MAINNET),
            IVoter(Addresses.PROXY_VOTER_MAINNET),
            IMlumStaking(Addresses.PROXY_MLUM_STAKING_MAINNET)
        );
    }
}
