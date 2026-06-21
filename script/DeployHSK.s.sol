// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/core/VeilexFactory.sol";
import "../src/core/VeilexPool.sol";
import "../src/core/VeilexRouter.sol";
import "../src/vault/VeilexVault.sol";
import "../src/privacy/StealthRegistry.sol";
import "../src/privacy/PrivateSwapVault.sol";
import "../src/privacy/ViewKeyCompliance.sol";
import "../src/oracle/PythAdapter.sol";
import "../src/tokens/DUSDC.sol";
import "../src/mocks/MockERC20.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

/**
 * @notice Full Veilex deployment to HashKey Chain testnet (chain 133), including
 *         seeded AMM pools so on-chain swaps work immediately.
 *
 *   forge script script/DeployHSK.s.sol --rpc-url https://testnet.hsk.xyz --broadcast --slow
 */
contract DeployHSK is Script {
    DUSDC dusdc;
    VeilexFactory factory;

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address dep = vm.addr(key);

        vm.startBroadcast(key);

        // ── Oracle (mock for testnet) ──
        MockPyth pyth = new MockPyth(60, 1);

        // ── Tokens ──
        dusdc = new DUSDC();
        dusdc.mint(dep, 5_000_000 * 1e6); // seed deployer with dUSDC for liquidity
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);
        MockERC20 wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        MockERC20 sol = new MockERC20("Solana", "SOL", 9);

        // ── Core DEX ──
        factory = new VeilexFactory();
        VeilexVault vault = new VeilexVault(address(factory), address(pyth));
        factory.setVault(address(vault));
        VeilexRouter router = new VeilexRouter(address(factory), address(weth));

        // ── Privacy ──
        StealthRegistry stealth = new StealthRegistry();
        PrivateSwapVault privVault = new PrivateSwapVault(address(factory), address(stealth));
        ViewKeyCompliance compliance = new ViewKeyCompliance();

        // ── Oracle adapter ──
        PythAdapter adapter = new PythAdapter(address(pyth));

        // ── Seed pools (base/dUSDC) priced roughly to market ──
        address pSol = _seed(dep, sol, 10_000 * 1e9, 730_000 * 1e6); // ~73
        address pEth = _seed(dep, weth, 100 ether, 170_000 * 1e6); // ~1700
        address pBtc = _seed(dep, wbtc, 10 * 1e8, 630_000 * 1e6); // ~63000

        vm.stopBroadcast();

        // ── Output ──
        console.log("\n=========== VEILEX @ HashKey testnet (133) ===========");
        console.log("MockPyth          :", address(pyth));
        console.log("dUSDC             :", address(dusdc));
        console.log("WETH (mock)       :", address(weth));
        console.log("WBTC (mock)       :", address(wbtc));
        console.log("SOL (mock)        :", address(sol));
        console.log("VeilexFactory     :", address(factory));
        console.log("VeilexVault       :", address(vault));
        console.log("VeilexRouter      :", address(router));
        console.log("StealthRegistry   :", address(stealth));
        console.log("PrivateSwapVault  :", address(privVault));
        console.log("ViewKeyCompliance :", address(compliance));
        console.log("PythAdapter       :", address(adapter));
        console.log("Pool SOL/dUSDC    :", pSol);
        console.log("Pool WETH/dUSDC   :", pEth);
        console.log("Pool WBTC/dUSDC   :", pBtc);
        console.log("======================================================\n");
        console.log("=== veilex/.env.local + veilpay/.env.local ===");
        console.log("NEXT_PUBLIC_STEALTH_REGISTRY_ADDRESS=", address(stealth));
        console.log("NEXT_PUBLIC_PAYMENT_TOKEN_ADDRESS=", address(dusdc));
        console.log("NEXT_PUBLIC_FACTORY_ADDRESS=", address(factory));
        console.log("NEXT_PUBLIC_VAULT_ADDRESS=", address(vault));
        console.log("NEXT_PUBLIC_PRIVATE_VAULT_ADDRESS=", address(privVault));
        console.log("NEXT_PUBLIC_COMPLIANCE_ADDRESS=", address(compliance));
        console.log("NEXT_PUBLIC_PYTH_ADAPTER_ADDRESS=", address(adapter));
        console.log("NEXT_PUBLIC_ROUTER_ADDRESS=", address(router));
    }

    /// @dev create base/dUSDC pair, fund it, mint LP to deployer; returns pool address.
    function _seed(address dep, MockERC20 base, uint256 baseAmt, uint256 quoteAmt) internal returns (address pool) {
        base.mint(dep, baseAmt);
        pool = factory.createPair(address(base), address(dusdc));
        base.transfer(pool, baseAmt);
        dusdc.transfer(pool, quoteAmt);
        VeilexPool(pool).mint(dep);
    }
}
