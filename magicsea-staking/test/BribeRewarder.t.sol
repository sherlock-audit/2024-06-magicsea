// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../src/interfaces/IBribeRewarder.sol";
import "../src/interfaces/IMasterChef.sol";
import "../src/rewarders/BribeRewarder.sol";
import "../src/rewarders/BaseRewarder.sol";
import "../src/rewarders/RewarderFactory.sol";
import "../src/transparent/TransparentUpgradeableProxy2Step.sol";
import "./mocks/ERC20.sol";
import "./mocks/VoterMock.sol";

contract BribeRewarderTest is Test {
    VoterMock _voterMock;

    BribeRewarder rewarder;

    RewarderFactory factory;

    IERC20 tokenA;
    IERC20 tokenB;

    IERC20 rewardToken;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    address pool = makeAddr("pool");

    function setUp() public {
        tokenA = IERC20(new ERC20Mock("Token A", "TA", 18));
        tokenB = IERC20(new ERC20Mock("Token B", "TB", 18));

        rewardToken = IERC20(new ERC20Mock("Reward Token", "RT", 6));

        _voterMock = new VoterMock();

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
        factory.setRewarderImplementation(
            IRewarderFactory.RewarderType.BribeRewarder, IRewarder(address(new BribeRewarder(address(_voterMock))))
        );

        rewarder = BribeRewarder(payable(address(factory.createBribeRewarder(rewardToken, pool))));
    }

    function testGetArgs() public view {
        assertEq(address(rewardToken), address(rewarder.getToken()));
        assertEq(pool, rewarder.getPool());
        assertEq(address(_voterMock), rewarder.getCaller());
    }

    function testBribeRevert() public {
        vm.expectRevert(IBribeRewarder.BribeRewarder__WrongEndId.selector);
        rewarder.bribe(3, 1, 10e18);

        _voterMock.setCurrentPeriod(1);

        vm.expectRevert(IBribeRewarder.BribeRewarder__WrongStartId.selector);
        rewarder.bribe(0, 1, 20e18);

        vm.expectRevert(IBribeRewarder.BribeRewarder__WrongStartId.selector);
        rewarder.bribe(1, 1, 20e18);

        vm.expectRevert(IBribeRewarder.BribeRewarder__ZeroReward.selector);
        rewarder.bribe(2, 2, 0);

        vm.expectRevert(IBribeRewarder.BribeRewarder__InsufficientFunds.selector);
        rewarder.bribe(2, 2, 10e18);

        ERC20Mock(address(rewardToken)).mint(address(rewarder), 5e18);
        vm.expectRevert(IBribeRewarder.BribeRewarder__InsufficientFunds.selector);
        rewarder.bribe(2, 2, 10e18);
    }

    function testStartEndEnd() public {
        ERC20Mock(address(rewardToken)).mint(address(rewarder), 20e18);

        rewarder.bribe(1, 2, 10e18);

        assertEq(1, rewarder.getStartVotingPeriodId());
        assertEq(2, rewarder.getLastVotingPeriodId());
    }

    function testBribeAndRegister() public {
        ERC20Mock(address(rewardToken)).mint(address(this), 20e18);
        ERC20Mock(address(rewardToken)).approve(address(rewarder), 20e18);

        rewarder.fundAndBribe(1, 2, 10e18);

        assertEq(20e18, rewardToken.balanceOf(address(rewarder)));

        (, uint256[] memory periods) = rewarder.getBribePeriods();
        assertEq(2, periods.length, "periods::length");
        assertEq(1, periods[0]);
        assertEq(2, periods[1]);

        IBribeRewarder[] memory rewarders;

        rewarders = _voterMock.getPoolBribesForPeriod(1, pool);
        assertEq(address(rewarder), address(rewarders[0]));
        assertEq(1, rewarders.length);

        rewarders = _voterMock.getPoolBribesForPeriod(2, pool);
        assertEq(address(rewarder), address(rewarders[0]));
        assertEq(1, rewarders.length);
    }

    function testDepositAndPendingReward() public {
        ERC20Mock(address(rewardToken)).mint(address(this), 20e18);
        ERC20Mock(address(rewardToken)).approve(address(rewarder), 20e18);

        rewarder.fundAndBribe(1, 2, 10e18);

        vm.expectRevert(IBribeRewarder.BribeRewarder__OnlyVoter.selector);
        rewarder.deposit(1, 1, 0.2e18);

        vm.prank(address(_voterMock));
        rewarder.deposit(1, 1, 0.2e18);

        // still period = 0, so reward is 0
        _voterMock.setCurrentPeriod(1);
        _voterMock.setStartAndEndTime(0, 10);
        vm.warp(0);
        assertEq(0, rewarder.getPendingReward(1, 1));

        // manipulate period and endtime
        _voterMock.setCurrentPeriod(2);
        _voterMock.setStartAndEndTime(10, 20);
        vm.warp(20);
        assertEq(10e18, rewarder.getPendingReward(1, 1));

        vm.prank(alice);
        rewarder.claim(1, 1);

        assertEq(10e18, rewardToken.balanceOf(alice));
    }
}
