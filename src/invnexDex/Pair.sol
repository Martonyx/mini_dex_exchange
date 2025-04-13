// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {Structs, DexErrors} from "../utils/DexUtils.sol";

contract Pair is ERC20, DexErrors {

    using SafeERC20 for IERC20;

    address public immutable token0;
    address public immutable token1;
    address public immutable factory;
    address public router;    

    Structs.Reserves private _reserves;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed to, uint256 amount0, uint256 amount1);
    event Sync(uint112 reserve0, uint112 reserve1);

    modifier onlyValidAmounts(uint256 amount0, uint256 amount1) {
        if (amount0 == 0 && amount1 == 0) revert Pair_InsufficientAmount();
        _;
    }

    modifier onlyRouter() {
        address _router = IFactory(factory).router();
        if (msg.sender != _router) revert Pair_CallerNotRouter();
        _;
    }

    constructor(address _token0, address _token1, address _factory) ERC20("Invnex Liquidity Token", "ILP") {
        token0 = _token0;
        token1 = _token1;
        factory = _factory;
    }

    function mint(address to) external onlyRouter returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        if (amount0 == 0 || amount1 == 0) revert Pair_InsufficientLiquidityAdded();

        if (totalSupply() == 0) {
            liquidity = sqrt(amount0 * amount1);
        } else {
            liquidity = min((amount0 * totalSupply()) / _reserve0, (amount1 * totalSupply()) / _reserve1);
        }

        if (liquidity == 0) revert Pair_InsufficientLiquidityMinted();

        _mint(to, liquidity); 
        _update(balance0, balance1);
        emit Mint(to, amount0, amount1);
    }

    function burn(address to, uint256 amount) external onlyRouter returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = balanceOf(to);
        if (liquidity < amount) revert Pair_InsufficientLiquidity();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        amount0 = (amount * balance0) / totalSupply();
        amount1 = (amount * balance1) / totalSupply();

        if (amount0 == 0 || amount1 == 0) revert Pair_InsufficientAmountBurned();

        _burn(to, amount);
        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1); 

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1);
        emit Burn(to, amount0, amount1);
    }

    function swap(Structs.PairSwapParams calldata params) external onlyRouter onlyValidAmounts(params.amount0Out, params.amount1Out) {
        if (params.recipient == address(0)) revert Pair_InvalidTo();

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        if (params.amount0Out >= _reserve0 || params.amount1Out >= _reserve1) revert Pair_InsufficientLiquidity();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        Structs.SwapDetails memory details = _calculateAmountsIn(
            _reserve0, _reserve1, balance0, balance1,
            params
        );
        
        uint256 balanceA = balance0 - params.amount0Out - params.fee0;
        uint256 balanceB = balance1 - params.amount1Out - params.fee1;

        if (details.amount0In == 0 && details.amount1In == 0) revert Pair_InsufficientInputAmount();
        
        if (balanceA * balanceB < uint256(_reserve0) * uint256(_reserve1)) revert Pair_K();
        
        _processSwapTransfers(params.amount0Out, params.amount1Out, params.fee0, params.fee1, params.recipient);

        _update(balanceA, balanceB);
    }
    
    function _processSwapTransfers(
        uint256 amount0AfterFee, 
        uint256 amount1AfterFee, 
        uint256 fee0, 
        uint256 fee1, 
        address to
    ) private {
        if (amount0AfterFee > 0) IERC20(token0).safeTransfer(to, amount0AfterFee);
        if (amount1AfterFee > 0) IERC20(token1).safeTransfer(to, amount1AfterFee);

        address _feeTo = IFactory(factory).feeTo();
        if (_feeTo == address(0)) revert Pair_FeeToNotSet();
        if (fee0 > 0) IERC20(token0).safeTransfer(_feeTo, fee0);
        if (fee1 > 0) IERC20(token1).safeTransfer(_feeTo, fee1);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Pair_Overflow();

        _reserves = Structs.Reserves({
            reserve0: uint112(balance0),
            reserve1: uint112(balance1),
            blockTimestampLast: uint32(block.timestamp)
        });
        emit Sync(uint112(balance0), uint112(balance1));
    }

    function _calculateAmountsIn(
        uint112 _reserve0, 
        uint112 _reserve1, 
        uint256 balance0,
        uint256 balance1,
        Structs.PairSwapParams memory params)
        private pure returns (Structs.SwapDetails memory details) {
        details.amount0In = balance0 > (_reserve0 - params.amount0Out - params.fee0)
            ? balance0 - (_reserve0 - params.amount0Out - params.fee0)
            : 0;
        details.amount1In = balance1 > (_reserve1 - params.amount1Out - params.fee1)
            ? balance1 - (_reserve1 - params.amount1Out - params.fee1)
            : 0;

        return details;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (_reserves.reserve0, _reserves.reserve1, _reserves.blockTimestampLast);
    }

    function sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}