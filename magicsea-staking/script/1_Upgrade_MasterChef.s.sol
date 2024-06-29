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

import "../src/MasterChefV2.sol";

/**
 *
 * proxyAdmin: contract ProxyAdmin2Step 0x2D52467D074B3590760831af816046471a81bf3a
 * lumMock: contract LumMock 0xC4Cc4703bbB57AA16cEE22888Ad71ECdDb0BDC32
 * rewarders: contract IBaseRewarder[2] [0x159a52634AEBad078343eC4AAb01e3738e3AE11E, 0x4bC738f2Db3F508644FD2A9A57e67201e35B9fd0]
 * proxies: struct FarmDeployer.Addresses Addresses({ rewarderFactory: 0x5a9226fFFe28aBa3c744B93753EB4b6EF94f60A2, masterChef: 0xC382eDeec3642DCf86e7075E46cfF7c345069b86, mlumStaking: 0x6f33A1f5AC574DDE68114CB7553E60013f5fDA55, voter: 0xdD693b9F810D0AEE1b3B74C50D3c363cE45CEC0C })
 * implementations: struct FarmDeployer.Addresses Addresses({ rewarderFactory: 0xfD3e5a520B745bdBCd3d29bf1ea068CCB5388A50, masterChef: 0xBE4047B0461925aDaD27B62A6836b7c8FE9A0142, mlumStaking: 0x6b20B00D9896397C7649A9351308546bFDd14731, voter: 0xFB7D8d8eDE596DdaFA7521a419Dbbb17a5be7c00 })
 *
 * == Logs ==
 *   Proxy Admin --> 0x2D52467D074B3590760831af816046471a81bf3a
 *   Lum Address --> 0xC4Cc4703bbB57AA16cEE22888Ad71ECdDb0BDC32
 */
contract Deployer is Script {
    uint256 pk;
    address deployer;

    function run() public {
        pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        vm.broadcast(pk);
        MasterChef masterChefImplementation = new MasterChef(
            ILum(Addresses.LUM_TESTNET),
            IVoter(Addresses.PROXY_VOTER_TESTNET), // proxy
            IRewarderFactory(Addresses.PROXY_REWARDER_FACTORY_TESTNET), // proxy
            address(0),
            0.02e18
        );

        console.log("MasterChefImplemantion --->", address(masterChefImplementation));

        // upgrate
        ProxyAdmin2Step proxyAdmin = ProxyAdmin2Step(Addresses.PROXY_ADMIN_TESTNET);

        vm.broadcast(pk);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(Addresses.PROXY_MASTERCHEF_TESTNET), 
            address(masterChefImplementation), 
            abi.encodeWithSelector(MasterChef.initialize.selector, deployer, Addresses.TREASURY_TESTNET)
        );

        IMasterChef masterChef = IMasterChef(Addresses.PROXY_MASTERCHEF_TESTNET);
        console.log("MasterChef Farms -->", masterChef.getNumberOfFarms());
        console.log("MasterChef mintLum -->", MasterChef(address(masterChef)).getMintLumFlag());
    }
}

contract AddFarm is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer --> ", deployer);
        MasterChef masterChef = MasterChef(Addresses.PROXY_MASTERCHEF_TESTNET);

        IERC20 lpToken = IERC20(0x8d7bD0dA2F2172027C1FeFc335a1594238C76A20); // lum-usdc

        vm.broadcast(pk);
        masterChef.add(lpToken, IMasterChefRewarder(address(0)));
    }
}

contract SetVoter is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer --> ", deployer);
        MasterChef masterChef = MasterChef(Addresses.PROXY_MASTERCHEF_TESTNET);

        vm.broadcast(pk);
        masterChef.setVoter(IVoter(Addresses.PROXY_VOTER_TESTNET));

        console.log("Voter --> ", address(masterChef.getVoter()));
    }
}

contract SetEmission is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer --> ", deployer);
        MasterChef masterChef = MasterChef(Addresses.PROXY_MASTERCHEF_TESTNET);

        vm.broadcast(pk);
        masterChef.setLumPerSecond(1e18); // 1 LUM per second (1e18 wei)

        console.log("Emission --> ", masterChef.getLumPerSecond());
    }
}

contract SetMintLumFlag is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer --> ", deployer);
        MasterChef masterChef = MasterChef(Addresses.PROXY_MASTERCHEF_TESTNET);

        vm.broadcast(pk);
        masterChef.setMintLum(false);

        console.log("Mint LUM Flag --> ", masterChef.getMintLumFlag());
    }
}