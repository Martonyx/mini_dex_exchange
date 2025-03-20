// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {USYTConverter} from "../src/invnexDex/USYTConverter.sol";

contract DeployConverter is Script {
    function run() external {
        vm.startBroadcast();

        address usdc = 0xc14B3132C8273Bc7006fC4884C3ea7cCb68c8030;
        address usyt = 0xc14B3132C8273Bc7006fC4884C3ea7cCb68c8030;

        USYTConverter converter = new USYTConverter(usdc, usyt);

        console.log("USYTConverter Address:", address(converter));

        vm.stopBroadcast();
    }
}
