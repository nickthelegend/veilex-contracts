// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/tokens/DUSDC.sol";

/**
 * @notice Deploy the dUSDC testnet token on HashKey Chain.
 * Run:
 *   forge script script/DeployDUSDC.s.sol \
 *     --rpc-url https://testnet.hsk.xyz --broadcast \
 *     --verify --verifier blockscout --verifier-url https://testnet-explorer.hsk.xyz/api
 */
contract DeployDUSDC is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        DUSDC dusdc = new DUSDC();
        dusdc.faucet(); // seed the deployer with 1,000 dUSDC

        vm.stopBroadcast();

        console.log("================ dUSDC ================");
        console.log("dUSDC token:", address(dusdc));
        console.log("Add to veilpay/.env.local:");
        console.log("  NEXT_PUBLIC_PAYMENT_TOKEN_ADDRESS=", address(dusdc));
        console.log("======================================");
    }
}
