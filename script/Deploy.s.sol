// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/core/VeilexFactory.sol";
import "../src/vault/VeilexVault.sol";
import "../src/privacy/StealthRegistry.sol";
import "../src/privacy/PrivateSwapVault.sol";
import "../src/privacy/ViewKeyCompliance.sol";
import "../src/oracle/PythAdapter.sol";
import "../src/mocks/MockERC20.sol";
import "../src/tokens/DUSDC.sol";

/**
 * @notice Full deployment for Veilex on HashKey Chain. Requires PRIVATE_KEY + PYTH_ADDRESS in .env.
 *
 * For testnet: deploy MockPyth first, use its address as PYTH_ADDRESS.
 * For mainnet: use the real Pyth address (docs.pyth.network).
 *
 * Run:
 *   forge script script/Deploy.s.sol \
 *     --rpc-url https://testnet.hsk.xyz --broadcast \
 *     --verify --verifier blockscout --verifier-url https://testnet-explorer.hsk.xyz/api
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address pythAddr = vm.envAddress("PYTH_ADDRESS");

        console.log("Deploying Veilex from:", deployer);
        console.log("Chain ID:", block.chainid);
        require(pythAddr != address(0), "Set PYTH_ADDRESS in .env");

        vm.startBroadcast(deployerKey);

        // ── 1. Test tokens (testnet only) ──────────
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        MockERC20 hsk = new MockERC20("HashKey Token", "HSK", 18);
        MockERC20 usdt = new MockERC20("Tether", "USDT", 6);

        // ── 2. Core DEX ────────────────────────────
        VeilexFactory factory = new VeilexFactory();

        // ── 3. Vault (MEV protection) ──────────────
        VeilexVault vault = new VeilexVault(address(factory), pythAddr);

        // Link vault to factory
        factory.setVault(address(vault));

        // ── 4. Privacy layer ───────────────────────
        StealthRegistry stealthRegistry = new StealthRegistry();
        PrivateSwapVault privateVault = new PrivateSwapVault(address(factory), address(stealthRegistry));
        ViewKeyCompliance compliance = new ViewKeyCompliance();

        // ── 5. Oracle adapter ──────────────────────
        PythAdapter pythAdapter = new PythAdapter(pythAddr);

        // ── 5b. dUSDC testnet token (faucet-mintable) ──
        DUSDC dusdc = new DUSDC();
        dusdc.faucet();

        // ── 6. Create initial pools ────────────────
        factory.createPair(address(weth), address(usdc));
        factory.createPair(address(weth), address(wbtc));
        factory.createPair(address(hsk), address(usdc));
        factory.createPair(address(weth), address(hsk));
        factory.createPair(address(usdc), address(usdt));

        // ── 7. Mint test tokens to deployer ────────
        weth.mint(deployer, 100 ether);
        usdc.mint(deployer, 500_000 * 1e6);
        wbtc.mint(deployer, 10 * 1e8);
        hsk.mint(deployer, 200_000 ether);
        usdt.mint(deployer, 500_000 * 1e6);

        vm.stopBroadcast();

        // ── Output ─────────────────────────────────
        console.log("\n========== VEILEX DEPLOYMENT ==========");
        console.log("Network: HashKey Chain Testnet (133)");
        console.log("");
        console.log("Core:");
        console.log("  VeilexFactory:      ", address(factory));
        console.log("  VeilexVault:        ", address(vault));
        console.log("");
        console.log("Privacy:");
        console.log("  StealthRegistry:    ", address(stealthRegistry));
        console.log("  PrivateSwapVault:   ", address(privateVault));
        console.log("  ViewKeyCompliance:  ", address(compliance));
        console.log("");
        console.log("Oracle:");
        console.log("  PythAdapter:        ", address(pythAdapter));
        console.log("");
        console.log("Tokens:");
        console.log("  dUSDC:              ", address(dusdc));
        console.log("");
        console.log("Test Tokens:");
        console.log("  WETH:               ", address(weth));
        console.log("  USDC:               ", address(usdc));
        console.log("  WBTC:               ", address(wbtc));
        console.log("  HSK:                ", address(hsk));
        console.log("  USDT:               ", address(usdt));
        console.log("");
        console.log("=== COPY TO veilex/.env.local ===");
        console.log("NEXT_PUBLIC_FACTORY_ADDRESS=", address(factory));
        console.log("NEXT_PUBLIC_VAULT_ADDRESS=", address(vault));
        console.log("NEXT_PUBLIC_STEALTH_REGISTRY_ADDRESS=", address(stealthRegistry));
        console.log("NEXT_PUBLIC_PRIVATE_VAULT_ADDRESS=", address(privateVault));
        console.log("NEXT_PUBLIC_COMPLIANCE_ADDRESS=", address(compliance));
        console.log("NEXT_PUBLIC_PYTH_ADAPTER_ADDRESS=", address(pythAdapter));
        console.log("NEXT_PUBLIC_STEALTH_REGISTRY_ADDRESS=", address(stealthRegistry));
        console.log("NEXT_PUBLIC_PAYMENT_TOKEN_ADDRESS=", address(dusdc), "(dUSDC, for veilpay)");
        console.log("========================================\n");
    }
}
