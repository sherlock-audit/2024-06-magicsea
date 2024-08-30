// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import "../../src/transparent/TransparentUpgradeableProxy2Step.sol";
import "../../src/transparent/ProxyAdmin2Step.sol";
import "../../src/rewarders/RewarderFactory.sol";
import "../../src/rewarders/MasterChefRewarder.sol";
import "../../src/rewarders/BribeRewarder.sol";
import "../../src/MasterChefV2.sol";
import "../../src/mocks/AdminVoter.sol";

import "../../src/MlumStaking.sol";

import {ILum} from "../../src/interfaces/ILum.sol";
import {IVoter} from "../../src/interfaces/IVoter.sol";
import {IMlumStaking} from "../../src/interfaces/IMlumStaking.sol";
import {IRewarderFactory} from "../../src/interfaces/IRewarderFactory.sol";

import {Addresses} from "./config/Addresses.sol";

contract Deployer is Script {
    mapping(IRewarderFactory.RewarderType => IBaseRewarder) _implementations;

    uint256 nonce;

    uint256 pk;
    address deployer;

    struct SCAddresses {
        address rewarderFactory;
        address masterChef;
        address voter;
    }

    function run()
        public
        returns (
            ProxyAdmin2Step proxyAdmin,
            IBaseRewarder[2] memory rewarders,
            SCAddresses memory implementations,
            SCAddresses memory proxies
        )
    {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.createSelectFork("iota");

        nonce = vm.getNonce(deployer);

        address proxyAdminAddress = vm.computeCreateAddress(deployer, nonce++);
        console.log("Proxy Admin -->", proxyAdminAddress);

        // rewarder addresses
        address[] memory rewarderAddresses = new address[](2);
        rewarderAddresses[0] = vm.computeCreateAddress(deployer, nonce++);
        rewarderAddresses[1] = address(0); // bribeRewarder still not audited  // vm.computeCreateAddress(deployer, nonce++);

        // implementations and proxies
        implementations = _computeAddresses(deployer);
        proxies = _computeAddresses(deployer);

        // deploy proxyAdmin

        vm.startBroadcast(pk);
        {
            proxyAdmin = new ProxyAdmin2Step(deployer);

            require(proxyAdminAddress == address(proxyAdmin), "run::1");
        }

        // Deploy Rewarders
        {
            IBaseRewarder masterChefRewarder = new MasterChefRewarder(proxies.masterChef);
            // IBribeRewarder bribeRewarder = new BribeRewarder(proxies.voter);

            _implementations[IRewarderFactory.RewarderType.MasterChefRewarder] = IBaseRewarder(rewarderAddresses[0]);
            _implementations[IRewarderFactory.RewarderType.BribeRewarder] = IBaseRewarder(rewarderAddresses[1]);

            rewarders[0] = _implementations[IRewarderFactory.RewarderType.MasterChefRewarder];
            rewarders[1] = _implementations[IRewarderFactory.RewarderType.BribeRewarder];

            require(rewarderAddresses[0] == address(masterChefRewarder), "run::3");
            // require(rewarderAddresses[1] == address(bribeRewarder), "run::4");
        }

        // Deploy Implementations
        {
            RewarderFactory rewarderFactoryImplementation = new RewarderFactory();

            require(implementations.rewarderFactory == address(rewarderFactoryImplementation), "run::5");
        }

        {
            MasterChef masterChefImplementation =
                new MasterChef(ILum(Addresses.LUM_MAINNET), IRewarderFactory(proxies.rewarderFactory), address(0), 0);

            require(implementations.masterChef == address(masterChefImplementation), "run::6");
        }

        {
            AdminVoter voterImplementation = new AdminVoter(IMasterChef(proxies.masterChef));

            require(implementations.voter == address(voterImplementation), "run::7");
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
                abi.encodeWithSelector(
                    MasterChef.initialize.selector, deployer, Addresses.TREASURY_MAINNET, IVoter(proxies.voter)
                )
            );

            require(proxies.masterChef == address(masterChefProxy), "run::10");
        }

        {
            TransparentUpgradeableProxy2Step voterProxy = new TransparentUpgradeableProxy2Step(
                implementations.voter, proxyAdmin, abi.encodeWithSelector(AdminVoter.initialize.selector, deployer)
            );

            require(proxies.voter == address(voterProxy), "run::11");
        }

        vm.stopBroadcast();
    }

    function _computeAddresses(address deployer_) internal returns (SCAddresses memory addresses) {
        addresses.rewarderFactory = vm.computeCreateAddress(deployer_, nonce++);
        addresses.masterChef = vm.computeCreateAddress(deployer_, nonce++);
        addresses.voter = vm.computeCreateAddress(deployer_, nonce++);
    }
}
