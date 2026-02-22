// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISwapExecutor
/// @notice Interface for the MonadMind Marketplace to trigger token swaps on behalf of followers.
interface ISwapExecutor {
    /// @notice Execute swaps for multiple followers in one transaction (batch).
    /// @dev Only callable by the registered MonadMind marketplace.
    /// @param strategyId Strategy whose followers are being traded for.
    /// @param followers Array of follower addresses (each must have deposited MON in the marketplace).
    /// @param amountsInWei MON amount to use per follower (native token).
    /// @param tokenOut Output token address (e.g. Uniswap V2 pair or ERC20).
    function executeBatch(
        uint256 strategyId,
        address[] calldata followers,
        uint256[] calldata amountsInWei,
        address tokenOut
    ) external payable;
}
