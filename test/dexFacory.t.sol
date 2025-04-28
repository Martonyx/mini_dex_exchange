// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "src/invnexDex/Factory.sol"; 
import "src/invnexDex/Pair.sol";

contract FactoryTest is Test {

    error Factory_RouterNotInitialized();
    
    Factory factory;
    address feeToSetter = address(0xBEEF);
    address router = address(0xCAFE);
    address tokenA = address(0xDEAD);
    address tokenB = address(0xBEEF);
    address pair;

    function setUp() public {
        factory = new Factory(feeToSetter);
    }

    function testDeployment() view public {
        assertEq(factory.feeToSetter(), feeToSetter);
        assertEq(factory.feeTo(), feeToSetter);
        assertEq(factory.feePercentage(), 1);
        assertEq(factory.allPairsLength(), 0);
    }

    function testSetRouter() public {
        vm.prank(feeToSetter);
        factory.setRouter(router);
        assertEq(factory.router(), router);
    }

    function testFailSetRouter_NotAuthorized() public {
        vm.expectRevert("Factory: UNAUTHORIZED");
        factory.setRouter(router);
    }

    function testCreatePair() public {
        vm.prank(feeToSetter);
        factory.setRouter(router);

        vm.prank(address(this));
        pair = factory.createPair(tokenA, tokenB);
        assertEq(factory.getPair(tokenA, tokenB), pair);
        assertEq(factory.allPairsLength(), 1);
    }

    function testCreatePairWithoutRouter() public {
        vm.expectRevert(Factory_RouterNotInitialized.selector);
        factory.createPair(tokenA, tokenB);
    }

    function testFailCreatePairSameToken() public {
        vm.prank(feeToSetter);
        factory.setRouter(router);
        factory.createPair(tokenA, tokenA);
        vm.expectRevert("Factory: IDENTICAL_ADDRESSES");
    }

    function testSetFeeTo() public {
        address newFeeTo = address(0xC0FFEE);
        vm.prank(feeToSetter);
        factory.setFeeTo(newFeeTo);
        assertEq(factory.feeTo(), newFeeTo);
    }

    function testSetDexFee() public {
        uint256 newFee = 5;
        vm.prank(feeToSetter);
        factory.setDexFee(newFee);
        assertEq(factory.feePercentage(), newFee);
    }

    function testFailSetDexFeeZero() public {
        vm.prank(feeToSetter);
        factory.setDexFee(0);
        vm.expectRevert("Factory: ZERO_INPUT");
    }

    function testSetFeeToSetter() public {
        address newFeeToSetter = address(0xABCD);
        vm.prank(feeToSetter);
        factory.StartFeeToSetterTransfer(newFeeToSetter);
        assertEq(factory.feeToSetter(), feeToSetter);

        vm.prank(newFeeToSetter);
        factory.claimFeeToSetterOwnership();
        assertEq(factory.feeToSetter(), newFeeToSetter);
    }
}
