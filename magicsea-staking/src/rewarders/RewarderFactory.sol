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
 * @dev The Rewarder Factory Contract allows users to create bribe rewarders and admin to create masterchef.
 */
contract RewarderFactory is Ownable2StepUpgradeable, IRewarderFactory {
    mapping(RewarderType => IRewarder) private _implementations;

    mapping(RewarderType => IRewarder[]) private _rewarders;
    mapping(IRewarder => RewarderType) private _rewarderTypes;

    mapping(address => uint256) private _nonces;

    /// @dev holds whitelisted tokens with their minBribeAmount (> 0) as bribe amount per period
    //  minAmount == 0 means token is not whitelisted
    mapping(address => uint256) private _whitelistedTokens;

    /// @dev fee for creating bribes in native token
    uint256 private _bribeCreatorFee;


    uint256[10] __gap;

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
    ) external reinitializer(1) {
        __Ownable_init(initialOwner);

        uint256 length = initialRewarderTypes.length;
        for (uint256 i; i < length; ++i) {
            _setRewarderImplementation(initialRewarderTypes[i], initialRewarders[i]);
        }

        _bribeCreatorFee = 0; // maybe in the future for non-whitelisted tokens
    }

    /**
     * @dev get the fee for creating bribes in native token decimals
     */
    function getBribeCreatorFee() external view returns (uint256) {
        return _bribeCreatorFee;
    }

    /**
     * @dev Returns if token is whitelisted and the minBribeAmount
     *
     * @param token token address
     * @return isWhitelisted true if whitelisted
     * @return minBribeAmount min bribe amount per period
     */
    function getWhitelistedTokenInfo (address token) external view returns (bool isWhitelisted, uint256 minBribeAmount) {
        minBribeAmount = _whitelistedTokens[token];
        isWhitelisted = minBribeAmount > 0;
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
        _checkOwner();

        if (rewarderType == RewarderType.BribeRewarder) revert RewarderFactory__InvalidRewarderType();

        rewarder = _clone(rewarderType, token, pid);

        emit RewarderCreated(rewarderType, token, pid, rewarder);
    }

    /**
     * @dev Create a bribe rewarder
     * Everyone can call this function. The bribe token needs to be whitelisted
     * @param token The token to reward.
     * @param pool The pool address
     * @return rewarder The rewarder.
     */
    function createBribeRewarder(IERC20 token, address pool) external returns (IBribeRewarder rewarder) {
        _checkWhitelist(address(token));

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
     * @dev Set token with their minBribeAmounts for whitelist
     * Notice: For whitelist native rewards, use address(0)
     *
     * @param tokens token addresses
     * @param minBribeAmounts minAmounts to bribe, 0 means token will be 'delisted'
     */
    function setWhitelist(address[] calldata tokens, uint256[] calldata minBribeAmounts) external onlyOwner {
        uint256 length = tokens.length;
        if (length != minBribeAmounts.length) revert RewarderFactory__InvalidLength();

        for (uint256 i; i < length; ++i) {
            _whitelistedTokens[tokens[i]] = minBribeAmounts[i];
        }
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

    /**
     * returns true if token is whitelisted (min amount > 0)
     * @param token token
     */
    function _checkWhitelist(address token) private view {
        if ( _whitelistedTokens[token] == 0) {
            revert RewarderFactory__TokenNotWhitelisted();
        }
    }

}
