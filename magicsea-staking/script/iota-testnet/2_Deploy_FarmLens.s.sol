// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy} from "../../src/transparent/TransparentUpgradeableProxy2Step.sol";
import "../../src/transparent/ProxyAdmin2Step.sol";

import {ILum} from "../../src/interfaces/ILum.sol";
import {IVoter} from "../../src/interfaces/IVoter.sol";
import {IMlumStaking} from "../../src/interfaces/IMlumStaking.sol";
import {IRewarderFactory} from "../../src/interfaces/IRewarderFactory.sol";
import {IMasterChefRewarder} from "../../src/interfaces/IMasterChefRewarder.sol";

import "../../src/MasterChefV2.sol";

import "../../src/FarmLens.sol";

import {Addresses} from "./config/Addresses.sol";

contract Deployer is Script {
    function run()
        public
        returns (
            FarmLens farmLens,
            FarmLens.FarmData memory farmData,
            FarmLens.VoteInfo memory voteInfo,
            FarmLens.UserBribeData memory userBribeData
        )
    {
        vm.createSelectFork("iota_testnet");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer -->", deployer);

        vm.broadcast(pk);
        farmLens = new FarmLens(
            IMasterChef(Addresses.PROXY_MASTERCHEF_TESTNET),
            IVoter(Addresses.PROXY_VOTER_TESTNET),
            IMlumStaking(Addresses.PROXY_MLUM_STAKING_TESTNET)
        );

        console.log("Voter", address(IMasterChef(Addresses.PROXY_MASTERCHEF_TESTNET).getVoter()));

        {
            farmData = farmLens.getFarmData(6, 6, address(0));
        }

        {
            voteInfo = farmLens.getVoteInfoAt(1);
        }

        {
            IVoter voter = IVoter(Addresses.PROXY_VOTER_TESTNET);
            console.log("Last period", voter.getLatestFinishedPeriod());

            // userBribeData = farmLens.getUserBribeRewards(0x3bC8631E2c59f99180B738D6aEFd881921A6AF5A);
        }
    }
}
