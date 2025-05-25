// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPair} from "../interfaces/IPair.sol";
import {Pair} from "./Pair.sol";
import {Structs, DexErrors} from "../utils/DexUtils.sol";

contract Router is ReentrancyGuard, DexErrors {

    using Math for uint256;
    using SafeERC20 for IERC20;

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

    modifier OnlyFeeToSetter(){
        if(msg.sender != IFactory(factory).feeToSetter()) revert Router_Unauthorized();
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
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) external nonReentrant ensure(tokenA, tokenB) ensureDeadline(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        address pair = IFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) revert Router_NOT_LISTED_IN_THE_DEX();

        (amountA, amountB) = _optimalAmounts(pair, amountADesired, amountBDesired);
        _validateAmounts(amountA, amountB, amountAMin, amountBMin);
        _transferTokensToPair(tokenA, tokenB, pair, amountA, amountB);

        liquidity = IPair(pair).mint(msg.sender);
        emit LiquidityAdded(pair, amountA, amountB, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) external nonReentrant ensure(tokenA, tokenB) ensureDeadline(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = _pairFor(tokenA, tokenB);

        (amountA, amountB) = IPair(pair).burn(msg.sender, liquidity);
        _validateAmounts(amountA, amountB, amountAMin, amountBMin);

        emit LiquidityRemoved(pair, amountA, amountB);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        address[] calldata _path,
        address to,
        uint256 amountAMin,
        uint256 amountBMin,
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
            IERC20(params.inputToken).safeTransferFrom(msg.sender, _pairFor(params.inputToken, USYT), amountIn);
            _swap(newAPath, address(this), amountAMin, amountBMin);

            uint256 USYTBalance = IERC20(USYT).balanceOf(address(this));

            address[] memory newBPath = new address[](2);
            newBPath[0] = USYT;
            newBPath[1] = params.outputToken;
            IERC20(USYT).safeTransfer(_pairFor(USYT, params.outputToken), USYTBalance);
            _swap(newBPath, to, amountAMin, amountBMin);
        } else {
            IERC20(params.inputToken).safeTransferFrom(msg.sender, _pairFor(params.inputToken, params.outputToken), amountIn);
            _swap(path, to, amountAMin, amountBMin);
        }
    
        params.amountOut = IERC20(params.outputToken).balanceOf(to) - params.balanceBefore;
        emit SwapExecuted(to, amountIn, params.amountOut);
    }

    function _swap(address[] memory path, address _to, uint256 amountAMin, uint256 amountBMin) private {
        uint256 pathLength = path.length;
        for (uint256 i = 0; i < pathLength - 1; i++) {
            Structs.BeforeSwapParams memory Bparams = _prepareSwapParams(i, path, _to, pathLength);
            Structs.PairSwapParams memory params;
            params.amount0Out = Bparams.amount0Out;
            params.amount1Out = Bparams.amount1Out;
            params.fee0 = Bparams.fee0;
            params.fee1 = Bparams.fee1;
            params.recipient = Bparams.recipient;
            params.minAmount0Out = amountAMin;
            params.minAmount1Out = amountBMin;

            _validateAmounts(params.amount0Out, params.amount1Out, params.minAmount0Out, params.minAmount1Out);
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
        address pair = _computePairAddress(tokenA, tokenB);
        if (!_isContract(pair)) revert Router_NOT_LISTED_IN_THE_DEX();
        (uint112 reserveA, uint112 reserveB,) = IPair(pair).getReserves();
        if (reserveA == 0 || reserveB == 0) revert Router_InsufficientLiquidity();
        
        priceA = (reserveB * DECIMALS) / reserveA;
        priceB = (reserveA * DECIMALS) / reserveB;
        
        return (priceA, priceB);
    }

    function getSpotPriceInUSYT(address token) public view returns (uint256 priceInUSYT) {
        address pair = _computePairAddress(token, USYT);
        if (!_isContract(pair)) revert Router_NOT_LISTED_IN_THE_DEX();
        
        (uint112 reserveToken, uint112 reserveUSYT,) = IPair(pair).getReserves();
        if (reserveToken == 0 || reserveUSYT == 0) revert Router_InsufficientLiquidity();
        
        priceInUSYT = (reserveUSYT * DECIMALS) / reserveToken;
        
        return priceInUSYT;
    }

    function emergencyWithdrawal(address tokenA, address tokenB, uint256 amount) external OnlyFeeToSetter {
        address pair = _pairFor(tokenA, tokenB);
        IPair(pair).emergencyWithdraw(tokenA, amount);
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
        uint256 slippage
    ) public pure returns (uint256 minAmountOut) {
        if (slippage > MAX_SLIPPAGE) revert Router_InvalidSlippage();
        if (slippage < MIN_SLIPPAGE) revert Router_InvalidSlippage();
        minAmountOut = amountOut * (MAX_SLIPPAGE - slippage) / MAX_SLIPPAGE;
    }

    function _validateAmounts(
        uint256 actualA,
        uint256 actualB,
        uint256 minA,
        uint256 minB
    ) internal pure {
        if (actualA < minA) revert Router_InsufficientAAmount();
        if (actualB < minB) revert Router_InsufficientBAmount();
    }

    function _transferTokensToPair(
        address tokenA,
        address tokenB,
        address pair,
        uint256 amountA,
        uint256 amountB
    ) private {
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
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

    function getOptimalAmounts(
        address tokenA,
        address tokenB,
        uint256 amountA, 
        uint256 amountB
        ) external view returns(uint256 a, uint256 b)
        {
        address _pair = _computePairAddress(tokenA, tokenB);
        (a, b) = _optimalAmounts(_pair, amountA, amountB);
    }

    function _adjustPath(address[] memory _path) private view returns (address[] memory, bool) {
        if (_isContract(_pairFor(_path[0], _path[1])))  {
            return (_path, false);
        }

        if (_isContract(_pairFor(_path[0], USYT)) && _isContract(_pairFor(USYT, _path[1]))) {
            return (_path, true);
        } else {
            revert Router_NO_SWAP_PATH_AVAILABLE();
        }
    }

    function getPairAddress(address tokenA, address tokenB) external view returns (address pair) {
        pair = _computePairAddress(tokenA, tokenB);
        if (!_isContract(pair)) revert Router_PairNotExists();

        return pair;
    }

    function _computePairAddress(address tokenA, address tokenB) private view returns (address predictedPair) {
        bytes32 initCodeHash = keccak256(type(Pair).creationCode);
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        predictedPair = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            factory,
            salt,
            initCodeHash
        )))));
    }

    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        if (path.length != 2) revert Router_InvalidPath();
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        (address[] memory adjustedPath, bool isUSYTPath) = _adjustPath(path);
        
        if (isUSYTPath) {
            // First swap: path[0] → USYT
            (amounts[1]) = _getSwapOutput(amounts[0], adjustedPath[0], USYT);
            
            // Second swap: USYT → path[1]
            (amounts[1]) = _getSwapOutput(amounts[1], USYT, adjustedPath[1]);
        } else {
            // Direct swap: path[0] → path[1]
            (amounts[1]) = _getSwapOutput(amounts[0], adjustedPath[0], adjustedPath[1]);
        }
    }

    function _getSwapOutput(
        uint256 amountIn,
        address inputToken,
        address outputToken
    ) private view returns (uint256 amountOut) {
        address pair = _computePairAddress(inputToken, outputToken);
        (uint112 reserveA, uint112 reserveB,) = IPair(pair).getReserves();
        (uint112 reserveIn, uint112 reserveOut) = inputToken == IPair(pair).token0() 
            ? (reserveA, reserveB)
            : (reserveB, reserveA);

        (amountOut,) = _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountsForLiquidityRemoval(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external view returns (uint256 amountA, uint256 amountB) {
        address pair = _pairFor(tokenA, tokenB);
        
        (uint256 reserveA, uint256 reserveB,) = IPair(pair).getReserves();
        uint256 totalSupply = IPair(pair).totalSupply();
        
        amountA = (liquidity * reserveA) / totalSupply;
        amountB = (liquidity * reserveB) / totalSupply;
    }
}