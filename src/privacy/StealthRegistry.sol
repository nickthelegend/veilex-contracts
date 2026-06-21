// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title StealthRegistry
 * @notice ERC-5564 stealth address registry for Veilex private payments.
 *
 * PRIVACY MODEL:
 *   Recipient has spendingPrivKey (control) and viewingPrivKey (scan).
 *   Sender uses recipient's stealthMetaAddress to derive a one-time stealth address
 *   via ECDH, sends tokens there, and announces the ephemeral pubkey + view tag.
 *   Recipient scans Announcement events with the viewing key to find funds.
 *
 *   COMPLIANCE: sharing viewingPrivKey lets an auditor SEE payments but NOT SPEND.
 */
contract StealthRegistry {
    uint256 public constant SCHEME_ID = 1; // secp256k1

    // ─── EVENTS ───────────────────────────────────
    event Announcement(
        uint256 indexed schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes ephemeralPubKey,
        bytes metadata
    );

    event StealthMetaAddressSet(address indexed registrant, uint256 indexed schemeId, bytes stealthMetaAddress);

    // ─── STORAGE ──────────────────────────────────
    // user => schemeId => stealthMetaAddress (66 bytes: spendingPubKey33 + viewingPubKey33)
    mapping(address => mapping(uint256 => bytes)) public stealthMetaAddressOf;

    // ─── REGISTER ─────────────────────────────────
    /**
     * @notice Register your stealth meta-address so others can pay you privately.
     * @param stealthMetaAddress abi.encodePacked(spendingPubKey, viewingPubKey) — 66 bytes
     */
    function registerStealthMetaAddress(uint256 schemeId, bytes calldata stealthMetaAddress) external {
        require(schemeId == SCHEME_ID, "Stealth: BAD_SCHEME");
        require(stealthMetaAddress.length == 66, "Stealth: BAD_LENGTH");
        stealthMetaAddressOf[msg.sender][schemeId] = stealthMetaAddress;
        emit StealthMetaAddressSet(msg.sender, schemeId, stealthMetaAddress);
    }

    function getStealthMetaAddress(address user, uint256 schemeId) external view returns (bytes memory) {
        return stealthMetaAddressOf[user][schemeId];
    }

    // ─── ANNOUNCE ─────────────────────────────────
    /**
     * @notice Announce a stealth payment. Call after sending tokens to stealthAddress.
     * @param ephemeralPubKey 33-byte compressed secp256k1 pubkey (fresh random per payment)
     * @param metadata        byte[0]=viewTag, then funcSig/token/amount
     */
    function announce(
        uint256 schemeId,
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes calldata metadata
    ) external {
        require(schemeId == SCHEME_ID, "Stealth: BAD_SCHEME");
        require(stealthAddress != address(0), "Stealth: ZERO_ADDR");
        require(ephemeralPubKey.length == 33, "Stealth: BAD_PUBKEY");
        require(metadata.length >= 1, "Stealth: NO_VIEWTAG");

        emit Announcement(schemeId, stealthAddress, msg.sender, ephemeralPubKey, metadata);
    }

    // ─── PRIVATE TRANSFER ─────────────────────────
    /**
     * @notice Transfer ERC-20 to a stealth address and announce in one tx.
     */
    function privateTransfer(
        address token,
        address stealthAddress,
        uint256 amount,
        bytes calldata ephemeralPubKey,
        bytes1 viewTag
    ) external {
        require(stealthAddress != address(0), "Stealth: ZERO_ADDR");
        require(amount > 0, "Stealth: ZERO_AMOUNT");
        require(ephemeralPubKey.length == 33, "Stealth: BAD_PUBKEY");

        IMinimalERC20(token).transferFrom(msg.sender, stealthAddress, amount);

        bytes memory metadata = abi.encodePacked(
            viewTag,
            bytes4(0x23b872dd), // transferFrom selector
            bytes20(token),
            bytes32(amount)
        );

        emit Announcement(SCHEME_ID, stealthAddress, msg.sender, ephemeralPubKey, metadata);
    }

    /**
     * @notice Send native HSK to a stealth address and announce.
     */
    function privateTransferNative(address stealthAddress, bytes calldata ephemeralPubKey, bytes1 viewTag)
        external
        payable
    {
        require(stealthAddress != address(0), "Stealth: ZERO_ADDR");
        require(msg.value > 0, "Stealth: ZERO_VALUE");
        require(ephemeralPubKey.length == 33, "Stealth: BAD_PUBKEY");

        (bool ok,) = stealthAddress.call{value: msg.value}("");
        require(ok, "Stealth: TRANSFER_FAILED");

        bytes memory metadata = abi.encodePacked(
            viewTag,
            bytes4(0xeeeeeeee),
            bytes20(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)),
            bytes32(msg.value)
        );

        emit Announcement(SCHEME_ID, stealthAddress, msg.sender, ephemeralPubKey, metadata);
    }
}

interface IMinimalERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
