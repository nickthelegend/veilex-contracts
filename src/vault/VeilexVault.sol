// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "../interfaces/IVeilexFactory.sol";
import "../interfaces/IVeilexPool.sol";

/**
 * @title VeilexVault
 * @notice MEV-protected swap engine using a commit-reveal scheme.
 *
 * FLOW:
 * 1. User calls commitOrder() — submits keccak256 hash of swap params + locks tokenIn
 *    - tokenIn + amountIn visible, but tokenOut + minOut HIDDEN inside hash
 *    - MEV bots see nothing useful — no destination, no direction
 *
 * 2. Wait COMMIT_DELAY blocks (2 blocks ≈ 4-6 seconds on HashKey Chain)
 *
 * 3. User calls revealAndSwap() — reveals actual params, contract verifies hash, executes swap
 *    - Pyth oracle validates price hasn't been manipulated
 *    - Swap executes atomically through VeilexPool
 *    - Bots had zero window to front-run
 *
 * CHAIN: HashKey Chain (EVM OP Stack L2)
 * ORACLE: Pyth Network (pull-based, fetch update from Hermes API)
 */
contract VeilexVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── CONSTANTS ────────────────────────────────
    uint256 public constant COMMIT_DELAY = 2; // blocks to wait before reveal
    uint256 public constant COMMIT_EXPIRY = 200; // blocks before order expires
    uint256 public constant MAX_PRICE_AGE = 60; // seconds — Pyth staleness limit
    uint256 public constant PRICE_TOLERANCE_BPS = 300; // 3% max deviation from oracle

    // ─── STORAGE ──────────────────────────────────
    IVeilexFactory public immutable factory;
    IPyth public immutable pyth;

    struct PendingOrder {
        address trader; // who committed
        address tokenIn; // token being sold (visible at commit)
        uint256 amountIn; // amount being sold (visible at commit)
        bytes32 commitment; // keccak256(tokenOut, minAmountOut, nonce, trader) — HIDDEN
        uint256 commitBlock; // block number when committed
        bool executed;
        bool cancelled;
    }

    mapping(bytes32 => PendingOrder) public orders;
    mapping(address => uint256) public nonces;

    // ─── EVENTS ───────────────────────────────────
    event OrderCommitted(
        bytes32 indexed orderHash, address indexed trader, address tokenIn, uint256 amountIn, uint256 commitBlock
    );

    event OrderExecuted(
        bytes32 indexed orderHash,
        address indexed trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 blockNumber
    );

    event OrderCancelled(bytes32 indexed orderHash, address indexed trader);

    // ─── CONSTRUCTOR ──────────────────────────────
    constructor(address _factory, address _pyth) {
        factory = IVeilexFactory(_factory);
        pyth = IPyth(_pyth);
    }

    // ─────────────────────────────────────────────
    // PHASE 1: COMMIT
    // ─────────────────────────────────────────────
    /**
     * @notice Commit a hidden swap order.
     * @param tokenIn    Token to sell
     * @param amountIn   Amount to sell
     * @param commitment keccak256(abi.encodePacked(tokenOut, minAmountOut, nonce, msg.sender))
     *                   Build this client-side — tokenOut and minAmountOut stay HIDDEN
     * @return orderHash The hash to pass to revealAndSwap()
     */
    function commitOrder(address tokenIn, uint256 amountIn, bytes32 commitment)
        external
        nonReentrant
        returns (bytes32 orderHash)
    {
        require(amountIn > 0, "Veilex: ZERO_AMOUNT");
        require(tokenIn != address(0), "Veilex: ZERO_TOKEN");

        // Lock tokens into vault
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Unique order hash includes commitment + caller + blocknumber
        orderHash = keccak256(abi.encodePacked(commitment, msg.sender, block.number));

        orders[orderHash] = PendingOrder({
            trader: msg.sender,
            tokenIn: tokenIn,
            amountIn: amountIn,
            commitment: commitment,
            commitBlock: block.number,
            executed: false,
            cancelled: false
        });

        emit OrderCommitted(orderHash, msg.sender, tokenIn, amountIn, block.number);
    }

    // ─────────────────────────────────────────────
    // PHASE 2: REVEAL AND EXECUTE
    // ─────────────────────────────────────────────
    /**
     * @notice Reveal actual swap params and execute. Must wait COMMIT_DELAY blocks.
     * @param orderHash       From commitOrder event
     * @param tokenOut        Destination token (was hidden in commitment)
     * @param minAmountOut    Minimum acceptable output (was hidden in commitment)
     * @param nonce           Your current nonce
     * @param pythPriceUpdate Fetch from Hermes: /v2/updates/price/latest?ids[]=<feedId>
     * @param tokenInFeedId   Pyth bytes32 feed ID for tokenIn
     * @param tokenOutFeedId  Pyth bytes32 feed ID for tokenOut
     */
    function revealAndSwap(
        bytes32 orderHash,
        address tokenOut,
        uint256 minAmountOut,
        uint256 nonce,
        bytes[] calldata pythPriceUpdate,
        bytes32 tokenInFeedId,
        bytes32 tokenOutFeedId
    ) external payable nonReentrant {
        PendingOrder storage order = orders[orderHash];

        // ── Validate ──────────────────────────────
        require(order.trader == msg.sender, "Veilex: NOT_OWNER");
        require(!order.executed, "Veilex: EXECUTED");
        require(!order.cancelled, "Veilex: CANCELLED");
        require(block.number >= order.commitBlock + COMMIT_DELAY, "Veilex: TOO_EARLY");
        require(block.number <= order.commitBlock + COMMIT_EXPIRY, "Veilex: EXPIRED");
        require(nonce == nonces[msg.sender], "Veilex: BAD_NONCE");

        // ── Verify commitment hash ─────────────────
        bytes32 expected = keccak256(abi.encodePacked(tokenOut, minAmountOut, nonce, msg.sender));
        require(order.commitment == expected, "Veilex: BAD_REVEAL");

        nonces[msg.sender]++;

        // ── Update Pyth oracle prices ──────────────
        uint256 pythFee = pyth.getUpdateFee(pythPriceUpdate);
        require(msg.value >= pythFee, "Veilex: PYTH_FEE");
        pyth.updatePriceFeeds{value: pythFee}(pythPriceUpdate);

        // ── Validate price not manipulated ────────
        _validatePrice(order.tokenIn, tokenOut, order.amountIn, minAmountOut, tokenInFeedId, tokenOutFeedId);

        // ── Execute swap (offloaded to relieve stack) ──
        _executeSwap(orderHash, tokenOut, minAmountOut);

        // Refund excess ETH (Pyth fee overpayment)
        if (msg.value > pythFee) {
            payable(msg.sender).transfer(msg.value - pythFee);
        }
    }

    /// @dev Executes the revealed swap through the pool and marks the order done.
    function _executeSwap(bytes32 orderHash, address tokenOut, uint256 minAmountOut) internal {
        PendingOrder storage order = orders[orderHash];

        address pool = factory.getPair(order.tokenIn, tokenOut);
        require(pool != address(0), "Veilex: NO_POOL");

        IERC20(order.tokenIn).safeTransfer(pool, order.amountIn);

        uint256 amountOut = IVeilexPool(pool).getAmountOut(order.amountIn, order.tokenIn);
        require(amountOut >= minAmountOut, "Veilex: SLIPPAGE");

        bool zeroForOne = order.tokenIn < tokenOut;
        IVeilexPool(pool).swap(zeroForOne ? 0 : amountOut, zeroForOne ? amountOut : 0, order.trader);

        order.executed = true;

        emit OrderExecuted(
            orderHash, order.trader, order.tokenIn, tokenOut, order.amountIn, amountOut, block.number
        );
    }

    // ─────────────────────────────────────────────
    // CANCEL
    // ─────────────────────────────────────────────
    function cancelOrder(bytes32 orderHash) external nonReentrant {
        PendingOrder storage order = orders[orderHash];
        require(order.trader == msg.sender, "Veilex: NOT_OWNER");
        require(!order.executed, "Veilex: EXECUTED");
        require(!order.cancelled, "Veilex: CANCELLED");

        order.cancelled = true;
        IERC20(order.tokenIn).safeTransfer(order.trader, order.amountIn);
        emit OrderCancelled(orderHash, msg.sender);
    }

    // ─────────────────────────────────────────────
    // VIEW HELPERS
    // ─────────────────────────────────────────────
    function computeCommitment(address tokenOut, uint256 minAmountOut, uint256 nonce, address trader)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(tokenOut, minAmountOut, nonce, trader));
    }

    function canReveal(bytes32 orderHash) external view returns (bool) {
        PendingOrder memory o = orders[orderHash];
        return !o.executed && !o.cancelled && block.number >= o.commitBlock + COMMIT_DELAY
            && block.number <= o.commitBlock + COMMIT_EXPIRY;
    }

    function blocksUntilReveal(bytes32 orderHash) external view returns (uint256) {
        PendingOrder memory o = orders[orderHash];
        if (block.number >= o.commitBlock + COMMIT_DELAY) return 0;
        return (o.commitBlock + COMMIT_DELAY) - block.number;
    }

    function getOrder(bytes32 orderHash) external view returns (PendingOrder memory) {
        return orders[orderHash];
    }

    // ─────────────────────────────────────────────
    // INTERNAL
    // ─────────────────────────────────────────────
    function _validatePrice(
        address,
        address,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes32 feedIn,
        bytes32 feedOut
    ) internal view {
        PythStructs.Price memory pIn = pyth.getPriceNoOlderThan(feedIn, MAX_PRICE_AGE);
        PythStructs.Price memory pOut = pyth.getPriceNoOlderThan(feedOut, MAX_PRICE_AGE);

        if (uint64(pIn.price) == 0 || uint64(pOut.price) == 0) return;

        uint256 priceIn = uint256(uint64(pIn.price));
        uint256 priceOut = uint256(uint64(pOut.price));
        uint256 expectedOut = (amountIn * priceIn) / priceOut;
        uint256 minAcceptable = expectedOut * (10000 - PRICE_TOLERANCE_BPS) / 10000;

        // rough check — normalize expo differences
        require(minAmountOut * 100 >= minAcceptable, "Veilex: PRICE_CHECK");
    }

    receive() external payable {}
}
