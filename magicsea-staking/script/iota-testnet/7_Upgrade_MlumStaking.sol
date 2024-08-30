// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import "../../src/transparent/TransparentUpgradeableProxy2Step.sol";
import "../../src/transparent/ProxyAdmin2Step.sol";

import {ILum} from "../../src/interfaces/ILum.sol";
import {IVoter} from "../../src/interfaces/IVoter.sol";
import {MlumStaking} from "../../src/MlumStaking.sol";
import {IMlumStaking} from "../../src/interfaces/IMlumStaking.sol";

import {Addresses} from "./config/Addresses.sol";


contract Deploy is Script {
    uint256 pk;
    address deployer;

    function run() public {
        pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        vm.createSelectFork("iota_testnet");

        vm.broadcast(pk);
        address stakingImplementation =
            address(
                new MlumStaking(IERC20(Addresses.MLUM_TESTNET), IERC20(Addresses.REWARD_IOTA_TOKEN_TESTNET))
            );
        console.log("MlumStakingImplementation --->", stakingImplementation);

        // upgrate
        ProxyAdmin2Step proxyAdmin = ProxyAdmin2Step(Addresses.PROXY_ADMIN_TESTNET);

        vm.broadcast(pk);
        TransparentUpgradeableProxy2Step mlumStakingProxy = new TransparentUpgradeableProxy2Step(
                stakingImplementation,
                proxyAdmin,
                abi.encodeWithSelector(MlumStaking.initialize.selector, deployer)
            );

        console.log("MlumStakingProxy --->", address(mlumStakingProxy));
    }
}


contract Upgrade is Script {
    uint256 pk;
    address deployer;

    function run() public {
        pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        vm.createSelectFork("iota_testnet");

        vm.broadcast(pk);
        MlumStaking stakingImplementation =
            new MlumStaking(IERC20(Addresses.MLUM_TESTNET), IERC20(Addresses.REWARD_IOTA_TOKEN_TESTNET));
        console.log("MlumStakingImplementation --->", address(stakingImplementation));

        // upgrate
        ProxyAdmin2Step proxyAdmin = ProxyAdmin2Step(Addresses.PROXY_ADMIN_TESTNET);

        vm.broadcast(pk);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(Addresses.PROXY_MLUM_STAKING_TESTNET),
            address(stakingImplementation),
            "" // abi.encodeWithSelector(MlumStaking.initialize.selector, deployer)
        );
    }
}


contract SetMinimumLockDuration is Script {

    uint256 pk;
    address deployer;

    function run() public {
        pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        vm.createSelectFork("iota_testnet");



        vm.startBroadcast(pk);
        MlumStaking staking = MlumStaking(Addresses.PROXY_MLUM_STAKING_TESTNET);

        console.log("MinimumLockDuration before --->", staking.getMinimumLockDuration());

        staking.setMinimumLockDuration(7 days);

        vm.stopBroadcast();
    }
}