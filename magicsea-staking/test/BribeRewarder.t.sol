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
            IRewarderFactory.RewarderType.BribeRewarder, IRewarder(address(
                new BribeRewarder(address(_voterMock), address(factory))))
        );


        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);

        uint256[] memory minAmounts = new uint256[](1);
        minAmounts[0] = 10e18;

        factory.setWhitelist(rewardTokens, minAmounts);

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

        ERC20Mock(address(rewardToken)).mint(address(rewarder), 10e18);
        vm.expectRevert(IBribeRewarder.BribeRewarder__InsufficientFunds.selector);
        rewarder.bribe(2, 2, 20e18);

        vm.expectRevert(IBribeRewarder.BribeRewarder__AmountTooLow.selector);
        rewarder.bribe(2, 2, 5e18);
    }

    function testWhitelist() public {
        // revert
        vm.expectRevert(IRewarderFactory.RewarderFactory__TokenNotWhitelisted.selector);
        factory.createBribeRewarder(tokenA, pool);

        // check for length
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(tokenA);

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = 1;
        minAmounts[1] = 2e18;

        vm.expectRevert(IRewarderFactory.RewarderFactory__InvalidLength.selector);
        factory.setWhitelist(rewardTokens, minAmounts);

        // allow tokenA
        minAmounts = new uint256[](1);
        minAmounts[0] = 2e18;

        factory.setWhitelist(rewardTokens, minAmounts);

        (bool isWhitelisted, uint256 minAmount) = factory.getWhitelistedTokenInfo(address(tokenA));
        assertTrue(isWhitelisted);
        assertEq(2e18, minAmount);

        IBribeRewarder rewarder_ = factory.createBribeRewarder(tokenA, pool);
        assertEq(address(tokenA), address(rewarder_.getToken()));

        // disallow tokenA again
        minAmounts[0] = 0;

        factory.setWhitelist(rewardTokens, minAmounts);

        vm.expectRevert(IRewarderFactory.RewarderFactory__TokenNotWhitelisted.selector);
        factory.createBribeRewarder(tokenA, pool);
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
        rewarder.deposit(1, alice, 0.2e18);

        _voterMock.setCurrentPeriod(1);
        _voterMock.setStartAndEndTime(0, 20);

        vm.prank(address(_voterMock));
        vm.warp(0);
        rewarder.deposit(1, alice, 0.2e18);

        // still period = 0, so reward is 0
        vm.warp(5);
        assertEq(0, rewarder.getPendingReward(alice));

        // manipulate period and endtime
        _voterMock.setCurrentPeriod(2);
        // _voterMock.setStartAndEndTime(25, 30);
        _voterMock.setLatestFinishedPeriod(1);
        vm.warp(20);
        assertEq(10000000000000000000, rewarder.getPendingReward(alice));

        vm.warp(21);
        vm.prank(alice);
        rewarder.claim(alice);

        assertEq(10000000000000000000, rewardToken.balanceOf(alice));
    }

    function testDepositMultiple() public {
        ERC20Mock(address(rewardToken)).mint(address(this), 20e18);
        ERC20Mock(address(rewardToken)).approve(address(rewarder), 20e18);

        rewarder.fundAndBribe(1, 2, 10e18);

        _voterMock.setCurrentPeriod(1);
        _voterMock.setStartAndEndTime(0, 100);

        // time: 0
        vm.warp(0);
        vm.prank(address(_voterMock));
        rewarder.deposit(1, alice, 0.2e18);

        assertEq(0, rewarder.getPendingReward(alice));

        // time: 50, seconds join
        vm.warp(50);
        vm.prank(address(_voterMock));
        rewarder.deposit(1, bob, 0.2e18);

        // time: 100
        vm.warp(100);
        _voterMock.setCurrentPeriod(2);
        _voterMock.setStartAndEndTime(0, 100);
        _voterMock.setLatestFinishedPeriod(1);

        // 1 -> [0,50] -> 1: 0.5
        // 2 -> [50,100] -> 1: 0.25 + 0.5, 2: 0.25

        assertEq(7500000000000000000, rewarder.getPendingReward(alice));
        assertEq(2500000000000000000, rewarder.getPendingReward(bob));

        vm.prank(alice);
        rewarder.claim(alice);

        vm.prank(bob);
        rewarder.claim(bob);

        assertEq(7500000000000000000, rewardToken.balanceOf(alice));
        assertEq(2500000000000000000, rewardToken.balanceOf(bob));
    }

    function testSweep() public {

        vm.prank(bob);
        IBribeRewarder newRewarder = factory.createBribeRewarder(
            rewardToken, pool
        );

        ERC20Mock(address(rewardToken)).mint(address(newRewarder), 20e18);

        vm.expectRevert();
        vm.prank(alice);
        newRewarder.sweep(rewardToken, alice);

        vm.prank(bob);
        newRewarder.sweep(rewardToken, bob);

        assertEq(20e18, rewardToken.balanceOf(bob));

        vm.startPrank(bob);
        rewardToken.approve(address(newRewarder), 20e18);

        BribeRewarder(payable(address(newRewarder))).fundAndBribe(1, 2, 10e18);

        vm.expectRevert(IBribeRewarder.BribeRewarder__OnlyVoterAdmin.selector);
        newRewarder.sweep(rewardToken, bob);
        vm.stopPrank();

        // sweep as admin (= address(this))
        newRewarder.sweep(rewardToken, bob);

        assertEq(20e18, rewardToken.balanceOf(bob));
    }
}
