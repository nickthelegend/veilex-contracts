// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title dUSDC — Demo USD Coin
 * @notice A testnet, faucet-mintable USDC-style token (6 decimals) for Veilex /
 *         VeilPay on HashKey Chain. Not real money — anyone can mint from the
 *         faucet to test private payments and dark-pool swaps.
 *
 *  - faucet(): mints FAUCET_AMOUNT to the caller, rate-limited per address.
 *  - mint(to, amount): open mint (testnet convenience).
 */
contract DUSDC is ERC20 {
    uint8 private constant DECIMALS = 6;

    /// @notice Amount dispensed per faucet() call (1,000 dUSDC).
    uint256 public constant FAUCET_AMOUNT = 1_000 * 10 ** DECIMALS;
    /// @notice Cooldown between faucet() calls for a given address.
    uint256 public constant FAUCET_COOLDOWN = 1 hours;

    mapping(address => uint256) public lastFaucet;

    event Faucet(address indexed to, uint256 amount);

    constructor() ERC20("Demo USD Coin", "dUSDC") {}

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /// @notice Mint yourself FAUCET_AMOUNT of dUSDC (rate-limited).
    function faucet() external {
        require(block.timestamp >= lastFaucet[msg.sender] + FAUCET_COOLDOWN, "dUSDC: COOLDOWN");
        lastFaucet[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit Faucet(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Seconds remaining before `user` can use the faucet again (0 if ready).
    function faucetCooldownRemaining(address user) external view returns (uint256) {
        uint256 ready = lastFaucet[user] + FAUCET_COOLDOWN;
        return block.timestamp >= ready ? 0 : ready - block.timestamp;
    }

    /// @notice Open mint for testing. Testnet only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
