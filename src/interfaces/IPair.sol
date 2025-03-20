// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Structs} from "../utils/dexErrors.sol";


interface IPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to, uint256 amount) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, uint256 fee0, uint256 fee1, address to) external;
    function swap(Structs.PairSwapParams calldata params) external;

}