// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../src/transparent/TransparentUpgradeableProxy2Step.sol";

import "openzeppelin/token/ERC721/ERC721.sol";
import "openzeppelin/token/ERC20/ERC20.sol";

import "../src/MlumStaking.sol";

import {ERC20Mock} from "./mocks/ERC20.sol";

contract MlumStakingTest is Test {
    address payable immutable DEV = payable(makeAddr("dev"));
    address payable immutable ALICE = payable(makeAddr("alice"));
    address payable immutable BOB = payable(makeAddr("bob"));

    IMlumStaking private _pool;

    ERC20Mock private _stakingToken;
    ERC20Mock private _rewardToken;

    function setUp() public {
        vm.prank(DEV);
        _stakingToken = new ERC20Mock("MagicLum", "MLUM", 18);

        vm.prank(DEV);
        _rewardToken = new ERC20Mock("USDT", "USDT", 6);

        vm.prank(DEV);

        address _poolImpl = address(new MlumStaking(_stakingToken, _rewardToken));

        _pool = MlumStaking(
            address(
                new TransparentUpgradeableProxy2Step(
                    _poolImpl, ProxyAdmin2Step(address(1)), abi.encodeWithSelector(MlumStaking.initialize.selector, DEV)
                )
            )
        );
    }

    function testCreatePosition() public {
        _rewardToken.mint(address(_pool), 100_000_000);
        _stakingToken.mint(ALICE, 2 ether);

        vm.startPrank(ALICE);
        _stakingToken.approve(address(_pool), 1 ether);
        _pool.createPosition(1 ether, 1 days);
        vm.stopPrank();

        assertEq(ERC721(address(_pool)).ownerOf(1), ALICE);

        skip(3600);

        vm.prank(ALICE);
        _pool.harvestPosition(1);

        assertGt(_rewardToken.balanceOf(ALICE), 0);

        vm.startPrank(ALICE);
        vm.expectRevert();
        _pool.withdrawFromPosition(1, 0.5 ether);

        skip(1 days);

        _pool.withdrawFromPosition(1, 0.5 ether);

        vm.stopPrank();
    }

    function testCreatePositions_multiple() public {
        _stakingToken.mint(ALICE, 2 ether);
        _stakingToken.mint(BOB, 4 ether);

        vm.startPrank(ALICE);
        _stakingToken.approve(address(_pool), 1 ether);
        _pool.createPosition(1 ether, 1 days);
        vm.stopPrank();

        vm.startPrank(BOB);
        _stakingToken.approve(address(_pool), 4 ether);
        _pool.createPosition(1 ether, 0.2 days);
        vm.stopPrank();

        // nothing is sent to contract -> reward = 0
        vm.prank(ALICE);
        uint256 aliceAmount = _pool.pendingRewards(1);
        assertEq(aliceAmount, 0);

        vm.prank(BOB);
        uint256 bobAmount = _pool.pendingRewards(2);
        assertEq(bobAmount, 0);

        // send something
        _rewardToken.mint(address(_pool), 100_000_000);

        // rewards > 0
        vm.prank(ALICE);
        aliceAmount = _pool.pendingRewards(1);
        assertGt(aliceAmount, 0);

        vm.prank(BOB);
        bobAmount = _pool.pendingRewards(2);
        assertGt(bobAmount, 0);
    }

    function testAddToPosition() public {
        _stakingToken.mint(ALICE, 2 ether);

        vm.startPrank(ALICE);
        _stakingToken.approve(address(_pool), 1 ether);
        _pool.createPosition(1 ether, 1 days);
        vm.stopPrank();

        // check lockduration
        MlumStaking.StakingPosition memory position = _pool.getStakingPosition(1);
        assertEq(position.lockDuration, 1 days);

        skip(43200);

        // add to position should take calc. avg. lock duration
        vm.startPrank(ALICE);
        _stakingToken.approve(address(_pool), 1 ether);
        _pool.addToPosition(1, 1 ether);
        vm.stopPrank();

        position = _pool.getStakingPosition(1);

        assertEq(position.lockDuration, 64800);
    }

    function testLockDurationAmountWithMultiplier() public {
        _stakingToken.mint(ALICE, 2 ether);

        vm.startPrank(ALICE);
        _stakingToken.approve(address(_pool), 1 ether);
        _pool.createPosition(1 ether, 365 days);
        vm.stopPrank();

        MlumStaking.StakingPosition memory position = _pool.getStakingPosition(1);

        assertEq(3 ether, position.amountWithMultiplier);
    }

    function testAmountWithMuliplierGreaterMaxLockDuration() public {
        _stakingToken.mint(ALICE, 2 ether);

        vm.startPrank(ALICE);
        _stakingToken.approve(address(_pool), 1 ether);
        _pool.createPosition(1 ether, 2 * 365 days);
        vm.stopPrank();

        MlumStaking.StakingPosition memory position = _pool.getStakingPosition(1);

        assertEq(3 ether, position.amountWithMultiplier);
    }

    function testWithdrawPosition() public {
        _stakingToken.mint(ALICE, 2 ether);

        vm.startPrank(ALICE);
        _stakingToken.approve(address(_pool), 1 ether);
        _pool.createPosition(1 ether, 2 days);
        vm.stopPrank();

        skip(1 days);

        vm.expectRevert();
        vm.prank(ALICE);
        _pool.withdrawFromPosition(1, 0.5 ether);

        skip(1 days);
        vm.prank(ALICE);
        _pool.withdrawFromPosition(1, 0.5 ether);

        assertEq(_stakingToken.balanceOf(ALICE), 1.5 ether);
    }
}
