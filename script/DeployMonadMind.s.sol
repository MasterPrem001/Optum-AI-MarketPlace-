// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MonadMind} from "../src/MonadMind.sol";
import {ISwapExecutor} from "../src/ISwapExecutor.sol";

/// @notice Deploys Executor first, then MonadMind with Executor's address; wires marketplace into Executor.
contract DeployMonadMind is Script {
    function run() external returns (MonadMind monadMind, ISwapExecutor executor) {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerPrivateKey == 0) {
            deployerPrivateKey = vm.envUint("RPC_URL");
        }

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Executor first (marketplace not yet known)
        executor = new ISwapExecutor(address(0));
        console.log("SwapExecutor deployed to:", address(executor));

        // 2. Deploy Marketplace (MonadMind) with Executor's address
        monadMind = new MonadMind(address(executor));
        console.log("MonadMind deployed to:", address(monadMind));

        // 3. Wire Executor to accept calls only from MonadMind
        executor.setMarketplace(address(monadMind));
        console.log("Executor marketplace set to MonadMind");

        vm.stopBroadcast();

        return (monadMind, executor);
    }
}
