// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Math} from "./libraries/Math.sol";
import {Rewarder} from "./libraries/Rewarder.sol";
import {Constants} from "./libraries/Constants.sol";
import {Amounts} from "./libraries/Amounts.sol";
import {ILum} from "./interfaces/ILum.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IMasterChef} from "./interfaces/IMasterChef.sol";
import {IMasterChefRewarder} from "./interfaces/IMasterChefRewarder.sol";
import {IRewarderFactory, IBaseRewarder} from "./interfaces/IRewarderFactory.sol";

/**
 * @title Master Chef Contract
 * @author MagicSea / BlueLabs
 * @dev The MasterChef allows users to deposit tokens to earn LUM tokens distributed as liquidity mining rewards.
 * The LUM token is minted by the MasterChef contract and distributed to the users.
 * A share of the rewards is sent to the treasury.
 * The weight of each pool is determined by the amount of votes in the Voter contract and by the top pool ids.
 * On top of the Voter rewards, the MasterChef can also distribute extra rewards in other tokens using extra rewarders.
 * 
 */
contract MasterChef is Ownable2StepUpgradeable, IMasterChef {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILum;
    using Math for uint256;
    using Rewarder for Rewarder.Parameter;
    using Amounts for Amounts.Parameter;

    ILum private immutable _lum;
    IVoter private _voter; // TODO make immutable again
    IRewarderFactory private immutable _rewarderFactory;
    address private immutable _lbHooksManager;

    uint256 private immutable _treasuryShare;

    address private _treasury;
    address private _gap0; // unused, but needed for the storage layout to be the same as the previous contract
    address private _gap1; // unused, but needed for the storage layout to be the same as the previous contract

    uint96 private _lumPerSecond;

    Farm[] private _farms;

    address private _trustee;

    bool private _mintLUM;

    address private _operator;

    /// trackes the unclaimed rewards for each address, eg. we dont want pay out lum on deposit
    /// pid => account => unclaimedRewards;
    mapping(uint256 => mapping (address => uint256)) private unclaimedRewards; 

    uint256[6] __gap;

    modifier onlyTrusted() {
        if (_trustee == address(0)) revert MasterChef__TrusteeNotSet();
        if (msg.sender != _trustee) revert MasterChef__NotTrustedCaller();
        _;
    }

    /**
     * @dev Constructor for the MasterChef contract.
     * @param lum The address of the LUM token.
     * @param voter The address of the VeMOE contract.
     * @param rewarderFactory The address of the rewarder factory.
     * @param lbHooksManager The address of the LB hooks manager.
     * @param treasuryShare The share of the rewards that will be sent to the treasury.
     */
    constructor(
        ILum lum,
        IVoter voter,
        IRewarderFactory rewarderFactory,
        address lbHooksManager,
        uint256 treasuryShare
    ) {
        _disableInitializers();

        if (treasuryShare > Constants.PRECISION) revert MasterChef__InvalidShares();

        _lum = lum;
        _voter = voter;
        _rewarderFactory = rewarderFactory;
        _lbHooksManager = lbHooksManager;

        _treasuryShare = treasuryShare;
    }

    /**
     * @dev Initializes the MasterChef contract.
     * @param initialOwner The initial owner of the contract.
     * @param treasury The initial treasury.
     */
    function initialize(address initialOwner, address treasury) external reinitializer(3) {
        __Ownable_init(initialOwner);

        _setTreasury(treasury);

        _mintLUM = false;
    }

    /**
     * @dev Returns the address of the MOE token.
     * @return The address of the MOE token.
     */
    function getLum() external view override returns (ILum) {
        return _lum;
    }

    /**
     * @dev Returns the address of the Voter contract.
     * @return The address of the Voter contract.
     */
    function getVoter() external view override returns (IVoter) {
        return _voter;
    }

    /**
     * @dev Returns the address of the rewarder factory.
     * @return The address of the rewarder factory.
     */
    function getRewarderFactory() external view override returns (IRewarderFactory) {
        return _rewarderFactory;
    }

    /**
     * @dev Returns the address of the LB hooks manager.
     * @return The address of the LB hooks manager.
     */
    function getLBHooksManager() external view override returns (address) {
        return _lbHooksManager;
    }

    /**
     * @dev Returns the address of the treasury.
     * @return The address of the treasury.
     */
    function getTreasury() external view override returns (address) {
        return _treasury;
    }

    /**
     * @dev Returns the share of the rewards that will be sent to the treasury.
     * @return The share of the rewards that will be sent to the treasury.
     */
    function getTreasuryShare() external view override returns (uint256) {
        return _treasuryShare;
    }

    /**
     * @dev Returns the number of farms.
     * @return The number of farms.
     */
    function getNumberOfFarms() external view override returns (uint256) {
        return _farms.length;
    }

    /**
     * @dev Returns the deposit amount of an account on a farm.
     * @param pid The pool ID of the farm.
     * @param account The account to check for the deposit amount.
     * @return The deposit amount of the account on the farm.
     */
    function getDeposit(uint256 pid, address account) external view override returns (uint256) {
        return _farms[pid].amounts.getAmountOf(account);
    }

    /**
     * @dev Returns the total deposit amount of a farm.
     * @param pid The pool ID of the farm.
     * @return The total deposit amount of the farm.
     */
    function getTotalDeposit(uint256 pid) external view override returns (uint256) {
        return _farms[pid].amounts.getTotalAmount();
    }

    /**
     * @dev Returns the pending rewards for a given account on a list of farms.
     * @param account The account to check for pending rewards.
     * @param pids The pool IDs of the farms.
     * @return lumRewards The LUM rewards for the account on the farms.
     * @return extraTokens The extra tokens from the extra rewarders.
     * @return extraRewards The extra rewards amounts from the extra rewarders.
     */
    function getPendingRewards(address account, uint256[] calldata pids)
        external
        view
        override
        returns (uint256[] memory lumRewards, IERC20[] memory extraTokens, uint256[] memory extraRewards)
    {
        lumRewards = new uint256[](pids.length);
        extraTokens = new IERC20[](pids.length);
        extraRewards = new uint256[](pids.length);

        for (uint256 i; i < pids.length; ++i) {
            uint256 pid = pids[i];

            Farm storage farm = _farms[pid];

            Rewarder.Parameter storage rewarder = farm.rewarder;
            Amounts.Parameter storage amounts = farm.amounts;

            uint256 balance = amounts.getAmountOf(account);
            uint256 totalSupply = amounts.getTotalAmount();

            {
                (, uint256 lumRewardForPid) = _calculateAmounts(_getRewardForPid(rewarder, pid, totalSupply));
                lumRewards[i] = rewarder.getPendingReward(account, balance, totalSupply, lumRewardForPid) + unclaimedRewards[pid][account];
            }

            IMasterChefRewarder extraRewarder = farm.extraRewarder;

            if (address(extraRewarder) != address(0)) {
                (extraTokens[i], extraRewards[i]) = extraRewarder.getPendingReward(account, balance, totalSupply);
            }
        }
    }

    /**
     * @dev Returns the token of a farm.
     * @param pid The pool ID of the farm.
     * @return The token of the farm.
     */
    function getToken(uint256 pid) external view override returns (IERC20) {
        return _farms[pid].token;
    }

    /**
     * @dev Returns the last update timestamp of a farm.
     * @param pid The pool ID of the farm.
     * @return The last update timestamp of the farm.
     */
    function getLastUpdateTimestamp(uint256 pid) external view override returns (uint256) {
        return _farms[pid].rewarder.lastUpdateTimestamp;
    }

    /**
     * @dev Returns the extra rewarder of a farm.
     * @param pid The pool ID of the farm.
     * @return The extra rewarder of the farm.
     */
    function getExtraRewarder(uint256 pid) external view override returns (IMasterChefRewarder) {
        return _farms[pid].extraRewarder;
    }

    /**
     * @dev Returns the LUM per second.
     * @return The LUM per second.
     */
    function getLumPerSecond() external view override returns (uint256) {
        return _lumPerSecond;
    }

    /**
     * @dev Returns the mintLUM flag.
     */
    function getMintLumFlag() external view returns (bool) {
        return _mintLUM;
    }

    /**
     * @dev Returns the LUM per second for a given pool ID.
     * If the pool ID is not in the top pool IDs, it will return 0.
     * Else, it will return the LUM per second multiplied by the weight of the pool ID over the total weight.
     * @param pid The pool ID.
     * @return The LUM per second for the pool ID.
     */
    function getLumPerSecondForPid(uint256 pid) external view override returns (uint256) {
        return _getRewardForPid(pid, _lumPerSecond, _voter.getTotalWeight());
    }

    /**
     * @dev Deposits tokens to a farm on behalf for user
     * @param pid The pool ID of the farm.
     * @param amount The amount of tokens to deposit.
     * @param to User account
     */
    function depositOnBehalf(uint256 pid, uint256 amount, address to) external override onlyTrusted {
        _modify(pid, to, amount.toInt256(), false);

        if (amount > 0) _farms[pid].token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Deposits tokens to a farm.
     * @param pid The pool ID of the farm.
     * @param amount The amount of tokens to deposit.
     */
    function deposit(uint256 pid, uint256 amount) external override {
        _modify(pid, msg.sender, amount.toInt256(), false);

        if (amount > 0) _farms[pid].token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Withdraws tokens from a farm.
     * @param pid The pool ID of the farm.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(uint256 pid, uint256 amount) external override {
        _modify(pid, msg.sender, -amount.toInt256(), true);

        if (amount > 0) _farms[pid].token.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Claims the rewards from a list of farms.
     * @param pids The pool IDs of the farms.
     */
    function claim(uint256[] calldata pids) external override {
        for (uint256 i; i < pids.length; ++i) {
            _modify(pids[i], msg.sender, 0, true);
        }
    }

    /**
     * @dev Emergency withdraws tokens from a farm, without claiming any rewards.
     * @param pid The pool ID of the farm.
     */
    function emergencyWithdraw(uint256 pid) external override {
        Farm storage farm = _farms[pid];

        uint256 balance = farm.amounts.getAmountOf(msg.sender);
        int256 deltaAmount = -balance.toInt256();

        farm.amounts.update(msg.sender, deltaAmount);

        farm.token.safeTransfer(msg.sender, balance);

        emit PositionModified(pid, msg.sender, deltaAmount, 0);
    }

    /**
     * @dev Updates all the farms in the pids list.
     * @param pids The pool IDs to update.
     */
    function updateAll(uint256[] calldata pids) external override {
        _updateAll(pids);
    }

    /**
     * @dev Sets the LUM per second.
     * It will update all the farms that are in the top pool IDs.
     * @param lumPerSecond The new LUM per second.
     */
    function setLumPerSecond(uint96 lumPerSecond) external override onlyOwner {
        if (lumPerSecond > Constants.MAX_LUM_PER_SECOND) revert MasterChef__InvalidLumPerSecond();

        // _updateAll(_voter.getTopPoolIds()); // todo remove this

        _lumPerSecond = lumPerSecond;

        emit LumPerSecondSet(lumPerSecond);
    }

    /**
     * @dev Adds a farm.
     * @param token The token of the farm.
     * @param extraRewarder The extra rewarder of the farm.
     */
    function add(IERC20 token, IMasterChefRewarder extraRewarder) external override {
        if (msg.sender != address(_lbHooksManager)) _checkOwnerOrOperator();
        
        //_checkOwner(); // || msg.sender != address(_voter)

        uint256 pid = _farms.length;

        Farm storage farm = _farms.push();

        farm.token = token;
        farm.rewarder.lastUpdateTimestamp = block.timestamp;

        if (address(extraRewarder) != address(0)) _setExtraRewarder(pid, extraRewarder);

        token.balanceOf(address(this)); // sanity check

        emit FarmAdded(pid, token);
    }

    /**
     * @dev Sets the extra rewarder of a farm.
     * @param pid The pool ID of the farm.
     * @param extraRewarder The new extra rewarder of the farm.
     */
    function setExtraRewarder(uint256 pid, IMasterChefRewarder extraRewarder) external override onlyOwner {
        _setExtraRewarder(pid, extraRewarder);
    }

    /**
     * @dev Sets the treasury.
     * @param treasury The new treasury.
     */
    function setTreasury(address treasury) external override onlyOwner {
        _setTreasury(treasury);
    }

    /**
     * @dev Sets voter
     * @param voter The new voter.
     */
    function setVoter(IVoter voter) external override onlyOwner {
        if (address(voter) == address(0)) revert MasterChef__ZeroAddress();

        _voter = voter;

        emit VoterSet(voter);
    }

    /**
     * @dev Sets trustee
     * @param trustee The new trustee.
     */
    function setTrustee(address trustee) external onlyOwner {
        _trustee = trustee;

        emit TrusteeSet(trustee);
    }

    /**
     * @dev Sets mintLum. If true this will mint new lum, on false this will just emit
     * @param mintLum The new mintLum.
     */
    function setMintLum(bool mintLum) external onlyOwner {
        _mintLUM = mintLum;

        emit MintLumSet(mintLum);
    }

    /**
     * @dev Updates the operator.
     * @param operator The new operator.
     */
    function updateOperator(address operator) external onlyOwner {
        _operator = operator;
        emit OperatorUpdated(operator);
    }

    /**
     * @dev Blocks the renouncing of ownership.
     */
    function renounceOwnership() public pure override {
        revert MasterChef__CannotRenounceOwnership();
    }

    /**
     * @dev Returns the reward for a given pool ID.
     * If the pool ID is not in the top pool IDs, it will return 0.
     * Else, it will return the reward multiplied by the weight of the pool ID over the total weight.
     * @param rewarder The storage pointer to the rewarder.
     * @param pid The pool ID.
     * @param totalSupply The total supply.
     * @return The reward for the pool ID.
     */
    function _getRewardForPid(Rewarder.Parameter storage rewarder, uint256 pid, uint256 totalSupply)
        private
        view
        returns (uint256)
    {
        return _getRewardForPid(pid, rewarder.getTotalRewards(_lumPerSecond, totalSupply), _voter.getTotalWeight());
    }

    /**
     * @dev Returns the reward for a given pool ID.
     * If the pool ID is not in the top pool IDs, it will return 0.
     * Else, it will return the reward multiplied by the weight of the pool ID over the total weight.
     * @param pid The pool ID.
     * @param totalRewards The total rewards.
     * @param totalWeight The total weight.
     * @return The reward for the pool ID.
     */
    function _getRewardForPid(uint256 pid, uint256 totalRewards, uint256 totalWeight) private view returns (uint256) {
        return totalWeight == 0 ? 0 : totalRewards * _voter.getWeight(pid) / totalWeight;
    }

    /**
     * @dev Sets the extra rewarder of a farm.
     * Will call link/unlink to make sure the rewarders are properly set/unset.
     * It is very important that a rewarder that was previously linked can't be linked again.
     * @param pid The pool ID of the farm.
     * @param extraRewarder The new extra rewarder of the farm.
     */
    function _setExtraRewarder(uint256 pid, IMasterChefRewarder extraRewarder) private {
        if (
            address(extraRewarder) != address(0)
                && _rewarderFactory.getRewarderType(extraRewarder) != IRewarderFactory.RewarderType.MasterChefRewarder
        ) {
            revert MasterChef__NotMasterchefRewarder();
        }

        IMasterChefRewarder oldExtraRewarder = _farms[pid].extraRewarder;

        if (address(oldExtraRewarder) != address(0)) oldExtraRewarder.unlink(pid);
        if (address(extraRewarder) != address(0)) extraRewarder.link(pid);

        _farms[pid].extraRewarder = extraRewarder;

        emit ExtraRewarderSet(pid, extraRewarder);
    }

    /**
     * @dev Updates all the farms in the pids list.
     * @param pids The pool IDs to update.
     */
    function _updateAll(uint256[] memory pids) private {
        uint256 length = pids.length;

        uint256 totalWeight = _voter.getTotalWeight();
        uint256 lumPerSecond = _lumPerSecond;

        for (uint256 i; i < length; ++i) {
            uint256 pid = pids[i];

            Farm storage farm = _farms[pid];
            Rewarder.Parameter storage rewarder = farm.rewarder;

            uint256 totalSupply = farm.amounts.getTotalAmount();
            uint256 totalRewards = rewarder.getTotalRewards(lumPerSecond, totalSupply);

            uint256 totalLumRewardForPid = _getRewardForPid(pid, totalRewards, totalWeight);
            uint256 lumRewardForPid = _mintLum(totalLumRewardForPid);

            rewarder.updateAccDebtPerShare(totalSupply, lumRewardForPid);
        }
    }

    /**
     * @dev Modifies the position of an account on a farm.
     * @param pid The pool ID of the farm.
     * @param account The account to modify the position of.
     * @param deltaAmount The delta amount to modify the position with.
     * @param isPayOutReward If true, the rewards will be paid out, otherwise accrued
     */
    function _modify(uint256 pid, address account, int256 deltaAmount, bool isPayOutReward) private {
        Farm storage farm = _farms[pid];
        Rewarder.Parameter storage rewarder = farm.rewarder;
        IMasterChefRewarder extraRewarder = farm.extraRewarder;

        (uint256 oldBalance, uint256 newBalance, uint256 oldTotalSupply,) = farm.amounts.update(account, deltaAmount);

        uint256 totalLumRewardForPid = _getRewardForPid(rewarder, pid, oldTotalSupply);
        uint256 lumRewardForPid = _mintLum(totalLumRewardForPid);

        uint256 lumReward = rewarder.update(account, oldBalance, newBalance, oldTotalSupply, lumRewardForPid);

        if (isPayOutReward) {
            lumReward = lumReward + unclaimedRewards[pid][account];
            unclaimedRewards[pid][account] = 0;
            if (lumReward > 0) _lum.safeTransfer(account, lumReward);
        } else {
            unclaimedRewards[pid][account] += lumReward;
        }

        if (address(extraRewarder) != address(0)) {
            extraRewarder.onModify(account, pid, oldBalance, newBalance, oldTotalSupply);
        }

        emit PositionModified(pid, account, deltaAmount, lumReward);
    }

    /**
     * @dev Sets the treasury.
     * @param treasury The new treasury.
     */
    function _setTreasury(address treasury) private {
        if (treasury == address(0)) revert MasterChef__ZeroAddress();

        _treasury = treasury;

        emit TreasurySet(treasury);
    }

    /**
     * @dev Mints LUM tokens to the treasury and to this contract if _mintLum is true.
     * If _mintLum is false the contract needs to be funded with LUM tokens.
     * @param amount The amount of LUM tokens to mint.
     * @return The amount of LUM tokens minted for liquidity mining.
     */
    function _mintLum(uint256 amount) private returns (uint256) {
        if (amount == 0) return 0;

        (uint256 treasuryAmount, uint256 liquidityMiningAmount) = _calculateAmounts(amount);

        if (!_mintLUM) {
            _lum.safeTransfer(_treasury, treasuryAmount);
            return liquidityMiningAmount;
        }

        _lum.mint(_treasury, treasuryAmount);
        return _lum.mint(address(this), liquidityMiningAmount);
    }

    /**
     * @dev Calculates the amounts of MOE tokens to mint for each recipient.
     * @param amount The amount of MOE tokens to mint.
     * @return treasuryAmount The amount of MOE tokens to mint for the treasury.
     * @return liquidityMiningAmount The amount of MOE tokens to mint for liquidity mining.
     */
    function _calculateAmounts(uint256 amount)
        private
        view
        returns (uint256 treasuryAmount, uint256 liquidityMiningAmount)
    {
        treasuryAmount = amount * _treasuryShare / Constants.PRECISION;
        liquidityMiningAmount = amount - treasuryAmount;
    }

    function _checkOwnerOrOperator() private view {
        if (msg.sender != address(_operator)) _checkOwner();
    }
}
