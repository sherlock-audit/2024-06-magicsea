// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "../src/transparent/TransparentUpgradeableProxy2Step.sol";

import "openzeppelin/token/ERC721/ERC721.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Mock} from "./mocks/ERC20.sol";
import {MasterChef} from "../src/MasterChefV2.sol";
import {MlumStaking} from "../src/MlumStaking.sol";
import "../src/Voter.sol";
import "../src/rewarders/BaseRewarder.sol";
import "../src/rewarders/MasterChefRewarder.sol";
import "../src/rewarders/RewarderFactory.sol";
import {IVoter} from "../src/interfaces/IVoter.sol";
import {ILum} from "../src/interfaces/ILum.sol";
import {IRewarderFactory} from "../src/interfaces/IRewarderFactory.sol";

contract MasterChefV2Test is Test {
    address payable immutable DEV = payable(makeAddr("dev"));
    address payable immutable ALICE = payable(makeAddr("alice"));
    address payable immutable BOB = payable(makeAddr("bob"));

    Voter private _voter;
    MlumStaking private _pool;
    MasterChef private _masterChefV2;

    MasterChefRewarder rewarderPoolA;

    RewarderFactory factory;

    ERC20Mock private _stakingToken;
    ERC20Mock private _rewardToken;
    ERC20Mock private _lumToken;

    uint256[] pIds;
    uint256[] weights;
    address[] defaultOperators;

    function setUp() public {
        vm.prank(DEV);
        _stakingToken = new ERC20Mock("MagicLum", "MLUM", 18);

        vm.prank(DEV);
        _rewardToken = new ERC20Mock("USDT", "USDT", 6);

        vm.prank(DEV);
        address poolImpl = address(new MlumStaking(_stakingToken, _rewardToken));

        _pool = MlumStaking(
            address(
                new TransparentUpgradeableProxy2Step(
                    poolImpl, ProxyAdmin2Step(address(1)), abi.encodeWithSelector(MlumStaking.initialize.selector, DEV)
                )
            )
        );

        address factoryImpl = address(new RewarderFactory());
        factory = RewarderFactory(
            address(
                new TransparentUpgradeableProxy2Step(
                    factoryImpl,
                    ProxyAdmin2Step(address(1)),
                    abi.encodeWithSelector(
                        RewarderFactory.initialize.selector, address(this), new uint8[](0), new address[](0)
                    )
                )
            )
        );

        vm.prank(DEV);
        _lumToken = new ERC20Mock("Lum", "LUM", 18);

        vm.prank(DEV);
        address masterChefImp = address(new MasterChef(ILum(address(_lumToken)), factory,DEV,1));

        _masterChefV2 = MasterChef(
            address(
                new TransparentUpgradeableProxy2Step(
                    masterChefImp, ProxyAdmin2Step(address(1)), abi.encodeWithSelector(MasterChef.initialize.selector, DEV,DEV,_voter)
                )
            )
        );
        vm.prank(DEV);
        _masterChefV2.setLumPerSecond(1e18 * 2);
        vm.prank(DEV);
        _masterChefV2.setMintLum(true);

        vm.prank(DEV);
        address voterImpl = address(new Voter(_masterChefV2, _pool, factory));

        _voter = Voter(
            address(
                new TransparentUpgradeableProxy2Step(
                    voterImpl, ProxyAdmin2Step(address(1)), abi.encodeWithSelector(Voter.initialize.selector, DEV)
                )
            )
        );

        vm.prank(DEV);
        _voter.updateMinimumLockTime(2 weeks);

        vm.prank(DEV);
        factory.setRewarderImplementation(
            IRewarderFactory.RewarderType.MasterChefRewarder, IRewarder(address(new MasterChefRewarder(address(_masterChefV2))))
        );

        vm.prank(DEV);
        _masterChefV2.setVoter(_voter);
    }

    function testRewardZeroAfterEmergency() public {
        uint256 currentPID = 0;
        uint256 TOTALREWARDS = 1000000000000000000;
        uint256 HALFTOTALREWARDS = 500000000000000000;

        pIds.push(currentPID);
        weights.push(500);

        vm.prank(DEV);
        ERC20Mock erc20Farm = new ERC20Mock("USDT", "USDT", 18);

        rewarderPoolA = MasterChefRewarder(payable(address(factory.createRewarder(IRewarderFactory.RewarderType.MasterChefRewarder, erc20Farm, currentPID))));
        vm.prank(DEV);
        erc20Farm.mint(address(rewarderPoolA), TOTALREWARDS);

        rewarderPoolA.setRewardPerSecond(1e16, 100);

        assertEq(rewarderPoolA.getPid(), currentPID);
        vm.prank(DEV);
        _masterChefV2.add(erc20Farm,rewarderPoolA);

        vm.prank(DEV);
        erc20Farm.mint(BOB, 1000);
        vm.prank(DEV);
        erc20Farm.mint(ALICE, 1000);

        vm.prank(BOB);
        erc20Farm.approve(address(_masterChefV2), type(uint256).max);
        vm.prank(ALICE);
        erc20Farm.approve(address(_masterChefV2), type(uint256).max);

        vm.prank(BOB);
        _masterChefV2.deposit(currentPID,1000);

        vm.prank(ALICE);
        _masterChefV2.deposit(currentPID,1000);

        _masterChefV2.updateAll(pIds);

        skip(100);

        (uint256[] memory lumRewards, ,uint256[] memory extraRewards) = _masterChefV2.getPendingRewards(BOB, pIds);
        _masterChefV2.updateAll(pIds);

        assertEq(lumRewards[0], 0);
        assertEq(extraRewards[0], HALFTOTALREWARDS);

        vm.prank(BOB);
        _masterChefV2.emergencyWithdraw(currentPID);

        (uint256[] memory lumRewardsAfter, ,uint256[] memory extraRewardsAfter) = _masterChefV2.getPendingRewards(BOB, pIds);
        assertEq(lumRewardsAfter[0], 0);
        assertEq(extraRewardsAfter[0], 0);
        ( , ,uint256[] memory extraRewardsAfterAlice) = _masterChefV2.getPendingRewards(ALICE, pIds);
        assertEq(extraRewardsAfterAlice[0], TOTALREWARDS);
    }
}