// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Re-export the Pyth SDK mock for easy deployment on testnet.
// Deploy: new MockPyth(60, 1) — 60 second validity, 1 wei update fee.
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
