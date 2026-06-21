// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVeilexPool {
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external;
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}
