// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "openzeppelin/token/ERC721/ERC721.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Mock} from "./mocks/ERC20.sol";
import {MasterChefMock} from "./mocks/MasterChefMock.sol";
import {MlumStaking} from "../src/MlumStaking.sol";
import "../src/Voter.sol";
import {IVoter} from "../src/interfaces/IVoter.sol";

contract VoterTest is Test {
    address payable immutable DEV = payable(makeAddr("dev"));
    address payable immutable ALICE = payable(makeAddr("alice"));
    address payable immutable BOB = payable(makeAddr("bob"));

    Voter private _voter;
    MlumStaking private _pool;

    ERC20Mock private _stakingToken;
    ERC20Mock private _rewardToken;

    function setUp() public {
        vm.prank(DEV);
        _stakingToken = new ERC20Mock("MagicLum", "MLUM", 18);

        vm.prank(DEV);
        _rewardToken = new ERC20Mock("USDT", "USDT", 6);

        vm.prank(DEV);
        _pool = new MlumStaking(_stakingToken, _rewardToken);
        _pool.initialize(DEV);

        vm.prank(DEV);
        MasterChefMock mock = new MasterChefMock();

        vm.prank(DEV);
        _voter = new Voter(mock, _pool, IRewarderFactory(address(new RewaderFactoryMock())));
        _voter.initialize(DEV);

        vm.prank(DEV);
        _voter.updateMinimumLockTime(2 weeks);
    }

    function testStartVotingPeriod() public {
        vm.prank(DEV);
        _voter.startNewVotingPeriod();

        assertEq(1, _voter.getCurrentVotingPeriod());

        (uint256 startTime, uint256 endTime) = _voter.getPeriodStartEndtime(1);
        assertGt(endTime, startTime);
    }

    function testVoteNotStarted() public {
        vm.prank(ALICE);
        vm.expectRevert(IVoter.IVoter_VotingPeriodNotStarted.selector);
        _voter.vote(1, _getDummyPools(), _getDeltaAmounts());
    }

    function testVoteNotOwner() public {
        vm.prank(DEV);
        _voter.startNewVotingPeriod();

        _createPosition(ALICE);

        vm.prank(BOB);
        vm.expectRevert(IVoter.IVoter__NotOwner.selector);
        _voter.vote(1, _getDummyPools(), _getDeltaAmounts());
    }

    function testAlreadyVoted() public {
        vm.prank(DEV);
        _voter.startNewVotingPeriod();

        _createPosition(ALICE);

        vm.startPrank(ALICE);
        _voter.vote(1, _getDummyPools(), _getDeltaAmounts());
        vm.expectRevert(IVoter.IVoter__AlreadyVoted.selector);
        _voter.vote(1, _getDummyPools(), _getDeltaAmounts());
        vm.stopPrank();
    }

    function testInsufficientAmount() public {
        vm.prank(DEV);
        _voter.startNewVotingPeriod();

        _createPosition(ALICE);

        uint256[] memory deltaAmounts = _getDeltaAmounts();
        deltaAmounts[0] = 2e18;

        vm.prank(ALICE);
        vm.expectRevert(IVoter.IVoter__InsufficientVotingPower.selector);
        _voter.vote(1, _getDummyPools(), deltaAmounts);
    }

    function testVoteGetters() public {
        _defaultVoteOnce(ALICE, true);

        address pool = _getDummyPools()[0];

        assertEq(1e18, _voter.getTotalVotes());
        assertEq(1e18, _voter.getUserVotes(1, pool));
        assertEq(1e18, _voter.getPoolVotesPerPeriod(1, pool));
        assertEq(0, _voter.getPoolVotesPerPeriod(2, pool));
        assertEq(1e18, _voter.getPoolVotes(pool));
    }

    function testSetTopPoolPidsAndWeightsInvalidLength() public {
        uint256[] memory pids = new uint256[](4);
        uint256[] memory weights = new uint256[](2);

        vm.prank(DEV);
        vm.expectRevert(IVoter.IVoter__InvalidLength.selector);
        _voter.setTopPoolIdsWithWeights(pids, weights);
    }

    function testSetTopPoolPidsAndWeights() public {
        uint256[] memory pids = new uint256[](2);
        pids[0] = 0;
        pids[1] = 1;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 2e18;
        weights[1] = 1e18;

        vm.prank(DEV);
        _voter.setTopPoolIdsWithWeights(pids, weights);

        assertEq(3e18, _voter.getTotalWeight());
        assertEq(2e18, _voter.getWeight(0));
        assertEq(1e18, _voter.getWeight(1));
    }

    function testGetAllPoolVotes() public {
        _defaultVoteOnce(ALICE, true);

        address[] memory pools = _voter.getVotedPools();
        assertEq(1, pools.length);
    }

    function _defaultVoteOnce(address user, bool newPeriod) internal {
        if (newPeriod) {
            vm.prank(DEV);
            _voter.startNewVotingPeriod();
        }
        _createPosition(user);
        vm.prank(user);
        _voter.vote(1, _getDummyPools(), _getDeltaAmounts());
    }

    function _createPosition(address user) internal {
        _stakingToken.mint(user, 2 ether);

        vm.startPrank(user);
        _stakingToken.approve(address(_pool), 1 ether);
        _pool.createPosition(1 ether, 2 weeks);
        vm.stopPrank();
    }

    function _getDummyPools() internal pure returns (address[] memory pools) {
        pools = new address[](1);
        pools[0] = 0x95f00a7125EC3D78d6B2FCD6FFd9989941eF25fC;
    }

    function _getDeltaAmounts() internal pure returns (uint256[] memory deltaAmounts) {
        deltaAmounts = new uint256[](1);
        deltaAmounts[0] = 1e18;
    }
}

contract RewaderFactoryMock {
    constructor() {
        // nothing
    }
}
