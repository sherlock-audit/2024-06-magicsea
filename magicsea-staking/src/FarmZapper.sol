// SPDX-License-Identifier: GPLv2

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.

// @author Wivern for Beefy.Finance
// @notice This contract adds liquidity to Uniswap V2 compatible liquidity pair pools and stake.

pragma solidity >=0.8.4;

import "openzeppelin/access/Ownable.sol";

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import "./interfaces/IMagicSeaPair.sol";
import "./interfaces/IMagicSeaRouter02.sol";
import "./interfaces/IWNATIVE.sol";
import "./interfaces/IMasterChef.sol";

/**
 * @dev FarmZapper let's you directly zap-in into a farm
 *
 * Inspired by Beefy's beefyUniswapZap
 */
contract FarmZapper is Ownable {
    using SafeERC20 for IERC20;

    IMagicSeaRouter02 private immutable _router;
    IMasterChef private immutable _masterChef;
    address private immutable _wNative;
    uint256 private immutable _minimumAmount;

    event SwapAndStaked(uint256 indexed pid, address indexed tokenIn, uint256 amountLiquidity, address sender);

    constructor(address router, address masterchef, address wNative, uint256 minimumAmount, address admin)
        Ownable(admin)
    {
        require(IMagicSeaRouter02(router).WETH() == wNative, "FarmZapper: wNative address not matching Router.WETH()");

        _router = IMagicSeaRouter02(router);
        _masterChef = IMasterChef(masterchef);
        _wNative = wNative;
        _minimumAmount = minimumAmount;
    }

    // EXTERNAL PAYABLE FUNCTIONS

    receive() external payable {
        assert(msg.sender == _wNative);
    }

    /**
     * @dev Zap in native token (WNATIVE) to a given pool pid
     */
    function zapInWNative(uint256 pid, uint256 tokenAmountOutMin) external payable {
        require(msg.value >= _minimumAmount, "FarmZapper: Insignificant input amount");

        IWNATIVE(_wNative).deposit{value: msg.value}();

        _swapAndStake(pid, tokenAmountOutMin, _wNative);
    }

    // EXTERNAL FUNCTIONS

    /**
     * @dev Zap in a ERC20 token to a given pid, amount and amountOutMin
     */
    function zapIn(uint256 pid, uint256 tokenAmountOutMin, address tokenIn, uint256 tokenInAmount) external {
        require(tokenInAmount >= _minimumAmount, "FarmZapper: Insignificant input amount");
        require(
            IERC20(tokenIn).allowance(msg.sender, address(this)) >= tokenInAmount, "Beefy: Input token is not approved"
        );

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);

        _swapAndStake(pid, tokenAmountOutMin, tokenIn);
    }

    /**
     * @dev Zap out from LP Token. Burns the LP and return both assets of the given pair
     */
    function zapOut(address lpToken, uint256 withdrawAmount, uint256 amountOutAMin, uint256 amountOutBMin) external {
        IMagicSeaPair pair = _getPair(lpToken);

        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), withdrawAmount);

        uint256 amount0;
        uint256 amount1;
        if (pair.token0() != _wNative && pair.token1() != _wNative) {
            (amount0, amount1) = _removeLiquidity(address(pair), msg.sender);
            require(amount0 >= amountOutAMin, "MagicSeaRouter: INSUFFICIENT_A_AMOUNT");
            require(amount1 >= amountOutBMin, "MagicSeaRouter: INSUFFICIENT_B_AMOUNT");
            return;
        }

        (amount0, amount1) = _removeLiquidity(address(pair), address(this));
        require(amount0 >= amountOutAMin, "MagicSeaRouter: INSUFFICIENT_A_AMOUNT");
        require(amount1 >= amountOutBMin, "MagicSeaRouter: INSUFFICIENT_B_AMOUNT");

        address[] memory tokens = new address[](2);
        tokens[0] = pair.token0();
        tokens[1] = pair.token1();

        _returnAssets(tokens);
    }

    /**
     * @dev Zap out from LP Token and swap it to a destination token of the given pair
     */
    function zapOutAndSwap(address lpToken, uint256 withdrawAmount, address desiredToken, uint256 desiredTokenOutMin)
        external
    {
        IMagicSeaPair pair = _getPair(lpToken);
        address token0 = pair.token0();
        address token1 = pair.token1();
        require(
            token0 == desiredToken || token1 == desiredToken, "FarmZapper: desired token not present in liquidity pair"
        );

        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), withdrawAmount);

        _removeLiquidity(address(pair), address(this));

        address swapToken = token1 == desiredToken ? token0 : token1;
        address[] memory path = new address[](2);
        path[0] = swapToken;
        path[1] = desiredToken;

        _approveTokenIfNeeded(path[0], address(_router));
        _router.swapExactTokensForTokens(
            IERC20(swapToken).balanceOf(address(this)), desiredTokenOutMin, path, address(this), block.timestamp
        );

        _returnAssets(path);
    }

    // OWNER FUNCTIONS

    function releaseStuckToken(address _token) external onlyOwner {
        require(_token != address(0), "cant be zero");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    // PUBLIC VIEW FUNCTIONS

    function getRouter() external view returns (IMagicSeaRouter02) {
        return _router;
    }

    function getMasterChef() external view returns (IMasterChef) {
        return _masterChef;
    }

    function getWNative() external view returns (address) {
        return _wNative;
    }

    function getMinimumAmount() external view returns (uint256) {
        return _minimumAmount;
    }

    function estimateSwap(uint256 pid, address tokenIn, uint256 fullInvestmentIn)
        public
        view
        returns (uint256 swapAmountIn, uint256 swapAmountOut, address swapTokenOut)
    {
        checkWETH();
        IMagicSeaPair pair = _getMasterChefPair(pid);

        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, "FarmZapper: Input token not present in liquidity pair");

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        (reserveA, reserveB) = isInputA ? (reserveA, reserveB) : (reserveB, reserveA);

        swapAmountIn = _getSwapAmount(fullInvestmentIn, reserveA, reserveB, pair.feeAmount());
        swapAmountOut = _router.getAmountOut(swapAmountIn, reserveA, reserveB, pair.feeAmount());
        swapTokenOut = isInputA ? pair.token1() : pair.token0();
    }

    function checkWETH() public view returns (bool isValid) {
        isValid = _wNative == _router.WETH();
        require(isValid, "FarmZapper: WETH address not matching Router.WETH()");
    }

    // PRIVATE FUNCTIONS

    function _removeLiquidity(address pair, address to) private returns (uint256 amount0, uint256 amount1) {
        IERC20(pair).safeTransfer(pair, IERC20(pair).balanceOf(address(this)));
        (amount0, amount1) = IMagicSeaPair(pair).burn(to);

        require(amount0 >= _minimumAmount, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        require(amount1 >= _minimumAmount, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
    }

    function _getMasterChefPair(uint256 pid) private view returns (IMagicSeaPair pair) {
        require(_masterChef.getNumberOfFarms() > pid, "no valid pid");

        pair = IMagicSeaPair(address(_masterChef.getToken(pid)));
        require(pair.factory() == _router.factory(), "FarmZapper: Incompatible liquidity pair factory");
    }

    function _getPair(address lpToken) private view returns (IMagicSeaPair pair) {
        pair = IMagicSeaPair(lpToken);
        require(pair.factory() == _router.factory(), "FarmZapper: Incompatible liquidity pair factory");
    }

    function _swapAndStake(uint256 pid, uint256 tokenAmountOutMin, address tokenIn) private {
        IMagicSeaPair pair = _getMasterChefPair(pid);

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        require(reserveA > _minimumAmount && reserveB > _minimumAmount, "FarmZapper: Liquidity pair reserves too low");

        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, "FarmZapper: Input token not present in liquidity pair");

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = isInputA ? pair.token1() : pair.token0();

        uint256 fullInvestment = IERC20(tokenIn).balanceOf(address(this));
        uint256 swapAmountIn;
        if (isInputA) {
            swapAmountIn = _getSwapAmount(fullInvestment, reserveA, reserveB, pair.feeAmount());
        } else {
            swapAmountIn = _getSwapAmount(fullInvestment, reserveB, reserveA, pair.feeAmount());
        }

        _approveTokenIfNeeded(path[0], address(_router));
        uint256[] memory swapedAmounts =
            _router.swapExactTokensForTokens(swapAmountIn, tokenAmountOutMin, path, address(this), block.timestamp);

        _approveTokenIfNeeded(path[1], address(_router));
        (,, uint256 amountLiquidity) = _router.addLiquidity(
            path[0],
            path[1],
            fullInvestment - (swapedAmounts[0]),
            swapedAmounts[1],
            1,
            1,
            address(this),
            block.timestamp
        );

        _approveTokenIfNeeded(address(pair), address(_masterChef));
        _masterChef.depositOnBehalf(pid, amountLiquidity, msg.sender);

        _returnAssets(path);

        emit SwapAndStaked(pid, tokenIn, amountLiquidity, msg.sender);
    }

    function _returnAssets(address[] memory tokens) private {
        uint256 balance;
        for (uint256 i; i < tokens.length; i++) {
            balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                if (tokens[i] == _wNative) {
                    IWNATIVE(_wNative).withdraw(balance);
                    (bool success,) = msg.sender.call{value: balance}(new bytes(0));
                    require(success, "FarmZapper: ETH transfer failed");
                } else {
                    IERC20(tokens[i]).safeTransfer(msg.sender, balance);
                }
            }
        }
    }

    function _getSwapAmount(uint256 investmentA, uint256 reserveA, uint256 reserveB, uint256 feeAmount)
        private
        view
        returns (uint256 swapAmount)
    {
        uint256 halfInvestment = investmentA / 2;
        uint256 nominator = _router.getAmountOut(halfInvestment, reserveA, reserveB, feeAmount);
        uint256 denominator = _router.quote(halfInvestment, reserveA + (halfInvestment), reserveB - (nominator));
        swapAmount = investmentA - (FixedPointMathLib.sqrt((halfInvestment * halfInvestment * nominator) / denominator));
    }

    function _approveTokenIfNeeded(address token, address spender) private {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).approve(spender, type(uint256).max);
        }
    }
}
