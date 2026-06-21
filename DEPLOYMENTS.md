# Veilex deployments — HashKey Chain Testnet (chain 133)

Deployed 2026-06-22 from `script/DeployHSK.s.sol`. Deployer `0x21e5EAc64fdFb84c1D7b94889d7A1555cA6d114d`.
Explorer: https://testnet-explorer.hsk.xyz · RPC: https://testnet.hsk.xyz · Deploy block ~29448513.

| Contract | Address |
|---|---|
| MockPyth | `0xc9766baAC165C4994B290b8Cd699118B59c2CeDd` |
| **dUSDC** (Demo USD Coin, 6dp) | `0xc0068DC46B661552d4237bE17e67aFAefE0C7e03` |
| WETH (mock, 18dp) | `0x30a946eCDA664418a292dc4362E60Cc4dE9d1bC9` |
| WBTC (mock, 8dp) | `0x5c29480b6A5117F2c47FC39d20095812246E4a98` |
| SOL (mock, 9dp) | `0x25593093dE1614Cd832Ad78023Ada0F644356bcd` |
| VeilexFactory | `0x83F44E81c7CB71903B8bb82898d07C767a465fd6` |
| VeilexVault | `0x57CD6d43F9A0b96e85E7565AA931d2200fa1Ad8f` |
| VeilexRouter | `0x4a60e766e7bfa866EBcf5FebF04f8c4B588F7dA2` |
| **StealthRegistry** | `0xf8b8b082aF43643C93CDB7BD4e549fb183F81522` |
| PrivateSwapVault | `0xA733E7Fc765c647C544aFBcE1fAd0fB258603Bae` |
| ViewKeyCompliance | `0x0bcB2b8Dfb80A2cFb991d9Da5269243A7ec414cc` |
| PythAdapter | `0x77Ab5Ee5b2f56Eb1686343e02C5A32D1caf75eBe` |
| Pool SOL/dUSDC (seeded ~$73) | `0xbF11A45B312Fd4568226BE6D3eda82AE05cBbb86` |
| Pool WETH/dUSDC (seeded ~$1700) | `0x1431038044cD99FbEFB563b1D0Df4B554B4B90Eb` |
| Pool WBTC/dUSDC (seeded ~$63000) | `0xBae6031c0A311562bd07918135630ed1630ab297` |

## Verified on-chain
- True private payment lifecycle (register → send → scan with viewing key) — confirmed live.
- dUSDC ERC-20 (name/symbol/decimals, mint/faucet).
- AMM quote: 1 SOL → 72.81 dUSDC from the seeded pool (0.25% fee).

## Security note
The deployer key is **deterministically derived from a public seed** in `GenerateDeployer.s.sol` — fine for testnet, but **generate a fresh, private key before any mainnet deploy**.
