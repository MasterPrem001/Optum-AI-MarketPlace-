// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISwapExecutor} from "./ISwapExecutor.sol";

/// @title MonadMind
/// @notice Registry & Vault: AI strategies with public metadata (name/bio) and secret metadata (IPFS CID for AI prompt).
///         Only users who follow (deposit MON) have their funds managed by the strategy. Off-chain agent triggers trades via SwapExecutor.
contract MonadMind is ReentrancyGuard {
    // ------------------------------------------------------------------------
    // Strategy registry (public + secret metadata)
    // ------------------------------------------------------------------------

    struct Strategy {
        uint256 id;
        address creator;
        string name;   // public
        string bio;    // public
        string secretLogicHash; // IPFS CID for AI prompt — only agent can read (see getSecretLogicHash)
        bool isActive;
    }

    uint256 public nextStrategyId = 1;
    mapping(uint256 => Strategy) public strategies;


    /// @notice user => strategyId => MON deposited (only these users can have funds used by agent trades)
    mapping(address => mapping(uint256 => uint256)) public deposits;
    mapping(uint256 => uint256) public totalDeposits;


    address public owner;
    /// @notice Off-chain AI agent; only this address can trigger trades for followers and read secretLogicHash.
    address public offChainAgent;
    ISwapExecutor public swapExecutor;


    event StrategyRegistered(uint256 indexed id, address indexed creator, string name, string bio);
    event Followed(uint256 indexed strategyId, address indexed user, uint256 amount);
    event Withdrawn(uint256 indexed strategyId, address indexed user, uint256 amount);
    event AgentTradeTriggered(uint256 indexed strategyId, address[] followers, uint256[] amounts, address tokenOut);
    event AgentUpdated(address indexed previousAgent, address indexed newAgent);
    event ExecutorUpdated(address indexed previousExecutor, address indexed newExecutor);

    modifier onlyOwner() {
        require(msg.sender == owner, "MonadMind: not owner");
        _;
    }

    modifier onlyAgent() {
        require(msg.sender == offChainAgent, "MonadMind: not agent");
        _;
    }

    constructor(address _executor) {
        owner = msg.sender;
        offChainAgent = msg.sender;
        if (_executor != address(0)) {
            swapExecutor = ISwapExecutor(_executor);
        }
    }



    /// @notice Register a strategy with public (name, bio) and secret (IPFS CID) metadata.
    function registerStrategy(string calldata _name, string calldata _bio, string calldata _secretLogicHash)
        external
        returns (uint256 id)
    {
        id = nextStrategyId;
        unchecked {
            nextStrategyId = id + 1;
        }
        strategies[id] = Strategy({
            id: id,
            creator: msg.sender,
            name: _name,
            bio: _bio,
            secretLogicHash: _secretLogicHash,
            isActive: true
        });
        emit StrategyRegistered(id, msg.sender, _name, _bio);
    }

    /// @notice Returns secretLogicHash (IPFS CID) only to the off-chain agent.
    /// @dev Access control: only offChainAgent can call this. The agent fetches the prompt from IPFS using the CID;
    ///      no other address can read the CID from the contract, so only the AI agent can resolve and use the secret logic.
    function getSecretLogicHash(uint256 _strategyId) external view onlyAgent returns (string memory) {
        require(_strategyId != 0 && _strategyId < nextStrategyId, "MonadMind: invalid strategy");
        return strategies[_strategyId].secretLogicHash;
    }

    /// @notice Owner-only: update the off-chain agent address (agent governance).
    function updateAgentAddress(address _newAgent) external onlyOwner {
        require(_newAgent != address(0), "MonadMind: zero address");
        address previous = offChainAgent;
        offChainAgent = _newAgent;
        emit AgentUpdated(previous, _newAgent);
    }

    /// @notice Owner-only: set SwapExecutor (e.g. after deployment).
    function setExecutor(address _executor) external onlyOwner {
        address previous = address(swapExecutor);
        swapExecutor = ISwapExecutor(_executor);
        emit ExecutorUpdated(previous, _executor);
    }

   

    /// @notice Follow a strategy by depositing MON. Only these users have funds that can be used by the strategy's agent.
    function follow(uint256 _strategyId) external payable {
        require(_strategyId != 0 && _strategyId < nextStrategyId, "MonadMind: invalid strategy");
        require(strategies[_strategyId].isActive, "MonadMind: strategy inactive");
        require(msg.value > 0, "MonadMind: zero amount");

        deposits[msg.sender][_strategyId] += msg.value;
        totalDeposits[_strategyId] += msg.value;
        emit Followed(_strategyId, msg.sender, msg.value);
    }

    /// @notice Withdraw MON. Checks-Effects-Interactions + ReentrancyGuard.
    function withdraw(uint256 _strategyId, uint256 _amount) external nonReentrant {
        require(_strategyId != 0 && _strategyId < nextStrategyId, "MonadMind: invalid strategy");
        require(_amount > 0, "MonadMind: zero amount");
        uint256 balance = deposits[msg.sender][_strategyId];
        require(balance >= _amount, "MonadMind: insufficient balance");

        deposits[msg.sender][_strategyId] = balance - _amount;
        totalDeposits[_strategyId] -= _amount;

        (bool ok,) = msg.sender.call{value: _amount}("");
        require(ok, "MonadMind: transfer failed");
        emit Withdrawn(_strategyId, msg.sender, _amount);
    }

    /// @notice Trigger swaps for multiple followers in one tx. Only offChainAgent. Funds are only taken from users who have followed (deposited).
    function triggerAgentTrade(
        uint256 _strategyId,
        address[] calldata followers,
        address tokenOut,
        uint256[] calldata amountsInWei
    ) external onlyAgent nonReentrant {
        require(_strategyId != 0 && _strategyId < nextStrategyId, "MonadMind: invalid strategy");
        require(strategies[_strategyId].isActive, "MonadMind: strategy inactive");
        require(followers.length == amountsInWei.length && followers.length > 0, "MonadMind: bad batch");
        require(tokenOut != address(0), "MonadMind: zero tokenOut");
        require(address(swapExecutor) != address(0), "MonadMind: no executor");

        uint256 total = 0;
        for (uint256 i = 0; i < followers.length; i++) {
            require(deposits[followers[i]][_strategyId] >= amountsInWei[i], "MonadMind: insufficient follower balance");
            total += amountsInWei[i];
        }
        require(total > 0, "MonadMind: zero total");

        // EFFECTS: deduct from each follower's deposit
        for (uint256 i = 0; i < followers.length; i++) {
            deposits[followers[i]][_strategyId] -= amountsInWei[i];
        }
        totalDeposits[_strategyId] -= total;

        // INTERACTION: send MON to executor and call batch (marketplace-aware)
        swapExecutor.executeBatch{value: total}(_strategyId, followers, amountsInWei, tokenOut);

        emit AgentTradeTriggered(_strategyId, followers, amountsInWei, tokenOut);
    }


    function getStrategy(uint256 _strategyId)
        external
        view
        returns (uint256 id, address creator, string memory name, string memory bio, bool isActive)
    {
        require(_strategyId != 0 && _strategyId < nextStrategyId, "MonadMind: invalid strategy");
        Strategy storage s = strategies[_strategyId];
        return (s.id, s.creator, s.name, s.bio, s.isActive);
    }

    function getUserDeposit(address user, uint256 _strategyId) external view returns (uint256) {
        return deposits[user][_strategyId];
    }

    receive() external payable {}
}
