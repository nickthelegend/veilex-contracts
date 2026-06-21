// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStealthRegistry {
    function announce(
        uint256 schemeId,
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes calldata metadata
    ) external;
    function registerStealthMetaAddress(uint256 schemeId, bytes calldata stealthMetaAddress) external;
    function getStealthMetaAddress(address user, uint256 schemeId) external view returns (bytes memory);
    function privateTransfer(
        address token,
        address stealthAddress,
        uint256 amount,
        bytes calldata ephemeralPubKey,
        bytes1 viewTag
    ) external;
}
