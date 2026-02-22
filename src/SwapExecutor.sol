// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISwapExecutor} from "./ISwapExecutor.sol";

/// @title Minimal Uniswap V2 Router interface for hackathon demo
interface IUniswapV2Router02 {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

/// @title SwapExecutor
/// @notice Execution engine for MonadMind: performs token swaps. Marketplace-aware (only accepts calls from MonadMind).
contract SwapExecutor is ReentrancyGuard, ISwapExecutor {
    address public marketplace;
    address public owner;

    /// @dev Uniswap V2–style router (or mock). Zero address = mock mode (emit only).
    IUniswapV2Router02 public router;

    event BatchExecuted(
        address indexed marketplace,
        uint256 indexed strategyId,
        address[] followers,
        uint256[] amountsInWei,
        address tokenOut
    );
    event MockSwap(uint256 indexed strategyId, address indexed follower, uint256 amountIn, address tokenOut);
    event MarketplaceUpdated(address indexed oldMarketplace, address indexed newMarketplace);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    modifier onlyMarketplace() {
        require(marketplace != address(0) && msg.sender == marketplace, "SwapExecutor: only marketplace");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "SwapExecutor: only owner");
        _;
    }

    /// @param _marketplace MonadMind address; can be address(0) and set later via setMarketplace (e.g. deploy Executor first, then Marketplace).
    constructor(address _marketplace) {
        marketplace = _marketplace;
        owner = msg.sender;
    }

    /// @inheritdoc ISwapExecutor
    /// @dev Marketplace must send MON via msg.value = sum(amountsInWei). Checks-Effects-Interactions.
    function executeBatch(
        uint256 strategyId,
        address[] calldata followers,
        uint256[] calldata amountsInWei,
        address tokenOut
    ) external payable override nonReentrant onlyMarketplace {
        require(followers.length == amountsInWei.length, "SwapExecutor: length mismatch");
        require(followers.length > 0, "SwapExecutor: empty batch");
        require(tokenOut != address(0), "SwapExecutor: zero tokenOut");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amountsInWei.length; i++) {
            totalAmount += amountsInWei[i];
        }
        require(msg.value == totalAmount, "SwapExecutor: value mismatch");

        // EFFECTS: emit batch event
        emit BatchExecuted(marketplace, strategyId, followers, amountsInWei, tokenOut);

        // INTERACTIONS: mock swap per follower (Uniswap V2 interface for demo)
        if (address(router) != address(0)) {
            address[] memory path = new address[](2);
            path[0] = address(0);
            path[1] = tokenOut;
            uint256 deadline = block.timestamp + 300;
            for (uint256 i = 0; i < followers.length; i++) {
                if (amountsInWei[i] == 0) continue;
                try
                    router.swapExactETHForTokens{value: amountsInWei[i]}(0, path, followers[i], deadline)
                returns (uint256[] memory) {
                    emit MockSwap(strategyId, followers[i], amountsInWei[i], tokenOut);
                } catch {
                    emit MockSwap(strategyId, followers[i], amountsInWei[i], tokenOut);
                }
            }
        } else {
            for (uint256 i = 0; i < followers.length; i++) {
                if (amountsInWei[i] > 0) {
                    emit MockSwap(strategyId, followers[i], amountsInWei[i], tokenOut);
                }
            }
        }
    }

    /// @notice Set the MonadMind marketplace (e.g. after deployment). Owner only.
    function setMarketplace(address _marketplace) external onlyOwner {
        require(_marketplace != address(0), "SwapExecutor: zero address");
        address old = marketplace;
        marketplace = _marketplace;
        emit MarketplaceUpdated(old, _marketplace);
    }

    /// @notice Set Uniswap V2 router. Zero address = mock-only mode.
    function setRouter(address _router) external onlyOwner {
        address old = address(router);
        router = IUniswapV2Router02(_router);
        emit RouterUpdated(old, _router);
    }

    /// @notice Accept MON from marketplace when it forwards funds for swaps (optional).
    receive() external payable {}
}
