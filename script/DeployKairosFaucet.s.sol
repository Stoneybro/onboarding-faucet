// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {console} from "forge-std/Test.sol";
import {KairosFaucet} from "src/KairosFaucet.sol";
import {Script} from "forge-std/Script.sol";

contract DeployKairosFaucet is Script {
    function run() external {
        address tokenAddress = address(0);
        uint256 dripAmount = 0.1 ether;

        vm.startBroadcast();
        KairosFaucet faucet = new KairosFaucet(tokenAddress, dripAmount);
        vm.stopBroadcast();

        console.log("KairosFaucet deployed at:", address(faucet));
    }
}
