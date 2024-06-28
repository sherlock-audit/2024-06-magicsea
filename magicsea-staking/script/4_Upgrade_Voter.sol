// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy} from "../src/transparent/TransparentUpgradeableProxy2Step.sol";
import "../src/transparent/ProxyAdmin2Step.sol";

import {ILum} from "../src/interfaces/ILum.sol";
import {IVoter} from "../src/interfaces/IVoter.sol";
import {IMlumStaking} from "../src/interfaces/IMlumStaking.sol";
import {IRewarderFactory} from "../src/interfaces/IRewarderFactory.sol";
import {IMasterChefRewarder} from "../src/interfaces/IMasterChefRewarder.sol";

import {Addresses} from "./config/Addresses.sol";

import "../src/Voter.sol";

contract Deployer is Script {
    uint256 pk;
    address deployer;

    function run() public {
        pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        //vm.createSelectFork("iota_testnet");

        vm.broadcast(pk);
        Voter voterImplementation = new Voter(
            IMasterChef(Addresses.PROXY_MASTERCHEF_TESTNET), // proxy
            IMlumStaking(Addresses.PROXY_MLUM_STAKING_TESTNET), // proxy
            IRewarderFactory(Addresses.PROXY_REWARDER_FACTORY_TESTNET) // proxy
        );

        console.log("VoterImplementation --->", address(voterImplementation));

        // upgrate
        ProxyAdmin2Step proxyAdmin = ProxyAdmin2Step(Addresses.PROXY_ADMIN_TESTNET);

        vm.broadcast(pk);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(Addresses.PROXY_VOTER_TESTNET), address(voterImplementation), ""
        );
    }
}

contract SetVotingDuration is Script {
    uint256 pk;
    address deployer;
    
    function run() public {
        pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        Voter voter = Voter(Addresses.PROXY_VOTER_TESTNET);

        vm.broadcast(deployer);
        voter.updatePeriodDuration(1 weeks);
    }
}
