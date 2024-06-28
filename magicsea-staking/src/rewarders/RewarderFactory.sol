// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ImmutableClone} from "../libraries/ImmutableClone.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {IRewarder} from "../interfaces/IRewarder.sol";
import {IBribeRewarder} from "../interfaces/IBribeRewarder.sol";
import {IBaseRewarder} from "../interfaces/IBaseRewarder.sol";
import {IRewarderFactory} from "../interfaces/IRewarderFactory.sol";

/**
 * @title Rewarder Factory Contract
 * @dev The Rewarder Factory Contract allows users to create bribe rewarders,
 * and admin to create masterchef.
 */
contract RewarderFactory is Ownable2StepUpgradeable, IRewarderFactory {
    mapping(RewarderType => IRewarder) private _implementations;

    mapping(RewarderType => IRewarder[]) private _rewarders;
    mapping(IRewarder => RewarderType) private _rewarderTypes;

    mapping(address => uint256) private _nonces;

    /**
     * @dev Disables the initialize function.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the RewarderFactory contract.
     * @param initialOwner The initial owner of the contract.
     */
    function initialize(
        address initialOwner,
        RewarderType[] calldata initialRewarderTypes,
        IRewarder[] calldata initialRewarders
    ) external initializer {
        //__Ownable_init(initialOwner);
        _transferOwnership(initialOwner);

        uint256 length = initialRewarderTypes.length;
        for (uint256 i; i < length; ++i) {
            _setRewarderImplementation(initialRewarderTypes[i], initialRewarders[i]);
        }
    }

    /**
     * @dev Returns the rewarder implementation for the given rewarder type.
     * @param rewarderType The rewarder type.
     * @return The rewarder implementation for the given rewarder type.
     */
    function getRewarderImplementation(RewarderType rewarderType) external view returns (IRewarder) {
        return _implementations[rewarderType];
    }

    /**
     * @dev Returns the number of rewarders for the given rewarder type.
     * @param rewarderType The rewarder type.
     * @return The number of rewarders for the given rewarder type.
     */
    function getRewarderCount(RewarderType rewarderType) external view returns (uint256) {
        return _rewarders[rewarderType].length;
    }

    /**
     * @dev Returns the rewarder at the given index for the given rewarder type.
     * @param rewarderType The rewarder type.
     * @param index The index of the rewarder.
     * @return The rewarder at the given index for the given rewarder type.
     */
    function getRewarderAt(RewarderType rewarderType, uint256 index) external view returns (IRewarder) {
        return _rewarders[rewarderType][index];
    }

    /**
     * @dev Returns the rewarder type for the given rewarder.
     * @param rewarder The rewarder.
     * @return The rewarder type for the given rewarder.
     */
    function getRewarderType(IRewarder rewarder) external view returns (RewarderType) {
        return _rewarderTypes[rewarder];
    }

    /**
     * @dev Creates a rewarder.
     * Only the owner can call this function, except for veMoe rewarders.
     * @param rewarderType The rewarder type.
     * @param token The token to reward.
     * @param pid The pool ID.
     * @return rewarder The rewarder.
     */
    function createRewarder(RewarderType rewarderType, IERC20 token, uint256 pid)
        external
        returns (IBaseRewarder rewarder)
    {
        if (rewarderType != RewarderType.VeMoeRewarder) _checkOwner();
        if (rewarderType == RewarderType.JoeStakingRewarder && pid != 0) revert RewarderFactory__InvalidPid();
        if (rewarderType == RewarderType.BribeRewarder) revert RewarderFactory__InvalidRewarderType();

        rewarder = _clone(rewarderType, token, pid);

        emit RewarderCreated(rewarderType, token, pid, rewarder);
    }

    function createBribeRewarder(IERC20 token, address pool) external returns (IBribeRewarder rewarder) {
        rewarder = IBribeRewarder(_cloneBribe(RewarderType.BribeRewarder, token, pool));

        emit BribeRewarderCreated(RewarderType.BribeRewarder, token, pool, rewarder);
    }

    /**
     * @dev Sets the rewarder implementation for the given rewarder type.
     * Only the owner can call this function.
     * @param rewarderType The rewarder type.
     * @param implementation The rewarder implementation.
     */
    function setRewarderImplementation(RewarderType rewarderType, IRewarder implementation) external onlyOwner {
        _setRewarderImplementation(rewarderType, implementation);
    }

    /**
     * @dev Clone the rewarder implementation for the given rewarder type and initialize it.
     * @param rewarderType The rewarder type.
     * @param token The token to reward.
     * @param pid The pool ID.
     * @return rewarder The rewarder.
     */
    function _clone(RewarderType rewarderType, IERC20 token, uint256 pid) private returns (IBaseRewarder rewarder) {
        if (rewarderType == RewarderType.InvalidRewarder) revert RewarderFactory__InvalidRewarderType();

        IRewarder implementation = _implementations[rewarderType];

        if (address(implementation) == address(0)) revert RewarderFactory__ZeroAddress();

        IRewarder[] storage rewarders = _rewarders[rewarderType];

        bytes memory immutableData = abi.encodePacked(token, pid);
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, _nonces[msg.sender]++));

        rewarder = IBaseRewarder(ImmutableClone.cloneDeterministic(address(implementation), immutableData, salt));

        rewarders.push(rewarder);
        _rewarderTypes[rewarder] = rewarderType;

        rewarder.initialize(msg.sender);
    }

    function _cloneBribe(RewarderType rewarderType, IERC20 token, address pool)
        private
        returns (IBribeRewarder rewarder)
    {
        if (rewarderType != RewarderType.BribeRewarder) revert RewarderFactory__InvalidRewarderType();

        IRewarder implementation = _implementations[rewarderType];

        if (address(implementation) == address(0)) revert RewarderFactory__ZeroAddress();

        IRewarder[] storage rewarders = _rewarders[rewarderType];

        bytes memory immutableData = abi.encodePacked(token, pool);
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, _nonces[msg.sender]++));

        rewarder = IBribeRewarder(ImmutableClone.cloneDeterministic(address(implementation), immutableData, salt));

        rewarders.push(rewarder);
        _rewarderTypes[rewarder] = rewarderType;

        rewarder.initialize(msg.sender);
    }

    /**
     * @dev Sets the rewarder implementation for the given rewarder type.
     * @param rewarderType The rewarder type.
     * @param implementation The rewarder implementation.
     */
    function _setRewarderImplementation(RewarderType rewarderType, IRewarder implementation) private {
        if (rewarderType == RewarderType.InvalidRewarder) revert RewarderFactory__InvalidRewarderType();

        _implementations[rewarderType] = implementation;

        emit RewarderImplementationSet(rewarderType, implementation);
    }
}
