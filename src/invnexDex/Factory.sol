// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Pair} from "./Pair.sol";
import {IPair} from "../interfaces/IPair.sol";
import {DexErrors} from "../utils/DexUtils.sol";

contract Factory is DexErrors {
    address public feeTo;
    address public feeToSetter;
    address public pendingFeeToSetter;
    address public router;
    uint256 public feePercentage;

    mapping(address => mapping(address => address)) public getPair;
    address[] private allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event RouterInitialized(address indexed router); 
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier ensure() {
        if (msg.sender != feeToSetter) revert Factory_Forbidden();
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
        if (_router == address(0)) revert Factory_ZeroAddress();
        router = _router;
        emit RouterInitialized(_router);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (router == address(0)) revert Factory_RouterNotInitialized();
        if (tokenA == tokenB) revert Factory_IdenticalAddresses();

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert Factory_ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert Factory_PairExists();

        bytes memory bytecode = type(Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        IPair(pair).initialize(token0, token1, address(this));

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external ensure {
        if (_feeTo == address(0)) revert Factory_ZeroAddress();
        feeTo = _feeTo;
    }

    function setDexFee(uint256 _fee) external ensure {
        if (_fee == 0) revert Factory_FeeCannotBeZero();
        feePercentage = _fee;
    }

    function StartFeeToSetterTransfer(address _feeToSetter) external ensure {
        if (_feeToSetter == address(0)) revert Factory_ZeroAddress();
        pendingFeeToSetter = _feeToSetter;
        emit OwnershipTransferStarted(feeToSetter, pendingFeeToSetter);
    }

    function claimFeeToSetterOwnership() external {
        if (msg.sender != pendingFeeToSetter) revert Factory_InvalidAddress();
        address oldFeeToSetter = feeToSetter;
        feeToSetter = msg.sender;
        pendingFeeToSetter = address(0);
        emit OwnershipTransferred(oldFeeToSetter, feeToSetter);
    }

    function getPairs(uint256 lowerLimit, uint256 upperLimit) external view returns (address[] memory) {
        if(lowerLimit > upperLimit) revert Factory_Invalid_Range();

        if(upperLimit > allPairs.length) upperLimit = allPairs.length;
        uint256 resultSize = upperLimit - lowerLimit;
        address[] memory result = new address[](resultSize);
        
        for (uint256 i = lowerLimit; i < upperLimit; i++) {
            result[i - lowerLimit] = allPairs[i];
        }
        
        return result;
    }
}