// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Factory} from "../src/invnexDex/Factory.sol";

contract DeployFactory is Script {
    function run() external {
        address feeToSetter = 0xc14B3132C8273Bc7006fC4884C3ea7cCb68c8030;
        vm.startBroadcast();

        Factory factory = new Factory(feeToSetter);

        vm.stopBroadcast();

        console.log("Factory deployed at:", address(factory));
    }
}
