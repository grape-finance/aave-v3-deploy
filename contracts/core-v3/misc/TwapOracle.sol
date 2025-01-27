// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {IPriceOracleGetter} from "../interfaces/IPriceOracleGetter.sol";
import {IUniswapV2Pair} from "../dependencies/uniswap/IUniswapV2Pair.sol";
import {Ownable} from "../dependencies/openzeppelin/contracts/Ownable.sol";
import {SafeMath} from "../dependencies/openzeppelin/contracts/SafeMath.sol";
import {IERC20} from "../dependencies/openzeppelin/contracts/IERC20.sol";

contract TwapOracle is Ownable {
    using SafeMath for uint256;

    // Price update interval
    uint256 public constant PERIOD = 3600; // 1 hour

    // Maximum price cap (in USD with 8 decimals)
    mapping(address => uint256) public maxPriceCap;

    // LP token to base token mapping (WETH or USDT)
    mapping(address => address) public baseToken;

    // Price accumulator for TWAP
    mapping(address => uint256) public priceAccumulator;

    // Last update timestamp
    mapping(address => uint256) public lastUpdateTimestamp;

    // Base token price feed (like Chainlink)
    IPriceOracleGetter public immutable BASE_PRICE_FEED;

    constructor(address basePriceFeed) {
        BASE_PRICE_FEED = IPriceOracleGetter(basePriceFeed);
    }

    // Admin function to set price cap
    function setMaxPriceCap(
        address lpToken,
        uint256 maxPrice
    ) external onlyOwner {
        maxPriceCap[lpToken] = maxPrice;
    }

    // Admin function to set base token for LP
    function setBaseToken(
        address lpToken,
        address _baseToken
    ) external onlyOwner {
        baseToken[lpToken] = _baseToken;
    }

    // Update price accumulator
    function updatePrice(address lpToken) public {
        require(baseToken[lpToken] != address(0), "Base token not set");

        IUniswapV2Pair pair = IUniswapV2Pair(lpToken);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        // Calculate LP token price
        uint256 totalSupply = pair.totalSupply();
        address token0 = pair.token0();
        address token1 = pair.token1();

        uint256 baseTokenReserve;
        if (token0 == baseToken[lpToken]) {
            baseTokenReserve = uint256(reserve0);
        } else {
            baseTokenReserve = uint256(reserve1);
        }

        // Get base token price from oracle (like Chainlink)
        uint256 baseTokenPrice = BASE_PRICE_FEED.getAssetPrice(
            baseToken[lpToken]
        );

        // Calculate LP token price (2 * sqrt(reserve0 * reserve1) / totalSupply)
        uint256 lpTokenPrice = (2 * baseTokenReserve * baseTokenPrice) /
            totalSupply;

        // Apply price cap if set
        if (maxPriceCap[lpToken] > 0) {
            lpTokenPrice = lpTokenPrice > maxPriceCap[lpToken]
                ? maxPriceCap[lpToken]
                : lpTokenPrice;
        }

        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp[lpToken];
        if (timeElapsed >= PERIOD) {
            priceAccumulator[lpToken] = lpTokenPrice;
            lastUpdateTimestamp[lpToken] = block.timestamp;
        } else {
            priceAccumulator[lpToken] =
                (
                    (priceAccumulator[lpToken] *
                        (PERIOD - timeElapsed) +
                        lpTokenPrice *
                        timeElapsed)
                ) /
                PERIOD;
        }
    }

    // Implement IPriceOracleGetter interface
    function getAssetPrice(address asset) external view returns (uint256) {
        require(priceAccumulator[asset] > 0, "Price not initialized");
        return priceAccumulator[asset];
    }
}
