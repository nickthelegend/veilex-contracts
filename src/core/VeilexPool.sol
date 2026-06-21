// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./VeilexERC20.sol";

interface IPoolERC20 {
    function balanceOf(address owner) external view returns (uint256);
}

/// @dev Minimal math helpers (ported from Uniswap's Math library, SafeMath-free).
library VeilexMath {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    // babylonian method
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

/// @dev UQ112.112 fixed-point for TWAP price accumulators.
library UQ112x112 {
    uint224 constant Q112 = 2 ** 112;

    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112;
    }

    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}

/**
 * @title VeilexPool
 * @notice Veilex AMM pool. Based on UniswapV2Pair, ported to 0.8.x.
 *         Differences from Uniswap V2:
 *           - SafeMath removed (native overflow checks)
 *           - flash-swap callback removed entirely
 *           - swap() is VAULT-ONLY — MEV bots cannot call it directly
 *           - fee lowered to 25 bps (0.25%)
 *           - protocol fee (feeTo) removed — 100% of fees accrue to LPs
 *         Reference: references_/UniswapV2Pair.sol
 */
contract VeilexPool is VeilexERC20 {
    using VeilexMath for uint256;
    using UQ112x112 for uint224;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 public constant FEE_BPS = 25; // 0.25%
    uint256 public constant BPS_DENOM = 10000;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    address public token0;
    address public token1;

    address public vault; // only the vault may call swap()

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    uint256 private unlocked = 1;
    modifier nonReentrant() {
        require(unlocked == 1, "Veilex: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Veilex: FORBIDDEN");
        _;
    }

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() {
        factory = msg.sender;
    }

    function getReserves()
        public
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "Veilex: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }

    // called once by the factory to wire the MEV-protection vault
    function setVault(address _vault) external {
        require(msg.sender == factory, "Veilex: FORBIDDEN");
        require(vault == address(0), "Veilex: VAULT_SET");
        vault = _vault;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Veilex: TRANSFER_FAILED");
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "Veilex: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        unchecked {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow desired
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // low-level — must be called by a router/contract performing safety checks
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IPoolERC20(token0).balanceOf(address(this));
        uint256 balance1 = IPoolERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = VeilexMath.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock first MINIMUM_LIQUIDITY
        } else {
            liquidity = VeilexMath.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
        }
        require(liquidity > 0, "Veilex: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    // low-level — must be called by a router/contract performing safety checks
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IPoolERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IPoolERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply;
        amount0 = liquidity * balance0 / _totalSupply; // pro-rata distribution
        amount1 = liquidity * balance1 / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "Veilex: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IPoolERC20(_token0).balanceOf(address(this));
        balance1 = IPoolERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /**
     * @notice Quote the output for a given input token & amount, 25 bps fee applied.
     * @param amountIn amount of tokenIn being sold
     * @param tokenIn  must be token0 or token1 of this pool
     */
    function getAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256 amountOut) {
        require(amountIn > 0, "Veilex: INSUFFICIENT_INPUT_AMOUNT");
        require(tokenIn == token0 || tokenIn == token1, "Veilex: INVALID_TOKEN");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        (uint256 reserveIn, uint256 reserveOut) =
            tokenIn == token0 ? (uint256(_reserve0), uint256(_reserve1)) : (uint256(_reserve1), uint256(_reserve0));
        require(reserveIn > 0 && reserveOut > 0, "Veilex: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * (BPS_DENOM - FEE_BPS); // * 9975
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * BPS_DENOM + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @notice Execute a swap. VAULT-ONLY — bots cannot front-run by calling this directly.
     *         No flash-swap callback. Enforces 25 bps fee via the k invariant.
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external onlyVault nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "Veilex: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "Veilex: INSUFFICIENT_LIQUIDITY");

        uint256 balance0;
        uint256 balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "Veilex: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            balance0 = IPoolERC20(_token0).balanceOf(address(this));
            balance1 = IPoolERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "Veilex: INSUFFICIENT_INPUT_AMOUNT");
        {
            // 25 bps fee: balanceAdjusted = balance*10000 - amountIn*25
            uint256 balance0Adjusted = balance0 * BPS_DENOM - amount0In * FEE_BPS;
            uint256 balance1Adjusted = balance1 * BPS_DENOM - amount1In * FEE_BPS;
            require(
                balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * (BPS_DENOM ** 2),
                "Veilex: K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external nonReentrant {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(_token0, to, IPoolERC20(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, to, IPoolERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    // force reserves to match balances
    function sync() external nonReentrant {
        _update(
            IPoolERC20(token0).balanceOf(address(this)),
            IPoolERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}
