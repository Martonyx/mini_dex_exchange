// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Pair} from "./Pair.sol";

contract Factory {
    address public feeTo;
    address public feeToSetter;
    address public router;
    uint256 public feePercentage;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event RouterInitialized(address indexed router); 

    modifier ensure() {
        require(msg.sender == feeToSetter, "Factory: FORBIDDEN");
        _;
    }

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
        feeTo = _feeToSetter;
        feePercentage = 1;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function setRouter(address _router) external ensure {
        require(_router != address(0), "Factory: Zero address");
        router = _router;
        emit RouterInitialized(_router);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(router != address(0), "Factory: ROUTER_NOT_INITIALIZED"); 
        require(tokenA != tokenB, "Factory: IDENTICAL_ADDRESSES");

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Factory: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "Factory: PAIR_EXISTS");

        pair = address(new Pair(token0, token1, address(this)));

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external ensure {
        require(_feeTo != address(0), "Factory: feeTo zero address");
        feeTo = _feeTo;
    }

    function setDexFee(uint256 _fee) external ensure {
        require(_fee > 0, "Factory: fee cannot be zero");
        feePercentage = _fee;
    }

    function setFeeToSetter(address _feeToSetter) external ensure {
        require(_feeToSetter != address(0), "Factory: feeTo zero address");
        feeToSetter = _feeToSetter;
    }
}