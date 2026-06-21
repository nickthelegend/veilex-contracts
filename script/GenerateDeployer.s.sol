// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

/**
 * @notice Run ONCE to generate a fresh deployer wallet. Deploys nothing.
 *
 * Usage: forge script script/GenerateDeployer.s.sol
 *
 * After running:
 * 1. Copy private key to .env as PRIVATE_KEY=0x...
 * 2. Fund the address with HSK (faucet/bridge below)
 * 3. Deploy: forge script script/Deploy.s.sol --rpc-url https://testnet.hsk.xyz --broadcast
 */
contract GenerateDeployer is Script {
    function run() external view {
        // Deterministic from a seed — change the seed to get a different wallet.
        uint256 privKey = uint256(keccak256(abi.encodePacked("veilex-deployer-v1")));
        address deployer = vm.addr(privKey);

        console.log("");
        console.log("======================================");
        console.log("   VEILEX DEPLOYER WALLET");
        console.log("======================================");
        console.log("Address    :", deployer);
        console.log("Private Key:", vm.toString(bytes32(privKey)));
        console.log("======================================");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Add to .env:");
        console.log("   PRIVATE_KEY=<private key above>");
        console.log("");
        console.log("2. Fund with HSK on testnet:");
        console.log("   Faucet : https://hsk.xyz/faucet");
        console.log("   Bridge : https://bridge.hsk.xyz");
        console.log("   Explorer: https://testnet-explorer.hsk.xyz");
        console.log("");
        console.log("3. Check balance:");
        console.log("   cast balance", deployer, "--rpc-url https://testnet.hsk.xyz");
        console.log("");
        console.log("4. Deploy (after funding):");
        console.log("   forge script script/Deploy.s.sol \\");
        console.log("     --rpc-url https://testnet.hsk.xyz \\");
        console.log("     --broadcast \\");
        console.log("     --verify \\");
        console.log("     --verifier blockscout \\");
        console.log("     --verifier-url https://testnet-explorer.hsk.xyz/api");
        console.log("======================================");
    }
}
