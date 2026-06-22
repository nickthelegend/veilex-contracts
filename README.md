# veilex-contracts

Foundry smart contracts for **Veilex** — a MEV-protected, privacy-first DEX and private-payments stack on **HashKey Chain**.

## Contracts
| Area | Contracts |
|---|---|
| `core/` | `VeilexFactory`, `VeilexPool` (Uniswap-V2-style AMM, **vault-only swap**, 25 bps fee), `VeilexRouter` (liquidity only), `VeilexERC20` (LP) |
| `vault/` | `VeilexVault` — **commit-reveal** MEV protection: commit a hashed order, wait 2 blocks, reveal + execute. Pyth price validation on reveal. |
| `privacy/` | `StealthRegistry` (ERC-5564 stealth addresses), `PrivateSwapVault` (commit-reveal + stealth output), `ViewKeyCompliance` (voluntary view-key disclosure) |
| `oracle/` | `PythAdapter` |
| `tokens/` | `DUSDC` — faucet-mintable testnet USD coin (6 dp) |

## Test & build
```bash
forge test            # 22 tests
forge build --sizes
```

## Deployed — HashKey Chain testnet (chain 133)
All addresses + verification notes in **[DEPLOYMENTS.md](./DEPLOYMENTS.md)**. The full private-payment lifecycle (register → send → scan with viewing key) and the AMM are verified live on-chain.

## Deploy
```bash
# set PRIVATE_KEY in .env (gitignored)
forge script script/DeployHSK.s.sol \
  --rpc-url https://testnet.hsk.xyz --broadcast --slow
```

> The sample deployer key is derived from a public seed (`GenerateDeployer.s.sol`) — fine for testnet, **generate a fresh key before mainnet**.
