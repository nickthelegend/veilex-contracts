// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/VeilexFactory.sol";
import "../src/core/VeilexPool.sol";
import "../src/vault/VeilexVault.sol";
import "../src/mocks/MockERC20.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract VeilexVaultTest is Test {
    VeilexFactory factory;
    VeilexVault vault;
    VeilexPool pool;
    MockPyth pyth;
    MockERC20 tokenIn;
    MockERC20 tokenOut;

    bytes32 feedIn = keccak256("FEED_IN");
    bytes32 feedOut = keccak256("FEED_OUT");

    address trader = address(0xA11CE);
    uint256 constant AMOUNT_IN = 10e18;
    uint256 constant MIN_OUT = 9e18;

    function setUp() public {
        tokenIn = new MockERC20("Token In", "TIN", 18);
        tokenOut = new MockERC20("Token Out", "TOUT", 18);

        pyth = new MockPyth(60, 1); // 60s validity, 1 wei fee
        factory = new VeilexFactory();
        vault = new VeilexVault(address(factory), address(pyth));
        factory.setVault(address(vault));

        pool = VeilexPool(factory.createPair(address(tokenIn), address(tokenOut)));

        // seed liquidity 1000/1000
        tokenIn.mint(address(pool), 1000e18);
        tokenOut.mint(address(pool), 1000e18);
        pool.mint(address(this));

        // give trader tokens to sell
        tokenIn.mint(trader, AMOUNT_IN);
        vm.warp(10_000); // stable timestamp for Pyth freshness
    }

    function _commit() internal returns (bytes32 orderHash) {
        bytes32 commitment = vault.computeCommitment(address(tokenOut), MIN_OUT, 0, trader);
        vm.startPrank(trader);
        tokenIn.approve(address(vault), AMOUNT_IN);
        orderHash = vault.commitOrder(address(tokenIn), AMOUNT_IN, commitment);
        vm.stopPrank();
    }

    function _pythUpdate() internal view returns (bytes[] memory updates) {
        updates = new bytes[](2);
        updates[0] = pyth.createPriceFeedUpdateData(feedIn, 1e8, 0, -8, 1e8, 0, uint64(block.timestamp));
        updates[1] = pyth.createPriceFeedUpdateData(feedOut, 1e8, 0, -8, 1e8, 0, uint64(block.timestamp));
    }

    function testCommitLocksTokens() public {
        bytes32 orderHash = _commit();
        assertEq(tokenIn.balanceOf(address(vault)), AMOUNT_IN, "vault did not lock tokens");
        assertEq(tokenIn.balanceOf(trader), 0, "trader still holds tokens");
        VeilexVault.PendingOrder memory o = vault.getOrder(orderHash);
        assertEq(o.trader, trader);
        assertEq(o.amountIn, AMOUNT_IN);
    }

    function testRevealRevertsTooEarly() public {
        bytes32 orderHash = _commit();
        bytes[] memory updates = _pythUpdate();
        vm.deal(trader, 1 ether);
        vm.prank(trader);
        vm.expectRevert(bytes("Veilex: TOO_EARLY"));
        vault.revealAndSwap{value: 2}(orderHash, address(tokenOut), MIN_OUT, 0, updates, feedIn, feedOut);
    }

    function testRevealSucceedsAfterDelay() public {
        bytes32 orderHash = _commit();
        vm.roll(block.number + vault.COMMIT_DELAY());

        bytes[] memory updates = _pythUpdate();
        vm.deal(trader, 1 ether);
        vm.prank(trader);
        vault.revealAndSwap{value: 2}(orderHash, address(tokenOut), MIN_OUT, 0, updates, feedIn, feedOut);

        VeilexVault.PendingOrder memory o = vault.getOrder(orderHash);
        assertTrue(o.executed, "order not executed");
        assertGe(tokenOut.balanceOf(trader), MIN_OUT, "trader did not receive output");
        assertEq(vault.nonces(trader), 1, "nonce did not increment");
    }

    function testRevealRevertsWrongCommitment() public {
        bytes32 orderHash = _commit();
        vm.roll(block.number + vault.COMMIT_DELAY());

        bytes[] memory updates = _pythUpdate();
        vm.deal(trader, 1 ether);
        vm.prank(trader);
        // reveal with a different minAmountOut than committed -> hash mismatch
        vm.expectRevert(bytes("Veilex: BAD_REVEAL"));
        vault.revealAndSwap{value: 2}(orderHash, address(tokenOut), MIN_OUT + 1, 0, updates, feedIn, feedOut);
    }

    function testCancelRefunds() public {
        bytes32 orderHash = _commit();
        vm.prank(trader);
        vault.cancelOrder(orderHash);
        assertEq(tokenIn.balanceOf(trader), AMOUNT_IN, "tokens not refunded");
        VeilexVault.PendingOrder memory o = vault.getOrder(orderHash);
        assertTrue(o.cancelled, "order not marked cancelled");
    }

    function testNonceIncrementsOnlyOnReveal() public {
        assertEq(vault.nonces(trader), 0);
        bytes32 orderHash = _commit();
        assertEq(vault.nonces(trader), 0, "commit must not bump nonce");
        vm.roll(block.number + vault.COMMIT_DELAY());
        bytes[] memory updates = _pythUpdate();
        vm.deal(trader, 1 ether);
        vm.prank(trader);
        vault.revealAndSwap{value: 2}(orderHash, address(tokenOut), MIN_OUT, 0, updates, feedIn, feedOut);
        assertEq(vault.nonces(trader), 1);
    }
}
