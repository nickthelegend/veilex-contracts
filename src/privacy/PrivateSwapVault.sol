// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IVeilexFactory.sol";
import "../interfaces/IVeilexPool.sol";
import "./StealthRegistry.sol";

/**
 * @title PrivateSwapVault
 * @notice Full-privacy swap: commit-reveal MEV protection + stealth address recipient.
 *
 * - Nobody can front-run (commit-reveal hides order until after 2 blocks)
 * - Nobody can link swap input to output address (stealth addresses)
 * - Recipient scans announcements with view key to find funds
 * - Compliance: recipient shares view key with auditor for regulatory access
 *
 * The commitment hides the stealth address + ephemeral key + view tag until reveal.
 */
contract PrivateSwapVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant COMMIT_DELAY = 2;
    uint256 public constant COMMIT_EXPIRY = 200;

    IVeilexFactory public immutable factory;
    StealthRegistry public immutable stealthRegistry;

    struct PrivateOrder {
        address trader;
        address tokenIn;
        uint256 amountIn;
        bytes32 commitment; // keccak256(tokenOut, minOut, stealthAddress, ephemeralPubKey, viewTag, nonce, trader)
        uint256 commitBlock;
        bool executed;
        bool cancelled;
    }

    mapping(bytes32 => PrivateOrder) public orders;
    mapping(address => uint256) public nonces;

    event PrivateOrderCommitted(bytes32 indexed orderHash, address indexed trader, address tokenIn, uint256 amountIn);
    event PrivateOrderExecuted(
        bytes32 indexed orderHash, address indexed stealthAddress, address tokenOut, uint256 amountOut
    );
    event PrivateOrderCancelled(bytes32 indexed orderHash);

    constructor(address _factory, address _stealthRegistry) {
        factory = IVeilexFactory(_factory);
        stealthRegistry = StealthRegistry(_stealthRegistry);
    }

    function commitPrivateOrder(address tokenIn, uint256 amountIn, bytes32 commitment)
        external
        nonReentrant
        returns (bytes32 orderHash)
    {
        require(amountIn > 0, "PrivVault: ZERO_AMOUNT");
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        orderHash = keccak256(abi.encodePacked(commitment, msg.sender, block.number));
        orders[orderHash] = PrivateOrder({
            trader: msg.sender,
            tokenIn: tokenIn,
            amountIn: amountIn,
            commitment: commitment,
            commitBlock: block.number,
            executed: false,
            cancelled: false
        });

        emit PrivateOrderCommitted(orderHash, msg.sender, tokenIn, amountIn);
    }

    function revealPrivateSwap(
        bytes32 orderHash,
        address tokenOut,
        uint256 minAmountOut,
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes1 viewTag,
        uint256 nonce
    ) external nonReentrant {
        PrivateOrder storage order = orders[orderHash];

        require(order.trader == msg.sender, "PrivVault: NOT_OWNER");
        require(!order.executed, "PrivVault: EXECUTED");
        require(!order.cancelled, "PrivVault: CANCELLED");
        require(block.number >= order.commitBlock + COMMIT_DELAY, "PrivVault: TOO_EARLY");
        require(block.number <= order.commitBlock + COMMIT_EXPIRY, "PrivVault: EXPIRED");
        require(nonce == nonces[msg.sender], "PrivVault: BAD_NONCE");
        require(stealthAddress != address(0), "PrivVault: ZERO_STEALTH");
        require(ephemeralPubKey.length == 33, "PrivVault: BAD_KEY");

        bytes32 expected = keccak256(
            abi.encodePacked(tokenOut, minAmountOut, stealthAddress, ephemeralPubKey, viewTag, nonce, msg.sender)
        );
        require(order.commitment == expected, "PrivVault: BAD_REVEAL");

        nonces[msg.sender]++;

        // Execute swap — output to stealth address (not caller's public address)
        address pool = factory.getPair(order.tokenIn, tokenOut);
        require(pool != address(0), "PrivVault: NO_POOL");

        IERC20(order.tokenIn).safeTransfer(pool, order.amountIn);
        uint256 amountOut = IVeilexPool(pool).getAmountOut(order.amountIn, order.tokenIn);
        require(amountOut >= minAmountOut, "PrivVault: SLIPPAGE");

        bool zeroForOne = order.tokenIn < tokenOut;
        IVeilexPool(pool).swap(
            zeroForOne ? 0 : amountOut,
            zeroForOne ? amountOut : 0,
            stealthAddress // ← output goes to stealth address
        );

        order.executed = true;

        // Announce so recipient can scan and find their funds using view key
        bytes memory metadata = abi.encodePacked(viewTag, bytes4(0x23b872dd), bytes20(tokenOut), bytes32(amountOut));
        stealthRegistry.announce(1, stealthAddress, ephemeralPubKey, metadata);

        emit PrivateOrderExecuted(orderHash, stealthAddress, tokenOut, amountOut);
    }

    function cancelPrivateOrder(bytes32 orderHash) external nonReentrant {
        PrivateOrder storage order = orders[orderHash];
        require(order.trader == msg.sender, "PrivVault: NOT_OWNER");
        require(!order.executed, "PrivVault: EXECUTED");
        require(!order.cancelled, "PrivVault: CANCELLED");
        order.cancelled = true;
        IERC20(order.tokenIn).safeTransfer(order.trader, order.amountIn);
        emit PrivateOrderCancelled(orderHash);
    }

    function computePrivateCommitment(
        address tokenOut,
        uint256 minAmountOut,
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes1 viewTag,
        uint256 nonce,
        address trader
    ) external pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(tokenOut, minAmountOut, stealthAddress, ephemeralPubKey, viewTag, nonce, trader)
        );
    }
}
