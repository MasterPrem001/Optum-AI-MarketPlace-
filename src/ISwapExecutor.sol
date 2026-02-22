// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISwapExecutor
/// @notice Interface for the MonadMind Marketplace to trigger token swaps on behalf of followers.
interface ISwapExecutor {

    function executeBatch(
        uint256 strategyId,
        address[] calldata followers,
        uint256[] calldata amountsInWei,
        address tokenOut
    ) external payable;
}
