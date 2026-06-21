# References — READ ONLY

These are the original Uniswap V2 source files used as reference only.
All Veilex contracts in src/ are our own implementations.
Never import from this folder in production contracts.

Key files:
- UniswapV2Pair.sol     → basis for VeilexPool.sol (renamed, fee changed, vault-only swap)
- UniswapV2Factory.sol  → basis for VeilexFactory.sol
- UniswapV2Router02.sol → basis for VeilexRouter.sol (swap functions removed)
