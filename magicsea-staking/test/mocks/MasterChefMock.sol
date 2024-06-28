// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../../src/interfaces/IMasterChef.sol";

//
contract MasterChefMock is IMasterChef {
    function add(IERC20 token, IMasterChefRewarder rewarder) external pure {
        {
            token;
            rewarder;
        } // supress warning
    }

    function claim(uint256[] memory pids) external pure {
        {
            pids;
        } // supress warning
    }

    function deposit(uint256 pid, uint256 amount) external pure {
        {
            pid;
            amount;
        } // supress warning
    }

    function emergencyWithdraw(uint256 pid) external pure {
        {
            pid;
        } // supress warning
    }

    function getDeposit(uint256 pid, address account) external pure returns (uint256) {
        {
            pid;
            account;
        } // supress warning
        return 0;
    }

    function getLastUpdateTimestamp(uint256 pid) external pure returns (uint256) {
        {
            pid;
        }
        return 0;
    }

    function getPendingRewards(address account, uint256[] memory pids)
        external
        pure
        returns (uint256[] memory lumRewards, IERC20[] memory extraTokens, uint256[] memory extraRewards)
    {
        {
            account;
            pids;
        }

        lumRewards = new uint256[](0);
        extraTokens = new IERC20[](0);
        extraRewards = new uint256[](0);
    }

    function getExtraRewarder(uint256 pid) external pure returns (IMasterChefRewarder) {
        {
            pid;
        }
        return IMasterChefRewarder(address(0));
    }

    function getLum() external pure returns (ILum) {
        return ILum(address(0));
    }

    function getLumPerSecond() external pure returns (uint256) {
        return 0;
    }

    function getLumPerSecondForPid(uint256 pid) external pure returns (uint256) {
        {
            pid;
        }
        return 0;
    }

    function getNumberOfFarms() external pure returns (uint256) {
        return 0;
    }

    function getToken(uint256 pid) external pure returns (IERC20) {
        {
            pid;
        }
        return IERC20(address(0));
    }

    function getTotalDeposit(uint256 pid) external pure returns (uint256) {
        {
            pid;
        }
        return 0;
    }

    function getTreasury() external pure returns (address) {
        return address(0);
    }

    function getTreasuryShare() external pure returns (uint256) {
        return 0;
    }

    function getRewarderFactory() external pure returns (IRewarderFactory) {
        return IRewarderFactory(address(0));
    }

    function getLBHooksManager() external pure returns (address) {
        return address(0);
    }

    function getVoter() external pure returns (IVoter) {
        return IVoter(address(0));
    }

    function setExtraRewarder(uint256 pid, IMasterChefRewarder extraRewarder) external pure {
        {
            pid;
            extraRewarder;
        }
    }

    function setVoter(IVoter voter) external pure {
        {
            voter;
        }
        // nothing
    }

    function setLumPerSecond(uint96 lumPerSecond) external pure {
        {
            lumPerSecond;
        }
        // nothing
    }

    function setTreasury(address treasury) external pure {
        {
            treasury;
        }
        // nothing
    }

    function updateAll(uint256[] calldata pids) external pure {
        {
            pids;
        }
        // nothing
    }

    function withdraw(uint256 pid, uint256 amount) external pure {
        {
            pid;
            amount;
        }
        // nothing
    }

    function depositOnBehalf(uint256 pid, uint256 amount, address account) external pure {
        {
            pid;
            amount;
            account;
        }
    }

    function setTrustee(address trustee) external pure override {
        trustee;
    }
}
