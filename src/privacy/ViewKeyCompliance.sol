// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ViewKeyCompliance
 * @notice Compliance layer for Veilex privacy features.
 *
 *   viewingPrivKey  → CAN find incoming payments, CANNOT spend → SHARE with auditor
 *   spendingPrivKey → CAN spend funds → NEVER share
 *
 * HOW COMPLIANCE WORKS:
 * 1. User generates spendingKey + viewingKey pair
 * 2. User registers stealthMetaAddress on StealthRegistry
 * 3. On disclosure: user shares viewingPrivKey OFF-CHAIN, then calls disclosViewKey()
 *    ON-CHAIN with keccak256(viewingPrivKey) to prove disclosure happened
 * 4. Auditor scans Announcement events with the viewing key — sees, cannot spend
 */
contract ViewKeyCompliance {
    event ViewKeyDisclosed(address indexed user, address indexed auditor, bytes32 viewKeyHash, uint256 timestamp);
    event ComplianceNoteAdded(address indexed user, bytes32 noteHash, uint256 timestamp);

    mapping(address => mapping(address => bool)) public viewKeyShared;
    mapping(address => address[]) public userAuditors;
    mapping(address => bytes32[]) public complianceNotes;
    mapping(address => bool) public approvedAuditors;

    address public admin;

    constructor() {
        admin = msg.sender;
    }

    function approveAuditor(address auditor) external {
        require(msg.sender == admin, "Compliance: NOT_ADMIN");
        approvedAuditors[auditor] = true;
    }

    function revokeAuditor(address auditor) external {
        require(msg.sender == admin, "Compliance: NOT_ADMIN");
        approvedAuditors[auditor] = false;
    }

    /**
     * @notice Voluntarily disclose view key to a compliance officer.
     *         Share the raw viewingPrivKey OFF-CHAIN; call this ON-CHAIN to prove it.
     * @param viewKeyHash keccak256(viewingPrivateKey)
     */
    function disclosViewKey(address auditor, bytes32 viewKeyHash) external {
        require(approvedAuditors[auditor], "Compliance: NOT_AUDITOR");
        require(!viewKeyShared[msg.sender][auditor], "Compliance: ALREADY_DISCLOSED");

        viewKeyShared[msg.sender][auditor] = true;
        userAuditors[msg.sender].push(auditor);

        emit ViewKeyDisclosed(msg.sender, auditor, viewKeyHash, block.timestamp);
    }

    function addComplianceNote(bytes32 noteHash) external {
        complianceNotes[msg.sender].push(noteHash);
        emit ComplianceNoteAdded(msg.sender, noteHash, block.timestamp);
    }

    function hasDisclosed(address user, address auditor) external view returns (bool) {
        return viewKeyShared[user][auditor];
    }

    function getAuditors(address user) external view returns (address[] memory) {
        return userAuditors[user];
    }

    function getComplianceNotes(address user) external view returns (bytes32[] memory) {
        return complianceNotes[user];
    }
}
