// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SimpleCoin1} from "../src/Invnex_token/SimpleToken1.sol";

contract DeploySimpleCoin is Script {
    function run() external {

        vm.startBroadcast();

        SimpleCoin1 simpleToken = new SimpleCoin1();

        vm.stopBroadcast();

        console.log("simpleToken deployed to:", address(simpleToken));
    }
}