// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPair} from "../interfaces/IPair.sol";
import {IAPIConsumer} from "../interfaces/IOracle.sol";
import {Structs} from "../utils/dexErrors.sol";

contract Router is ReentrancyGuard {

    using Math for uint256;

    IAPIConsumer public immutable priceOracle;

    address public factory;
    address public USTY;
    uint256 public totalFee = 3;
    uint256 public threshold = 90;

    event LiquidityAdded(address indexed pair, uint256 amountA, uint256 amountB, uint256 liquidity);
    event LiquidityRemoved(address indexed pair, uint256 amountA, uint256 amountB);
    event SwapExecuted(address indexed pair, address indexed to, uint256 amountIn, uint256 amountOut);

    constructor(address _factory, address _usyt, address _oracle) {
        priceOracle = IAPIConsumer(_oracle);
        factory = _factory;
        USTY = _usyt;
    }

    modifier ensure(address tokenA, address tokenB) {
        require(tokenA != tokenB, "Router: IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "Router: ZERO_ADDRESS");
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

        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        (amountA, amountB) = IPair(pair).burn(msg.sender, liquidity);

        emit LiquidityRemoved(pair, amountA, amountB);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        address[] calldata _path,
        address to,
        uint256 slippage,
        uint256 deadline
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Router: EXPIRED");
        require(_path.length == 2, "Router: INVALID_PATH");

        (address[] memory path, bool isEtkPath) = _adjustPath(_path);
        address inputToken = path[0];
        address outputToken = path[path.length - 1];

        if (isEtkPath) {
            address[] memory newAPath = path;
            newAPath[0] = inputToken;
            newAPath[1] = USTY;
            IERC20(inputToken).transferFrom(msg.sender, _pairFor(inputToken, USTY), amountIn);
            _swap(newAPath, address(this), slippage);

            uint256 etkBalance = IERC20(USTY).balanceOf(address(this));

            address[] memory newBPath = path;
            newBPath[0] = USTY;
            newBPath[1] = outputToken;
            IERC20(USTY).transfer(_pairFor(USTY, outputToken), etkBalance);
            _swap(newBPath, to, slippage);
        } else {
            IERC20(inputToken).transferFrom(msg.sender, _pairFor(inputToken, outputToken), amountIn);
            _swap(path, to, slippage);
        }

        uint256 amountOut = IERC20(outputToken).balanceOf(to);
        emit SwapExecuted(_pairFor(inputToken, path[1]), to, amountIn, amountOut);
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

        (params.amountIn, params.amountOut, params.feeAmount) = _getAmounts(params.input, params.output, params.pair);
        (params.amount0Out, params.amount1Out) = _getSwapOutputs(params.input, params.amountOut, params.pair);
        (params.fee0, params.fee1) = _getSwapOutputs(params.input, params.feeAmount, params.pair);

        params.recipient = _getRecipient(i, pathLength, _to, params.output, path);
        return params;
    }

    function _getAmounts(address input, address output, address pair) 
        private 
        view 
        returns (uint256 amountIn, uint256 amountOut, uint256 feeAmount) 
    {
        (uint112 reserve0, uint112 reserve1,) = IPair(pair).getReserves();

        (uint256 reserveIn, uint256 reserveOut) = input == IPair(pair).token0()
            ? (reserve0, reserve1) 
            : (reserve1, reserve0);

        amountIn = IERC20(input).balanceOf(pair) - reserveIn;
        
        (amountOut, feeAmount) = _getAmountOut(amountIn, reserveIn, reserveOut, input, output);
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

    function _getAmountOut(
        uint256 amountIn, 
        uint256 reserveIn, 
        uint256 reserveOut,
        address tokenIn, 
        address tokenOut
    ) private view returns (uint256 amountOut, uint256 feeAmount) {
        require(amountIn > 0, "Router: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Router: INSUFFICIENT_LIQUIDITY");

        Structs.AmountOutParams memory params;
        params.amountIn = amountIn;
        params.reserveIn = reserveIn;
        params.reserveOut = reserveOut;

        (params.priceIn, params.priceOut) = getSpotPrice(tokenIn, tokenOut);

        params.feeToPortion = IFactory(factory).feePercentage();
        params.lpFee = totalFee - params.feeToPortion;
        
        params.feeAmount = params.amountIn.mulDiv(params.feeToPortion, 1000, Math.Rounding.Floor);
        params.amountInWithFee = params.amountIn.mulDiv(1000 - params.lpFee, 1000, Math.Rounding.Floor);

        params.effectiveAmountIn = params.amountInWithFee.mulDiv(params.priceIn, params.priceOut, Math.Rounding.Floor);
        
        params.amountOut = reserveOut.mulDiv(params.effectiveAmountIn, reserveIn + params.effectiveAmountIn, Math.Rounding.Floor);
        
        return (params.amountOut, params.feeAmount);
    }

    function getSpotPrice(address tokenA, address tokenB) public view returns (uint256 priceA, uint256 priceB) {
        (uint256 oraclePriceA, uint256 lastUpdatedA) = priceOracle.getLastUpdatedPrice(tokenA);
        (uint256 oraclePriceB, uint256 lastUpdatedB) = priceOracle.getLastUpdatedPrice(tokenB);

        require ((lastUpdatedA >= block.timestamp - threshold) && (lastUpdatedB >= block.timestamp - threshold), "Router: thresholdExceeded");

        if (oraclePriceA > 0 && oraclePriceB > 0) {
            return (oraclePriceA, oraclePriceB);
        }   
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

    function _optimalAmounts(
        address pair,
        uint256 amountADesired,
        uint256 amountBDesired
    ) private view returns (uint256 amountA, uint256 amountB) {
        (uint112 reserveA, uint112 reserveB,) = IPair(pair).getReserves();
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = amountADesired.mulDiv(reserveB, reserveA, Math.Rounding.Floor);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = amountBDesired.mulDiv(reserveA, reserveB, Math.Rounding.Floor);
                require(amountAOptimal <= amountADesired, "Router: INSUFFICIENT_LIQUIDITY");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _adjustPath(address[] memory _path) private view returns (address[] memory, bool) {
        address[] memory path = _path;
        bool isEtkPath;

        if (_pairFor(_path[0], _path[1]) != address(0)) {
            isEtkPath = false;
            return (_path, isEtkPath);
        }

        if (_pairFor(_path[0], USTY) != address(0) && _pairFor(USTY, _path[1]) != address(0)) {
            isEtkPath = true;
        } else {
            revert("Router: NO_SWAP_PATH_AVAILABLE");
        }

        return (path, isEtkPath);
    }
}