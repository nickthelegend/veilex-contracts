// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/VeilexFactory.sol";
import "../src/core/VeilexPool.sol";
import "../src/mocks/MockERC20.sol";

contract VeilexPoolTest is Test {
    VeilexFactory factory;
    VeilexPool pool;
    MockERC20 tokenA;
    MockERC20 tokenB;

    address token0;
    address token1;
    address stranger = address(0xBEEF);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        factory = new VeilexFactory();
        // Use this test contract as the vault so we can drive swap() directly.
        factory.setVault(address(this));

        pool = VeilexPool(factory.createPair(address(tokenA), address(tokenB)));
        token0 = pool.token0();
        token1 = pool.token1();
    }

    function _addLiquidity(uint256 amount0, uint256 amount1) internal returns (uint256 liquidity) {
        MockERC20(token0).mint(address(pool), amount0);
        MockERC20(token1).mint(address(pool), amount1);
        liquidity = pool.mint(address(this));
    }

    function testAddLiquidityMintsLP() public {
        uint256 liq = _addLiquidity(1000e18, 1000e18);
        assertGt(liq, 0, "no LP minted");
        assertEq(pool.balanceOf(address(this)), liq, "LP not credited");
        // totalSupply = liquidity + MINIMUM_LIQUIDITY locked to address(0)
        assertEq(pool.totalSupply(), liq + pool.MINIMUM_LIQUIDITY());
        (uint112 r0, uint112 r1,) = pool.getReserves();
        assertEq(r0, 1000e18);
        assertEq(r1, 1000e18);
    }

    function testGetAmountOut() public {
        _addLiquidity(1000e18, 1000e18);
        uint256 amountIn = 10e18;
        // expected with 25 bps fee
        uint256 amountInWithFee = amountIn * 9975;
        uint256 expected = (amountInWithFee * 1000e18) / (1000e18 * 10000 + amountInWithFee);
        assertEq(pool.getAmountOut(amountIn, token0), expected);
    }

    function testSwapRevertsForNonVault() public {
        _addLiquidity(1000e18, 1000e18);
        uint256 amountIn = 10e18;
        MockERC20(token0).mint(address(pool), amountIn);
        uint256 out = pool.getAmountOut(amountIn, token0);

        vm.prank(stranger);
        vm.expectRevert(bytes("Veilex: FORBIDDEN"));
        pool.swap(0, out, stranger);
    }

    function testSwapSucceedsForVault() public {
        _addLiquidity(1000e18, 1000e18);
        uint256 amountIn = 10e18;
        // optimistic transfer of tokenIn (token0) into the pool, then swap
        MockERC20(token0).mint(address(pool), amountIn);
        uint256 out = pool.getAmountOut(amountIn, token0);

        address recipient = address(0xCAFE);
        pool.swap(0, out, recipient); // this == vault
        assertEq(MockERC20(token1).balanceOf(recipient), out, "recipient did not receive tokenOut");
    }

    function testKInvariantHoldsAfterSwap() public {
        _addLiquidity(1000e18, 1000e18);
        (uint112 r0Before, uint112 r1Before,) = pool.getReserves();
        uint256 kBefore = uint256(r0Before) * r1Before;

        uint256 amountIn = 25e18;
        MockERC20(token0).mint(address(pool), amountIn);
        uint256 out = pool.getAmountOut(amountIn, token0);
        pool.swap(0, out, address(0xCAFE));

        (uint112 r0After, uint112 r1After,) = pool.getReserves();
        uint256 kAfter = uint256(r0After) * r1After;
        // k must not decrease (fee makes it grow)
        assertGe(kAfter, kBefore, "k invariant violated");
    }
}
