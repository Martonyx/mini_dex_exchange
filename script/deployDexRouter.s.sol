// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/invnexDex/Router.sol";

contract DeployRouter is Script {
    function run() external {

        vm.startBroadcast();

        address factoryAddress = 0x86293364a4A2a3929C93d9bCa1Be623c0D00Eb2f;
        address usyt = 0x9F1A0317BE662e848668278688ffC013b9c26F0e;
        address oracle = 0x9F1A0317BE662e848668278688ffC013b9c26F0e;

        Router router = new Router(factoryAddress, usyt, oracle);

        vm.stopBroadcast();
        
        console.log("Router deployed at:", address(router));
    }
}