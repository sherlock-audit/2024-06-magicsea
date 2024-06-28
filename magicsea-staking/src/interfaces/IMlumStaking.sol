// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/token/ERC721/IERC721.sol";

interface IMlumStaking is IERC721 {
    // Info of each NFT (staked position).
    struct StakingPosition {
        uint256 amount; // How many lp tokens the user has provided
        uint256 amountWithMultiplier; // Amount + lock bonus faked amount (amount + amount*multiplier)
        uint256 startLockTime; // The time at which the user made his deposit
        uint256 initialLockDuration; // lock duration on creation
        uint256 lockDuration; // The lock duration in seconds
        uint256 lockMultiplier; // Active lock multiplier (times 1e2)
        uint256 rewardDebt; // Reward debt
        uint256 totalMultiplier; // lockMultiplier
    }

    function exists(uint256 tokenId) external view returns (bool);

    function hasDeposits() external view returns (bool);

    function getStakingPosition(uint256 tokenId) external view returns (StakingPosition memory position);

    function pendingRewards(uint256 tokenId) external view returns (uint256);

    function createPosition(uint256 amount, uint256 lockDuration) external;

    function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

    function harvestPosition(uint256 tokenId) external;

    function harvestPositionTo(uint256 tokenId, address to) external;

    function harvestPositionsTo(uint256[] calldata tokenIds, address to) external;

    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external;

    function emergencyWithdraw(uint256 tokenId) external;
}
