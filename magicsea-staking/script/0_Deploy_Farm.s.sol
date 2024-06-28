// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import "../src/transparent/TransparentUpgradeableProxy2Step.sol";
import "../src/transparent/ProxyAdmin2Step.sol";
import "../src/rewarders/RewarderFactory.sol";
import "../src/rewarders/MasterChefRewarder.sol";
import "../src/rewarders/BribeRewarder.sol";
import "../src/MasterChefV2.sol";
import "../src/Voter.sol";
import "../src/mocks/LumMock.sol";

import "../src/MlumStaking.sol";

import {ILum} from "../src/interfaces/ILum.sol";
import {IVoter} from "../src/interfaces/IVoter.sol";
import {IMlumStaking} from "../src/interfaces/IMlumStaking.sol";
import {IRewarderFactory} from "../src/interfaces/IRewarderFactory.sol";

contract FarmDeployer is Script {
    address private MLUM_SHIMMER_TESTNET = 0x699F410Af72905b736B171e039241f0E692D66Ea;
    address private REWARD_SHIMMER_TOKEN_TESTNET = 0x4f67E9B8e1DA5aBcb52CAb8bf5cB27034393718B;

    address private MLUM_IOTA_TESTNET = 0x408ba8dea8b514cc24F81e72795FC3DdbcA8Dbb5;
    address private REWARD_IOTA_TOKEN_TESTNET = 0x24b972796274D255b84c2B36e8a29bdAAdb65206;

    address private TREASURY_TESTNET = 0xE3F132867fC5cbb95D21C53c00647E8e7Cd6CF97;

    struct Addresses {
        address rewarderFactory;
        address masterChef;
        address mlumStaking;
        address voter;
    }

    mapping(IRewarderFactory.RewarderType => IBaseRewarder) _implementations;

    uint256 nonce;

    uint256 pk;
    address deployer;

    function run()
        public
        returns (
            ProxyAdmin2Step proxyAdmin,
            LumMock lumMock,
            IBaseRewarder[2] memory rewarders,
            Addresses memory proxies,
            Addresses memory implementations
        )
    {
        address mlum;
        address rewardToken;
        if (block.chainid == 1075) {
            mlum = MLUM_IOTA_TESTNET;
            rewardToken = REWARD_IOTA_TOKEN_TESTNET;
        }

        pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        nonce = vm.getNonce(deployer);

        address proxyAdminAddress = vm.computeCreateAddress(deployer, nonce++);
        address lumAddress = vm.computeCreateAddress(deployer, nonce++);

        console.log("Proxy Admin -->", proxyAdminAddress);
        console.log("Lum Address -->", lumAddress);
        console.log("Mlum Address -->", mlum);

        address[] memory rewarderAddresses = new address[](2);

        // rewarder addresses
        rewarderAddresses[0] = vm.computeCreateAddress(deployer, nonce++);
        rewarderAddresses[1] = vm.computeCreateAddress(deployer, nonce++);

        // implementations and proxies
        implementations = _computeAddresses(deployer);
        proxies = _computeAddresses(deployer);

        // deploy proxyAdmin

        vm.startBroadcast(pk);
        {
            proxyAdmin = new ProxyAdmin2Step(deployer);

            require(proxyAdminAddress == address(proxyAdmin), "run::1");
        }

        // Deploy LUM mock
        {
            lumMock = new LumMock(deployer, proxies.masterChef);

            require(lumAddress == address(lumMock), "run::2");
        }

        // Deploy Rewarders
        {
            IBaseRewarder masterChefRewarder = new MasterChefRewarder(proxies.masterChef);
            IBribeRewarder bribeRewarder = new BribeRewarder(proxies.voter);

            _implementations[IRewarderFactory.RewarderType.MasterChefRewarder] = IBaseRewarder(rewarderAddresses[0]);
            _implementations[IRewarderFactory.RewarderType.BribeRewarder] = IBaseRewarder(rewarderAddresses[1]);

            rewarders[0] = _implementations[IRewarderFactory.RewarderType.MasterChefRewarder];
            rewarders[1] = _implementations[IRewarderFactory.RewarderType.BribeRewarder];

            require(rewarderAddresses[0] == address(masterChefRewarder), "run::3");
            require(rewarderAddresses[1] == address(bribeRewarder), "run::4");
        }

        // Deploy Implementations

        {
            RewarderFactory rewarderFactoryImplementation = new RewarderFactory();

            require(implementations.rewarderFactory == address(rewarderFactoryImplementation), "run::5");
        }

        {
            MasterChef masterChefImplementation = new MasterChef(
                ILum(lumAddress), IVoter(proxies.voter), IRewarderFactory(proxies.rewarderFactory), address(0), 0.02e18
            );

            require(implementations.masterChef == address(masterChefImplementation), "run::6");
        }

        {
            MlumStaking stakingImplemenation = new MlumStaking(IERC20(mlum), IERC20(rewardToken));

            require(implementations.mlumStaking == address(stakingImplemenation), "run::7");
        }

        {
            Voter voterImplementation = new Voter(
                IMasterChef(proxies.masterChef),
                IMlumStaking(proxies.mlumStaking),
                IRewarderFactory(proxies.rewarderFactory)
            );

            require(implementations.voter == address(voterImplementation), "run::8");
        }

        // Deploy proxies

        {
            IRewarderFactory.RewarderType[] memory rewarderTypes = new IRewarderFactory.RewarderType[](2);
            IBaseRewarder[] memory rewarderImplementations = new IBaseRewarder[](2);

            rewarderTypes[0] = IRewarderFactory.RewarderType.MasterChefRewarder;
            rewarderTypes[1] = IRewarderFactory.RewarderType.BribeRewarder;

            rewarderImplementations[0] = _implementations[IRewarderFactory.RewarderType.MasterChefRewarder];
            rewarderImplementations[1] = _implementations[IRewarderFactory.RewarderType.BribeRewarder];

            bytes memory data = abi.encodeWithSelector(
                RewarderFactory.initialize.selector, deployer, rewarderTypes, rewarderImplementations
            );

            TransparentUpgradeableProxy2Step rewarderFactoryProxy =
                new TransparentUpgradeableProxy2Step(implementations.rewarderFactory, proxyAdmin, data);

            require(proxies.rewarderFactory == address(rewarderFactoryProxy), "run::9");
        }

        {
            TransparentUpgradeableProxy2Step masterChefProxy = new TransparentUpgradeableProxy2Step(
                implementations.masterChef,
                proxyAdmin,
                abi.encodeWithSelector(MasterChef.initialize.selector, deployer, TREASURY_TESTNET)
            );

            require(proxies.masterChef == address(masterChefProxy), "run::10");
        }

        {
            TransparentUpgradeableProxy2Step mlumStakingProxy = new TransparentUpgradeableProxy2Step(
                implementations.mlumStaking,
                proxyAdmin,
                abi.encodeWithSelector(MlumStaking.initialize.selector, deployer)
            );

            require(proxies.mlumStaking == address(mlumStakingProxy), "run::11");
        }

        {
            TransparentUpgradeableProxy2Step voterProxy = new TransparentUpgradeableProxy2Step(
                implementations.voter, proxyAdmin, abi.encodeWithSelector(Voter.initialize.selector, deployer)
            );

            require(proxies.voter == address(voterProxy), "run::12");
        }

        vm.stopBroadcast();
    }

    function _computeAddresses(address deployer_) internal returns (Addresses memory addresses) {
        addresses.rewarderFactory = vm.computeCreateAddress(deployer_, nonce++);
        addresses.masterChef = vm.computeCreateAddress(deployer_, nonce++);
        addresses.mlumStaking = vm.computeCreateAddress(deployer_, nonce++);
        addresses.voter = vm.computeCreateAddress(deployer_, nonce++);
    }
}
