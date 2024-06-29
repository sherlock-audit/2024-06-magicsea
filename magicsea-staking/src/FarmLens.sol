// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata, IERC20} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Enumerable, IERC721} from "openzeppelin/token/ERC721/extensions/IERC721Enumerable.sol";

import "./interfaces/IBribeRewarder.sol";

import {IVoter} from "./interfaces/IVoter.sol";
import {IMasterChef} from "./interfaces/IMasterChef.sol";
import {IMasterChefRewarder} from "./interfaces/IMasterChefRewarder.sol";
import {IMagicSeaPair} from "./interfaces/IMagicSeaPair.sol";
import {IMlumStaking} from "./interfaces/IMlumStaking.sol";

/**
 * @author MagicSea / BlueLabs
 * @title FarmLens
 * 
 * Readonly functions to get data from the farm contracts
 */
contract FarmLens {
    IMasterChef immutable _masterChef;
    IVoter immutable _voter;
    IMlumStaking immutable _mlumStaking;

    struct FarmData {
        address masterChef;
        uint256 totalVotes;
        uint256 totalAllocPoint;
        uint256 totalLumPerSec;
        uint256 totalNumberOfFarms;
        Farm[] farms;
    }

    struct Farm {
        uint256 pid;
        address token;
        uint256 totalStaked;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 lumPerSecond;
        Rewarder rewarder;
        Pool poolInfo;
        uint256 userAmount;
        uint256 userPendingLumReward;
    }

    struct Token {
        address token;
        uint256 decimals;
        string symbol;
    }

    struct Pool {
        Token lpToken;
        Token token0;
        Token token1;
        uint256 totalSupply;
        uint256 reserve0;
        uint256 reserve1;
    }

    struct Rewarder {
        address rewarderAddress;
        bool isStarted;
        bool isEnded;
        uint256 pid;
        uint256 totalDeposited;
        uint256 remainingReward;
        uint256 rewardPerSec;
        uint256 lastUpdateTimestamp;
        uint256 endUpdateTimestamp;
        Token rewardToken;
        uint256 userPendingAmount;
    }

    // General vote data
    struct VoteData {
        address voterAddress;
        uint256 totalVotes;
        VoteInfo[] votes;
    }

    struct VoteInfo {
        address pool;
        uint256 votes;
        Bribe[] bribes;
    }

    // User bribe rewards

    struct UserBribeData {
        address account;
        BribeReward[] userBribeRewards;
    }

    struct Bribe {
        address poolAddress;
        uint256 startPeriodId;
        uint256 lastPeriodId;
        uint256 amountPerPeriod;
        address rewarder;
        Token rewardToken;
    }

    struct BribeReward {
        Bribe bribe;
        uint256 periodId;
        uint256 tokenId;
        uint256 pendingReward;
    }

    // Farm Info

    struct FarmVoteData {
        address voterAddress;
        uint256 currentPeriodId;
        uint256 totalWeight;
        uint256 totalVotes;
        FarmVoteInfo[] farmVotes;
    }

    struct FarmVoteInfo {
        uint256 pid;
        address pool;
        uint256 totalVotesPerPool;
        uint256 totalWeightPerFarm;
    }

    constructor(IMasterChef masterChef, IVoter voter, IMlumStaking mlumStaking) {
        _masterChef = masterChef;
        _voter = voter;
        _mlumStaking = mlumStaking;
    }

    function getFarmData(uint256 start, uint256 nb, address account) external view returns (FarmData memory data) {
        uint256 nbFarms = _masterChef.getNumberOfFarms();

        nb = start >= nbFarms ? 0 : (start + nb > nbFarms ? nbFarms - start : nb);

        data = FarmData({
            masterChef: address(_masterChef),
            totalVotes: 0,
            totalAllocPoint: _voter.getTotalWeight(),
            totalLumPerSec: _masterChef.getLumPerSecond(),
            totalNumberOfFarms: nbFarms,
            farms: new Farm[](nb)
        });

        for (uint256 i; i < nb; ++i) {
            data.farms[i] = this.getFarmInfo(start + i, account);
            /* try this.getFarmInfo(start + i, account) returns (Farm memory farm) {
                data.farms[i] = farm;
            } catch {} */
        }
    }

    /**
     * @dev returns farm info for a pid. mimics the poolInfo from legacy farm implementation
     */
    function getFarmInfo(uint256 pid, address account) external view returns (Farm memory farm) {
        address lpAddress = address(_masterChef.getToken(pid));
        farm.pid = pid;
        farm.token = lpAddress;
        farm.totalStaked = _masterChef.getTotalDeposit(pid);
        farm.allocPoint = _voter.getWeight(pid);
        farm.lastRewardTime = _masterChef.getLastUpdateTimestamp(pid);
        // farm.lumPerSecond = _masterChef.getLumPerSecondForPid(pid);
        try this.getPoolInfo(lpAddress) returns (Pool memory poolInfo) {
            farm.poolInfo = poolInfo;
        } catch {}

        IMasterChefRewarder rewarder = _masterChef.getExtraRewarder(pid);

        (uint256 lumReward,, uint256 extraReward) = getMasterChefPendingRewardsAt(account, pid);

        farm.userAmount = _masterChef.getDeposit(pid, account);
        farm.userPendingLumReward = lumReward;

        if (address(rewarder) != address(0)) {
            (IERC20 token, uint256 rewardPerSecond, uint256 lastUpdateTimestamp, uint256 endTimestamp) =
                rewarder.getRewarderParameter();

            Token memory rewardToken;
            try this.getRewardToken(address(token)) returns (Token memory rewardToken_) {
                rewardToken = rewardToken_;
            } catch {}

            uint256 remainingReward = _getRemainingReward(address(rewarder));

            farm.rewarder = Rewarder({
                rewarderAddress: address(rewarder),
                isStarted: lastUpdateTimestamp <= block.timestamp,
                isEnded: endTimestamp <= block.timestamp,
                pid: pid,
                totalDeposited: farm.totalStaked,
                rewardToken: rewardToken,
                rewardPerSec: rewardPerSecond,
                remainingReward: remainingReward,
                lastUpdateTimestamp: lastUpdateTimestamp,
                endUpdateTimestamp: endTimestamp,
                userPendingAmount: extraReward
            });
        }
    }

    function getMasterChefPendingRewardsAt(address user, uint256 pid)
        public
        view
        returns (uint256 moeReward, address extraToken, uint256 extraReward)
    {
        uint256[] memory pids = new uint256[](1);
        pids[0] = pid;

        (uint256[] memory lumRewards, IERC20[] memory extraTokens, uint256[] memory extraRewards) =
            _masterChef.getPendingRewards(user, pids);

        return (lumRewards[0], address(extraTokens[0]), extraRewards[0]);
    }

    function getPoolInfo(address lpAddress) external view returns (Pool memory poolInfo) {
        IMagicSeaPair pair = IMagicSeaPair(lpAddress);

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        address token0Address = pair.token0();
        address token1Address = pair.token1();

        uint256 decimals0 = IERC20Metadata(token0Address).decimals();
        uint256 decimals1 = IERC20Metadata(token1Address).decimals();

        poolInfo.lpToken = Token({
            token: lpAddress,
            symbol: IERC20Metadata(lpAddress).symbol(),
            decimals: IERC20Metadata(lpAddress).decimals()
        });
        poolInfo.totalSupply = pair.totalSupply();
        poolInfo.token0 =
            Token({token: token0Address, symbol: IERC20Metadata(token0Address).symbol(), decimals: decimals0});

        poolInfo.token1 =
            Token({token: token1Address, symbol: IERC20Metadata(token1Address).symbol(), decimals: decimals1});

        poolInfo.reserve0 = reserve0;
        poolInfo.reserve1 = reserve1;
    }

    function _getRemainingReward(address rewarder) private view returns (uint256 remainingReward) {
        remainingReward = IMasterChefRewarder(rewarder).getRemainingReward();
        // (, bytes memory data) = rewarder.staticcall(abi.encodeWithSelector(IBaseRewarder.getRemainingReward.selector));
        // remainingReward = abi.decode(data, (uint256));
    }

    function getVoteData(uint256 start, uint256 nb) external view returns (VoteData memory voteData) {
        uint256 nbPools = _voter.getVotedPoolsLength();

        nb = start >= nbPools ? 0 : (start + nb > nbPools ? nbPools - start : nb);

        voteData =
            VoteData({voterAddress: address(_voter), totalVotes: _voter.getTotalVotes(), votes: new VoteInfo[](nb)});

        for (uint256 i; i < nb; ++i) {
            try this.getVoteInfoAt(start + i) returns (VoteInfo memory info) {
                voteData.votes[i] = info;
            } catch {}
        }
    }

    function getVoteInfoAt(uint256 index) external view returns (VoteInfo memory voteInfo) {
        (address pool, uint256 votes) = _voter.getVotedPoolsAtIndex(index);

        Bribe[] memory bribes = this.getBribesForPool(_voter.getCurrentVotingPeriod(), pool);

        voteInfo = VoteInfo({pool: pool, votes: votes, bribes: bribes});
    }

    function getBribesForPool(uint256 period, address pool) external view returns (Bribe[] memory bribes) {
        uint256 length = _voter.getBribeRewarderLength(period, pool);
        bribes = new Bribe[](length);

        for (uint256 i = 0; i < length; ++i) {
            IBribeRewarder rewarder = _voter.getBribeRewarderAt(period, pool, i);

            bribes[i] = this.getBribe(rewarder);
        }
    }

    function getBribe(IBribeRewarder rewarder) external view returns (Bribe memory bribe) {
        bribe = Bribe({
            poolAddress: rewarder.getPool(),
            rewarder: address(rewarder),
            startPeriodId: rewarder.getStartVotingPeriodId(),
            lastPeriodId: rewarder.getLastVotingPeriodId(),
            amountPerPeriod: rewarder.getAmountPerPeriod(),
            rewardToken: this.getRewardToken(address(rewarder.getToken()))
        });
    }

    function getRewardToken(address tokenAddress) external view returns (Token memory rewardToken) {
        rewardToken = Token({
            token: tokenAddress,
            symbol: IERC20Metadata(tokenAddress).symbol(),
            decimals: IERC20Metadata(tokenAddress).decimals()
        });
    }

    /// returns user rewards from perod
    function getUserBribeRewards(address account) external view returns (UserBribeData memory userData) {
        userData.account = account;

        // get tokenIds from account
        uint256 tokenIdLength = IERC721(address(_mlumStaking)).balanceOf(account);

        // TODO get pending reward for each last (future: last 5) periods
        // for now only the last period (which is claimable)

        uint256 lastPeriod;
        try _voter.getLatestFinishedPeriod() returns (uint256 lastPeriod_) {
            lastPeriod = lastPeriod_;
        } catch {
            lastPeriod = 0; // this will give zero rewards anyway
        }

        uint256 numberOfRewards = _numberOfAllUserBribeRewards(lastPeriod, tokenIdLength, account);
        userData.userBribeRewards = new BribeReward[](numberOfRewards);
        for (uint256 i; i < numberOfRewards; ++i) {
            // return rewards for each rewarder
            for (uint256 i1; i1 < tokenIdLength; ++i1) {
                uint256 tokenId = IERC721Enumerable(address(_mlumStaking)).tokenOfOwnerByIndex(account, i1);

                for (uint256 i2; i2 < _voter.getUserBribeRewarderLength(lastPeriod, tokenId); ++i2) {
                    userData.userBribeRewards[i] = this.getUserBribeRewardFor(lastPeriod, tokenId, i2);
                }
            }
        }
    }

    function _numberOfAllUserBribeRewards(uint256 period, uint256 mlumBalance, address account)
        internal
        view
        returns (uint256 rewardLength)
    {
        for (uint256 i; i < mlumBalance; ++i) {
            uint256 tokenId = IERC721Enumerable(address(_mlumStaking)).tokenOfOwnerByIndex(account, i); // .tokenByIndex(i);
            rewardLength += _voter.getUserBribeRewarderLength(period, tokenId);
        }
    }

    function getUserBribeRewardFor(uint256 period, uint256 tokenId, uint256 index)
        external
        view
        returns (BribeReward memory userReward)
    {
        IBribeRewarder rewarder = _voter.getUserBribeRewaderAt(period, tokenId, index);
        userReward.bribe = this.getBribe(rewarder);
        userReward.periodId = period;
        userReward.tokenId = tokenId;
        userReward.pendingReward = rewarder.getPendingReward(period, tokenId);
    }
}
