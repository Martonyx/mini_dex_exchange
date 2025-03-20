// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {USYT} from "../src/Invnex_token/USYT.sol";

contract DeployUSYT is Script {
    function run() external {

        vm.startBroadcast();

        USYT usyt = new USYT();

        vm.stopBroadcast();

        console.log("USYT deployed to:", address(usyt));
    }
}
