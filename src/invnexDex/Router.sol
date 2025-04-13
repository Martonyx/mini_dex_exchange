// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPair} from "../interfaces/IPair.sol";
import {Structs, DexErrors} from "../utils/DexUtils.sol";

contract Router is ReentrancyGuard, DexErrors {

    using Math for uint256;

    address public factory;
    address public USYT;
    uint256 constant DENOMINATOR = 1000;
    uint256 constant TOTAL_FEE = 3;
    uint256 constant MAX_SLIPPAGE = 1000;
    uint256 constant MIN_SLIPPAGE = 5;
    uint256 constant DECIMALS = 1e18;

    event LiquidityAdded(address indexed pair, uint256 amountA, uint256 amountB, uint256 liquidity);
    event LiquidityRemoved(address indexed pair, uint256 amountA, uint256 amountB);
    event SwapExecuted(address indexed to, uint256 amountIn, uint256 amountOut);

    constructor(address _factory, address _usyt) {
        factory = _factory;
        USYT = _usyt;
    }

    modifier ensure(address tokenA, address tokenB) {
        if (tokenA == tokenB) revert Router_IdenticalAddresses();
        if (tokenA == address(0) || tokenB == address(0)) revert Router_ZeroAddress();
        _;
    }

    modifier ensureDeadline(uint256 _deadline) {
        if (block.timestamp > _deadline) revert Router_DeadlineExpired();
        _;
    }

    function _sortTokens(address tokenA, address tokenB) ensure(tokenA, tokenB) private pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _pairFor(address tokenA, address tokenB) private view returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = IFactory(factory).getPair(token0, token1);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external nonReentrant ensure(tokenA, tokenB) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        address pair = IFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = IFactory(factory).createPair(tokenA, tokenB);
        }

        (amountA, amountB) = _optimalAmounts(pair, amountADesired, amountBDesired);

        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);

        liquidity = IPair(pair).mint(msg.sender);
        emit LiquidityAdded(pair, amountA, amountB, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external nonReentrant ensure(tokenA, tokenB) returns (uint256 amountA, uint256 amountB) {
        address pair = _pairFor(tokenA, tokenB);

        (amountA, amountB) = IPair(pair).burn(msg.sender, liquidity);

        emit LiquidityRemoved(pair, amountA, amountB);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        address[] calldata _path,
        address to,
        uint256 slippage,
        uint256 _deadline
    ) external nonReentrant ensureDeadline(_deadline) {
        if (_path.length != 2) revert Router_InvalidPath();

        (address[] memory path, bool isUSYTPath) = _adjustPath(_path);
        Structs.UserParams memory params;
        params.inputToken = path[0];
        params.outputToken = path[path.length - 1];
        params.balanceBefore = IERC20(params.outputToken).balanceOf(to);

        if (isUSYTPath) {
            address[] memory newAPath = new address[](2);
            newAPath[0] = params.inputToken;
            newAPath[1] = USYT;
            IERC20(params.inputToken).transferFrom(msg.sender, _pairFor(params.inputToken, USYT), amountIn);
            _swap(newAPath, address(this), slippage);

            uint256 USYTBalance = IERC20(USYT).balanceOf(address(this));

            address[] memory newBPath = new address[](2);
            newBPath[0] = USYT;
            newBPath[1] = params.outputToken;
            IERC20(USYT).transfer(_pairFor(USYT, params.outputToken), USYTBalance);
            _swap(newBPath, to, slippage);
        } else {
            IERC20(params.inputToken).transferFrom(msg.sender, _pairFor(params.inputToken, params.outputToken), amountIn);
            _swap(path, to, slippage);
        }
    
        params.amountOut = IERC20(params.outputToken).balanceOf(to) - params.balanceBefore;
        emit SwapExecuted(to, amountIn, params.amountOut);
    }

    function _swap(address[] memory path, address _to, uint256 slippage) private {
        uint256 pathLength = path.length;
        for (uint256 i = 0; i < pathLength - 1; i++) {
            Structs.BeforeSwapParams memory Bparams = _prepareSwapParams(i, path, _to, pathLength);
            Structs.PairSwapParams memory params;
            params.amount0Out = Bparams.amount0Out;
            params.amount1Out = Bparams.amount1Out;
            params.fee0 = Bparams.fee0;
            params.fee1 = Bparams.fee1;
            params.recipient = Bparams.recipient;
            params.slippageTolerance = slippage;
            params.minAmount0Out = calculateSlippage(params.amount0Out, params.slippageTolerance);
            params.minAmount1Out = calculateSlippage(params.amount1Out, params.slippageTolerance);

            if (params.amount0Out < params.minAmount0Out) revert Router_SlippageExceeded();
            if (params.amount1Out < params.minAmount1Out) revert Router_SlippageExceeded();
            IPair(Bparams.pair).swap(params);
        }
    }

    function _prepareSwapParams(uint256 i, address[] memory path, address _to, uint256 pathLength)
        private
        view
        returns (Structs.BeforeSwapParams memory params)
    {
        params.input = path[i];
        params.output = path[i + 1];
        params.pair = _pairFor(params.input, params.output);

        (params.amountIn, params.amountOut, params.feeAmount) = _getAmounts(params.input, params.pair);
        (params.amount0Out, params.amount1Out) = _getSwapOutputs(params.input, params.amountOut, params.pair);
        (params.fee0, params.fee1) = _getFeesOutputs(params.input, params.feeAmount, params.pair);

        params.recipient = _getRecipient(i, pathLength, _to, params.output, path);
        return params;
    }

    function _getAmounts(address input, address pair) 
        private 
        view 
        returns (uint256 amountIn, uint256 amountOut, uint256 feeAmount) 
    {
        (uint112 reserve0, uint112 reserve1,) = IPair(pair).getReserves();

        (uint256 reserveIn, uint256 reserveOut) = input == IPair(pair).token0()
            ? (reserve0, reserve1) 
            : (reserve1, reserve0);

        amountIn = IERC20(input).balanceOf(pair) - reserveIn;

        (amountOut, feeAmount) = _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function _getSwapOutputs(
        address input,
        uint256 amountOut,
        address pair
    ) private view returns (uint256 amount0Out, uint256 amount1Out) {
        address token0 = IPair(pair).token0();
        (amount0Out, amount1Out) = input == token0
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));
    }

    function _getFeesOutputs(
        address input,
        uint256 feeOut,
        address pair
    ) private view returns (uint256 fee0Out, uint256 fee1Out) {
        address token0 = IPair(pair).token0();
        (fee0Out, fee1Out) = input == token0
            ? (feeOut, uint256(0))
            : (uint256(0), feeOut);
    }

    function _getAmountOut(
        uint256 amountIn, 
        uint256 reserveIn, 
        uint256 reserveOut
    ) private view returns (uint256 amountOut, uint256 feeAmount) {
        if (amountIn <= 0) revert Router_InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert Router_InsufficientLiquidity();

        Structs.AmountOutParams memory params;
        params.reserveIn = reserveIn;
        params.reserveOut = reserveOut;

        params.feeToPortion = IFactory(factory).feePercentage();
        params.lpFee = TOTAL_FEE - params.feeToPortion;
        
        params.feeAmount = amountIn.mulDiv(params.feeToPortion, DENOMINATOR);
        params.amountIn = amountIn - params.feeAmount;
        params.amountInWithFee = params.amountIn.mulDiv(DENOMINATOR - params.lpFee, DENOMINATOR);
        
        params.amountOut = reserveOut.mulDiv(params.amountInWithFee, reserveIn + params.amountInWithFee);
        
        return (params.amountOut, params.feeAmount);
    }

    function getSpotPriceAandB(address tokenA, address tokenB) public view returns (uint256 priceA, uint256 priceB) {
        address pair = _pairFor(tokenA, tokenB);
        if (pair == address(0)) revert Router_NOT_LISTED_IN_THE_DEX();
        (uint112 reserveA, uint112 reserveB,) = IPair(pair).getReserves();
        if (reserveA == 0 || reserveB == 0) revert Router_InsufficientLiquidity();
        
        priceA = (reserveB * DECIMALS) / reserveA;
        priceB = (reserveA * DECIMALS) / reserveB;
        
        return (priceA, priceB);
    }

    function getSpotPriceInUSYT(address token) public view returns (uint256 priceInUSYT) {
        address pair = _pairFor(token, USYT);
        if (pair == address(0)) revert Router_NOT_LISTED_IN_THE_DEX();
        
        (uint112 reserveToken, uint112 reserveUSYT,) = IPair(pair).getReserves();
        if (reserveToken == 0 || reserveUSYT == 0) revert Router_InsufficientLiquidity();
        
        priceInUSYT = (reserveUSYT * DECIMALS) / reserveToken;
        
        return priceInUSYT;
    }

    function _getRecipient(
        uint256 i,
        uint256 pathLength,
        address _to,
        address output,
        address[] memory path
    ) private view returns (address) {
        return i == pathLength - 2 ? _to : _pairFor(output, path[i + 2]);
    }

    function calculateSlippage(
        uint256 amountOut, 
        uint256 slippageTolerance
    ) internal pure returns (uint256 minAmountOut) {
        if (slippageTolerance > MAX_SLIPPAGE) revert Router_InvalidSlippageTolerance();
        if (slippageTolerance < MIN_SLIPPAGE) revert Router_InvalidSlippageTolerance();
        minAmountOut = amountOut * (MAX_SLIPPAGE - slippageTolerance) / MAX_SLIPPAGE;
    }

    function _optimalAmounts(
        address pair,
        uint256 amountADesired,
        uint256 amountBDesired
    ) private view returns (uint256 amountA, uint256 amountB) {
        (uint112 reserveA, uint112 reserveB,) = IPair(pair).getReserves();
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = amountADesired.mulDiv(reserveB, reserveA);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = amountBDesired.mulDiv(reserveA, reserveB);
                if(amountAOptimal > amountADesired) revert Router_InsufficientLiquidity();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _adjustPath(address[] memory _path) private view returns (address[] memory, bool) {
        if (_pairFor(_path[0], _path[1]) != address(0)) {
            return (_path, false);
        }

        if (_pairFor(_path[0], USYT) != address(0) && _pairFor(USYT, _path[1]) != address(0)) {
            return (_path, true);
        } else {
            revert Router_NO_SWAP_PATH_AVAILABLE();
        }
    }

    function getPairAddress(address tokenA, address tokenB) external view returns (address pair) {
        pair = _pairFor(tokenA, tokenB);
        if (pair == address(0)) revert Router_PairNotExists();

        return pair;
    }
}