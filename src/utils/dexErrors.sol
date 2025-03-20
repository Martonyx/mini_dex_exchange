//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

abstract contract DexErrorsAndStruct {

    error InvalidTokenAddresses();
    error PoolAlreadyExists();
    error PoolDoesNotExist();
    error InsufficientLiquidity();
    error IncorrectLiquidityRatio();
    error TransferFailed();
    error InsufficientBalance();
    error InsufficientAllowance();
    error SpotPriceZero();
    error TransactionExpired();
    error SwapAmountMustBeGreaterThanZero();
    error SwapAmountTooLarge();
    error OutputAmountToolow();
    error InsufficientBalanceInTotokenPool();
    error InvalidPoolBalances();
    error TransferFromFailed();
    error AmountAApprovalFailed();
    error AmountBApprovalFailed();

}

abstract contract Structs {

    struct PairSwapParams {
        uint256 amount0Out;
        uint256 amount1Out;
        uint256 fee0;
        uint256 fee1;
        address recipient;
        uint256 minAmount0Out; 
        uint256 minAmount1Out; 
        uint256 slippageTolerance;
    }

    struct BeforeSwapParams {
        address input;
        address output;
        address pair;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
        uint256 amount0Out;
        uint256 amount1Out;
        uint256 fee0;
        uint256 fee1;
        uint256 amount0AOut;
        uint256 amount1BOut;
        address recipient;
    }

    struct AmountOutParams {
        uint256 amountIn;
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 priceIn;
        uint256 priceOut;
        uint256 feeToPortion;
        uint256 lpFee;
        uint256 feeAmount;
        uint256 effectiveAmountIn;
        uint256 amountInWithFee;
        uint256 amountOut;
    }
}