// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/privacy/StealthRegistry.sol";
import "../src/mocks/MockERC20.sol";

contract StealthRegistryTest is Test {
    StealthRegistry registry;
    MockERC20 token;

    address sender = address(0x5E4D);
    address stealth = address(0x57EA);

    event Announcement(
        uint256 indexed schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes ephemeralPubKey,
        bytes metadata
    );

    function setUp() public {
        registry = new StealthRegistry();
        token = new MockERC20("Token", "TKN", 18);
    }

    function _bytesOf(uint256 len, bytes1 first) internal pure returns (bytes memory b) {
        b = new bytes(len);
        if (len > 0) b[0] = first;
    }

    function testRegisterStealthMetaAddress() public {
        bytes memory meta = _bytesOf(66, 0x02);
        vm.prank(sender);
        registry.registerStealthMetaAddress(1, meta);
        assertEq(registry.getStealthMetaAddress(sender, 1), meta, "meta-address not stored");
    }

    function testRegisterRevertsWrongLength() public {
        bytes memory meta = _bytesOf(65, 0x02);
        vm.expectRevert(bytes("Stealth: BAD_LENGTH"));
        registry.registerStealthMetaAddress(1, meta);
    }

    function testAnnounceEmitsEvent() public {
        bytes memory ephemeral = _bytesOf(33, 0x02);
        bytes memory metadata = _bytesOf(1, 0xAB);

        vm.expectEmit(true, true, true, true);
        emit Announcement(1, stealth, sender, ephemeral, metadata);

        vm.prank(sender);
        registry.announce(1, stealth, ephemeral, metadata);
    }

    function testPrivateTransferSendsAndAnnounces() public {
        uint256 amount = 100e18;
        token.mint(sender, amount);
        bytes memory ephemeral = _bytesOf(33, 0x03);

        vm.startPrank(sender);
        token.approve(address(registry), amount);

        // only check indexed topics; metadata is built inside the contract
        vm.expectEmit(true, true, true, false);
        emit Announcement(1, stealth, sender, ephemeral, "");

        registry.privateTransfer(address(token), stealth, amount, ephemeral, 0xAB);
        vm.stopPrank();

        assertEq(token.balanceOf(stealth), amount, "stealth address did not receive tokens");
    }

    function testWrongLengthEphemeralReverts() public {
        bytes memory ephemeral = _bytesOf(32, 0x02); // not 33
        bytes memory metadata = _bytesOf(1, 0xAB);
        vm.expectRevert(bytes("Stealth: BAD_PUBKEY"));
        registry.announce(1, stealth, ephemeral, metadata);
    }
}
