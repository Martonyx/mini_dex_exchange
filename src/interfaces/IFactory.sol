// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IFactory {

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function router() external view returns (address);
    function feePercentage() external view returns (uint256);
    
    function allPairs(uint256 index) external view returns (address);
    function allPairsLength() external view returns (uint256);
    function getPair(address tokenA, address tokenB) external view returns (address);

    function createPair(address tokenA, address tokenB) external returns (address pair);
}