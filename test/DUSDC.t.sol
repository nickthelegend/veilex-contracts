// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/tokens/DUSDC.sol";

contract DUSDCTest is Test {
    DUSDC dusdc;
    address user = address(0xD00D);

    function setUp() public {
        dusdc = new DUSDC();
        vm.warp(1_000_000); // non-zero start so cooldown math is realistic
    }

    function testDecimalsIsSix() public view {
        assertEq(dusdc.decimals(), 6);
    }

    function testFaucetMints() public {
        vm.prank(user);
        dusdc.faucet();
        assertEq(dusdc.balanceOf(user), dusdc.FAUCET_AMOUNT());
        assertEq(dusdc.balanceOf(user), 1_000 * 1e6);
    }

    function testFaucetCooldownReverts() public {
        vm.startPrank(user);
        dusdc.faucet();
        vm.expectRevert(bytes("dUSDC: COOLDOWN"));
        dusdc.faucet();
        vm.stopPrank();
    }

    function testFaucetWorksAfterCooldown() public {
        vm.startPrank(user);
        dusdc.faucet();
        vm.warp(block.timestamp + dusdc.FAUCET_COOLDOWN());
        dusdc.faucet();
        vm.stopPrank();
        assertEq(dusdc.balanceOf(user), 2 * dusdc.FAUCET_AMOUNT());
    }

    function testCooldownRemaining() public {
        vm.prank(user);
        dusdc.faucet();
        assertEq(dusdc.faucetCooldownRemaining(user), dusdc.FAUCET_COOLDOWN());
        vm.warp(block.timestamp + dusdc.FAUCET_COOLDOWN());
        assertEq(dusdc.faucetCooldownRemaining(user), 0);
    }

    function testOpenMint() public {
        dusdc.mint(user, 500 * 1e6);
        assertEq(dusdc.balanceOf(user), 500 * 1e6);
    }
}
