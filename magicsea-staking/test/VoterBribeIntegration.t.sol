// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../src/transparent/TransparentUpgradeableProxy2Step.sol";

import "openzeppelin/token/ERC721/ERC721.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Mock} from "./mocks/ERC20.sol";
import {MasterChefMock} from "./mocks/MasterChefMock.sol";
import {MlumStaking} from "../src/MlumStaking.sol";
import "../src/Voter.sol";
import {IVoter} from "../src/interfaces/IVoter.sol";
import "../src/rewarders/RewarderFactory.sol";
import "../src/rewarders/BribeRewarder.sol";

contract VoterBribeIntegration is Test {
    address payable immutable DEV = payable(makeAddr("dev"));
    address payable immutable ALICE = payable(makeAddr("alice"));
    address payable immutable BOB = payable(makeAddr("bob"));

    Voter private _voter;
    MlumStaking private _pool;
    RewarderFactory private _factory;

    ERC20Mock private _stakingToken;
    ERC20Mock private _rewardToken;

    address _poolMock = address(1);

    function setUp() public {
        _stakingToken = new ERC20Mock("MagicLum", "MLUM", 18);
        _rewardToken = new ERC20Mock("USDT", "USDT", 6);

        address poolImpl = address(new MlumStaking(_stakingToken, _rewardToken));

        _pool = MlumStaking(
            address(
                new TransparentUpgradeableProxy2Step(
                    poolImpl, ProxyAdmin2Step(address(1)), abi.encodeWithSelector(MlumStaking.initialize.selector, address(this))
                )
            )
        );

        MasterChefMock mock = new MasterChefMock();

        address factoryImpl = address(new RewarderFactory());
        _factory = RewarderFactory(
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

        address voterImpl = address(new Voter(mock, _pool, IRewarderFactory(address(_factory))));

        _voter = Voter(
            address(
                new TransparentUpgradeableProxy2Step(
                    voterImpl, ProxyAdmin2Step(address(1)), abi.encodeWithSelector(Voter.initialize.selector, address(this))
                )
            )
        );

        _factory.setRewarderImplementation(
            IRewarderFactory.RewarderType.BribeRewarder, IRewarder(address(
                new BribeRewarder(address(_voter), address(_factory))))
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(_rewardToken);

        uint256[] memory minAmounts = new uint256[](1);
        minAmounts[0] = 1;

        _factory.setWhitelist(rewardTokens, minAmounts);

        _voter.updateMinimumLockTime(2 weeks);
    }

    function testRevertOnToManyBribes() public {
        addNumberOfRewarders(5, ALICE);

        // poor bob can't bribe
        vm.prank(BOB);
        BribeRewarder rewarder = BribeRewarder(payable(address(_factory.createBribeRewarder(_rewardToken, _poolMock))));

        _rewardToken.mint(address(rewarder), 1000);

        vm.expectRevert("too much bribes");
        vm.prank(BOB);
        rewarder.bribe(1, 1, 1);

        assertEq(_voter.getBribeRewarderLength(1, _poolMock), 5);
    }

    function testAddElevatedBribe() public {
        addNumberOfRewarders(5, ALICE);

        vm.prank(BOB);
        BribeRewarder rewarder = BribeRewarder(payable(address(_factory.createBribeRewarder(_rewardToken, _poolMock))));

        _rewardToken.mint(address(rewarder), 1000);

        vm.prank(BOB);
        vm.expectRevert("too much bribes");
        rewarder.bribe(1, 1, 1);

        // elevate bobs rewarder
        _voter.addElevatedRewarder(address(rewarder));

        vm.prank(BOB);
        rewarder.bribe(1, 1, 1);

        assertEq(_voter.getBribeRewarderLength(1, _poolMock), 6);
    }

    function testRemoveElevatedBribe() public {
        addNumberOfRewarders(5, ALICE);

        vm.prank(BOB);
        BribeRewarder rewarder = BribeRewarder(payable(address(_factory.createBribeRewarder(_rewardToken, _poolMock))));

        _rewardToken.mint(address(rewarder), 1000);

        _voter.addElevatedRewarder(address(rewarder));
        _voter.removeElevatedRewarder(address(rewarder));

        vm.prank(BOB);
        vm.expectRevert("too much bribes");
        rewarder.bribe(1, 1, 1);

        assertEq(_voter.getBribeRewarderLength(1, _poolMock), 5);
    }

    function addNumberOfRewarders(uint num, address by) internal {
        for (uint256 i = 0; i < num; i++) {
            vm.prank(by);
            BribeRewarder rewarder_ = BribeRewarder(payable(address(_factory.createBribeRewarder(_rewardToken, _poolMock))));

            _rewardToken.mint(address(rewarder_), 1000);

            vm.prank(by);
            rewarder_.bribe(1, 1, 1);
        }
    }
}