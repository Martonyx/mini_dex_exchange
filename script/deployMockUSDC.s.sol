// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {USDC} from "../src/Invnex_token/mockUSDC.sol";

contract DeployUSDC is Script {
    function run() external {

        vm.startBroadcast();

        USDC usdc = new USDC();

        vm.stopBroadcast();

        console.log("USDC deployed to:", address(usdc));
    }
}