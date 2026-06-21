// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVeilexVault {
    function commitOrder(address tokenIn, uint256 amountIn, bytes32 commitment) external returns (bytes32 orderHash);
    function revealAndSwap(
        bytes32 orderHash,
        address tokenOut,
        uint256 minAmountOut,
        uint256 nonce,
        bytes[] calldata pythPriceUpdate,
        bytes32 tokenInFeedId,
        bytes32 tokenOutFeedId
    ) external payable;
    function cancelOrder(bytes32 orderHash) external;
    function canReveal(bytes32 orderHash) external view returns (bool);
    function blocksUntilReveal(bytes32 orderHash) external view returns (uint256);
    function computeCommitment(address tokenOut, uint256 minAmountOut, uint256 nonce, address trader)
        external
        pure
        returns (bytes32);
    function nonces(address trader) external view returns (uint256);
}
