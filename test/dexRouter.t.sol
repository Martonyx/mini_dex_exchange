// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "src/invnexDex/Router.sol";
import "src/invnexDex/Factory.sol";
import "src/invnexDex/Pair.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import{USYT} from "Invnex_token/USYT.sol";
import {DexErrors} from "src/utils/DexUtils.sol";

contract RouterTest is Test, DexErrors {
    Router router;
    Factory factory;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;
    address pair;
    USYT usyt;

    address user = address(0x123);

    function setUp() public {
        factory = new Factory(address(this));
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        tokenC = new MockERC20("Token C", "TKC");
        usyt = new USYT();
        router = new Router(address(factory), address(usyt));
        factory.setRouter(address(router));

        tokenA.mint(user, 5000 ether);
        tokenB.mint(user, 5000 ether);
        tokenC.mint(user, 500 ether);
        usyt.mint(user, 5000 ether);
        
        vm.startPrank(user);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        usyt.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    modifier addLiquidity() {
        vm.startPrank(user);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            500 ether,
            100 ether
        );

        router.addLiquidity(
            address(usyt),
            address(tokenB),
            500 ether,
            100 ether
        );

        router.addLiquidity(
            address(usyt),
            address(tokenC),
            500 ether,
            100 ether
        );
        _;
    }

    function testAddLiquidity() public {
        vm.prank(user);
        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether
        );

        pair = factory.getPair(address(tokenA), address(tokenB));

        assertEq(amountA, 100 ether, "Incorrect amountA");
        assertEq(amountB, 100 ether, "Incorrect amountB");
        assertGt(liquidity, 0, "Liquidity not minted");
        assertEq(IERC20(pair).balanceOf(user), liquidity, "Incorrect LP token balance");
    }

    function testAutoCreatePair() public {
        assertEq(factory.getPair(address(tokenA), address(tokenB)), address(0), "Pair should not exist yet");

        vm.prank(user);
        router.addLiquidity(address(tokenA), address(tokenB), 100 ether, 100 ether);

        assertTrue(factory.getPair(address(tokenA), address(tokenB)) != address(0), "Pair was not created");
    }

    function testFailAddLiquidityIdenticalTokens() public {
        vm.prank(user);
        router.addLiquidity(address(tokenA), address(tokenA), 100 ether, 100 ether);
    }

    function testFailAddLiquidityZeroAddress() public {
        vm.prank(user);
        router.addLiquidity(address(0), address(tokenB), 100 ether, 100 ether);
    }

    function testRemoveLiquidity() public addLiquidity {
        pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 lpBalance = IERC20(pair).balanceOf(user);

        IERC20(pair).approve(address(router), lpBalance);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBalance
        );
        vm.stopPrank();

        assertGt(amountA, 0, "AmountA should be greater than zero");
        assertGt(amountB, 0, "AmountB should be greater than zero");
    }

    function testSwapExactTokensForTokens_Success() public addLiquidity {
        uint256 beforeTransfer = tokenB.balanceOf(user);

        uint256 amountIn = 200e18;
        uint256 slippage = 5;
        uint256 deadline = block.timestamp + 1 hours;
        
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        router.swapExactTokensForTokens(amountIn, path, user, slippage, deadline);

        uint256 afterTransfer = tokenB.balanceOf(user);
        uint256 amountOut = afterTransfer - beforeTransfer;
        assertGt(amountOut, 0, "Swap should produce output tokens");
    }

    function testSwapExactTokensForTokens_RevertOnExpiredDeadline() public {
        uint256 amountIn = 1e18;
        uint256 slippage = 5;
        uint256 deadline = block.timestamp - 1;
        
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert(Router_DeadlineExpired.selector);
        vm.prank(user);
        router.swapExactTokensForTokens(amountIn, path, user, slippage, deadline);
    }

    function testSwapExactTokensForTokens_RevertOnInvalidPath() public {
        uint256 amountIn = 1e18;
        uint256 slippage = 5;
        uint256 deadline = block.timestamp + 1 hours;
        
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(usyt);
        path[2] = address(tokenB);

        vm.expectRevert(Router_InvalidPath.selector);
        vm.prank(user);
        router.swapExactTokensForTokens(amountIn, path, user, slippage, deadline);
    }

    function testSwapExactTokensForTokens_RevertOnInsufficientBalance() public {
        uint256 amountIn = 1e30;
        uint256 slippage = 5;
        uint256 deadline = block.timestamp + 1 hours;
        
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert();
        vm.prank(user);
        router.swapExactTokensForTokens(amountIn, path, user, slippage, deadline);
    }

    function testSwapExactTokensForTokens_RevertOnInsufficientAllowance() public {
        tokenA.approve(address(router), 0);
        
        uint256 amountIn = 1e18;
        uint256 slippage = 5;
        uint256 deadline = block.timestamp + 1 hours;
        
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert();
        vm.prank(user);
        router.swapExactTokensForTokens(amountIn, path, user, slippage, deadline);
    }

    function testSwapExactTokensForTokens_USYTPath() public addLiquidity {
        uint256 amountIn = 1e18;
        uint256 slippage = 5;
        uint256 deadline = block.timestamp + 1 hours;
        
        address[] memory path = new address[](2);
        path[0] = address(tokenB);
        path[1] = address(tokenC);

        router.swapExactTokensForTokens(amountIn, path, user, slippage, deadline);

        uint256 amountOut = tokenC.balanceOf(user);
        assertGt(amountOut, 0, "USYT path swap should execute successfully");
    }

    function testGetSpotPrice() public addLiquidity {
        (uint256 priceA, uint256 priceB) = router.getSpotPriceAandB(address(tokenA), address(tokenB));

        uint256 DECIMALS = 1e18;
        uint256 expectedPriceA = (100 ether * DECIMALS) / 500 ether;
        uint256 expectedPriceB = (500 ether * DECIMALS) / 100 ether; 

        assertEq(priceA, expectedPriceA, "PriceA is incorrect");
        assertEq(priceB, expectedPriceB, "PriceB is incorrect");
    }

    function testGetSpotPriceInUSYT() public addLiquidity {
        uint256 price = router.getSpotPriceInUSYT(address(tokenB));

        uint256 expectedPrice = (100 ether * 1e18) / 500 ether;

        assertEq(price, expectedPrice, "Incorrect token price in USYT");
    }

    // Test that predicted address matches actual deployed address
    function testComputePairAddressMatchesDeployment() public {
        vm.prank(user);
        factory.createPair(address(tokenA), address(tokenB));
        address predictedPair = router.getPairAddress(address(tokenA), address(tokenB));
        assertTrue(factory.getPair(address(tokenA), address(tokenB)) == predictedPair, "computed address is wrong");
    }
}


contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
