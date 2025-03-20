// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {USYT} from "../src/Invnex_token/USYT.sol";

contract DeployUSYT is Script {
    function run() external {
        uint256 initialSupply = 10000000;

        vm.startBroadcast();

        USYT usyt = new USYT(initialSupply);

        vm.stopBroadcast();

        console.log("USYT deployed to:", address(usyt));
    }
}
