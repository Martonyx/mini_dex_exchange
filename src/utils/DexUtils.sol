//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

abstract contract DexErrors {
        error Factory_Unauthorized();
    error Factory_ZeroAddress();
    error Factory_RouterNotInitialized();
    error Factory_IdenticalAddresses();
    error Factory_PairExists();
    error Factory_FeeCannotBeZero();
    error Factory_InvalidAddress();
    error Factory_Invalid_Range();

    error Pair_InsufficientAmount();
    error Pair_CallerNotRouter();
    error Pair_InsufficientLiquidityAdded();
    error Pair_InsufficientLiquidityMinted();
    error Pair_InsufficientLiquidity();
    error Pair_InsufficientAmountBurned();
    error Pair_InvalidTo();
    error Pair_InsufficientInputAmount();
    error Pair_K();
    error Pair_FeeToNotSet();
    error Pair_Overflow();
    error Pair_CannotWithdrawPairTokens();
    error Pair_AlreadyInitialized();

    error Router_IdenticalAddresses();
    error Router_Unauthorized();
    error Router_ZeroAddress();
    error Router_DeadlineExpired();
    error Router_InvalidPath();
    error Router_SlippageExceeded();
    error Router_InsufficientInputAmount();
    error Router_InsufficientLiquidity();
    error Router_InsufficientAAmount();
    error Router_InsufficientBAmount();
    error Router_InvalidSlippage();
    error Router_NO_SWAP_PATH_AVAILABLE();
    error Router_NOT_LISTED_IN_THE_DEX();
    error Router_PairNotExists();
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

    struct UserParams {
        uint256 balanceBefore;
        uint256 amountIn;
        uint256 amountOut;
        address inputToken;
        address outputToken;
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
        uint256 feeToPortion;
        uint256 lpFee;
        uint256 feeAmount;
        uint256 amountInWithFee;
        uint256 amountOut;
    }

    struct SwapDetails {
        uint256 amount0In;
        uint256 amount1In;
    }

    struct Reserves {
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;
    }
}