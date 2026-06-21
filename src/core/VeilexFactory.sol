// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./VeilexPool.sol";

/**
 * @title VeilexFactory
 * @notice Deploys and registers Veilex pools. Based on UniswapV2Factory, ported to 0.8.x.
 *         Differences:
 *           - feeTo / feeToSetter removed (fees stay with LPs)
 *           - holds the MEV-protection `vault`, set once, wired into every new pool
 *         Reference: references_/UniswapV2Factory.sol
 */
contract VeilexFactory {
    address public vault;
    bool public vaultSet;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event VaultSet(address indexed vault);

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Set the vault once. All pools created afterwards route swaps through it.
    function setVault(address _vault) external {
        require(!vaultSet, "Veilex: VAULT_SET");
        require(_vault != address(0), "Veilex: ZERO_VAULT");
        vault = _vault;
        vaultSet = true;
        emit VaultSet(_vault);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(vaultSet, "Veilex: VAULT_NOT_SET");
        require(tokenA != tokenB, "Veilex: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Veilex: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "Veilex: PAIR_EXISTS");

        bytes memory bytecode = type(VeilexPool).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        VeilexPool(pair).initialize(token0, token1);
        VeilexPool(pair).setVault(vault); // pass vault into the new pool

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
