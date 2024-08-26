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

import {Addresses} from "./config/Addresses.sol";

import "../../src/MasterChefV2.sol";

contract Deployer is Script {
    uint256 pk;
    address deployer;

    function run() public {
        pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        vm.createSelectFork("iota");

        vm.broadcast(pk);
        MasterChef masterChefImplementation = new MasterChef(
            ILum(Addresses.LUM_MAINNET),
            IRewarderFactory(Addresses.PROXY_REWARDER_FACTORY_MAINNET), // proxy
            Addresses.LB_HOOKS_MANAGER,
            0
        );

        console.log("MasterChefImplemantion --->", address(masterChefImplementation));

        // upgrate
        ProxyAdmin2Step proxyAdmin = ProxyAdmin2Step(Addresses.PROXY_ADMIN_MAINNET);

        vm.broadcast(pk);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(Addresses.PROXY_MASTERCHEF_MAINNET),
            address(masterChefImplementation),
            "" // abi.encodeWithSelector(MasterChef.initialize.selector, deployer, Addresses.TREASURY_TESTNET)
        );

        IMasterChef masterChef = IMasterChef(Addresses.PROXY_MASTERCHEF_MAINNET);
        console.log("MasterChef Farms -->", masterChef.getNumberOfFarms());
        console.log("MasterChef mintLum -->", MasterChef(address(masterChef)).getMintLumFlag());

        console.log("MasterChef mintLum -->", MasterChef(address(masterChef)).getTotalDeposit(1));
    }
}

contract AddFarm is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer --> ", deployer);
        // MasterChef masterChef = MasterChef(Addresses.PROXY_MASTERCHEF_MAINNET);
    }
}

contract SetVoter is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer --> ", deployer);
        MasterChef masterChef = MasterChef(Addresses.PROXY_MASTERCHEF_MAINNET);

        vm.broadcast(pk);
        masterChef.setVoter(IVoter(Addresses.PROXY_VOTER_MAINNET));

        console.log("Voter --> ", address(masterChef.getVoter()));
    }
}

contract SetEmission is Script {
    uint96 internal constant EMISSIONS_PER_SECOND = 0.06148e18;

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer --> ", deployer);
        MasterChef masterChef = MasterChef(Addresses.PROXY_MASTERCHEF_MAINNET);

        IVoter voter = IVoter(Addresses.PROXY_VOTER_MAINNET);

        console.log(voter.getTotalWeight());

        vm.startBroadcast(pk);

        masterChef.updateAll(voter.getTopPoolIds());
        masterChef.setLumPerSecond(EMISSIONS_PER_SECOND);

        vm.stopBroadcast();
        console.log("Emission --> ", masterChef.getLumPerSecond());
    }
}
