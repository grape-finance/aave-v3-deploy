// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {Errors} from "../protocol/libraries/helpers/Errors.sol";
import {IACLManager} from "../interfaces/IACLManager.sol";
import {IPoolAddressesProvider} from "../interfaces/IPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "../interfaces/IPriceOracleGetter.sol";
import {IAaveOracle} from "../interfaces/IAaveOracle.sol";

/**
 * @title AaveOracle
 * @notice Contract to fetch asset prices from Pyth
 */
contract AaveOracle is IAaveOracle {
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

    // Map of asset price feed IDs (asset => Pyth price feed ID)
    mapping(address => bytes32) private priceFeedIds;

    IPyth public immutable pyth;
    // IPriceOracleGetter private _fallbackOracle;
    address public immutable override BASE_CURRENCY;
    uint256 public immutable override BASE_CURRENCY_UNIT;

    // Add Twap Oracle
    IPriceOracleGetter public TWAP_ORACLE;

    // Map to track which assets use Twap Oracle
    mapping(address => bool) public isTwapAsset;

    /**
     * @dev Only asset listing or pool admin can call functions marked by this modifier.
     */
    modifier onlyAssetListingOrPoolAdmins() {
        _onlyAssetListingOrPoolAdmins();
        _;
    }

    /**
     * @notice Constructor
     * @param provider The address of the PoolAddressesProvider
     * @param _pythAddress The address of the Pyth contract
     * @param assets The addresses of the assets
   * @param sources The address of the source of each asset
   
     * @param baseCurrency The base currency used for the price quotes
     * @param baseCurrencyUnit The unit of the base currency
     */
    constructor(
        IPoolAddressesProvider provider,
        address _pythAddress,
        address[] memory assets,
        bytes32[] memory sources,
        address baseCurrency,
        uint256 baseCurrencyUnit
    ) {
        ADDRESSES_PROVIDER = provider;
        pyth = IPyth(_pythAddress);
        _setAssetsSources(assets, sources);
        BASE_CURRENCY = baseCurrency;
        BASE_CURRENCY_UNIT = baseCurrencyUnit;
        emit BaseCurrencySet(baseCurrency, baseCurrencyUnit);
    }

    /**
     * @notice Sets the Pyth price feed ID for an asset
     * @param assets The address of the asset
     * @param feedIds The Pyth price feed ID for the asset
     */
    function setPriceFeedIds(
        address[] calldata assets,
        bytes32[] calldata feedIds
    ) external onlyAssetListingOrPoolAdmins {
        _setAssetsSources(assets, feedIds);
    }

    /**
     * @notice Internal function to set the sources for each asset
     * @param assets The addresses of the assets
     * @param sources The address of the source of each asset
     */
    function _setAssetsSources(
        address[] memory assets,
        bytes32[] memory sources
    ) internal {
        require(
            assets.length == sources.length,
            Errors.INCONSISTENT_PARAMS_LENGTH
        );
        for (uint256 i = 0; i < assets.length; i++) {
            priceFeedIds[assets[i]] = sources[i];
            emit AssetSourceUpdated(assets[i], sources[i]);
        }
    }

    /**
     * @notice Sets the Twap Oracle
     * @param _TwapOracleAddress The address of the Twap Oracle
     */
    function setTwapOracle(
        address _TwapOracleAddress
    ) external onlyAssetListingOrPoolAdmins {
        TWAP_ORACLE = IPriceOracleGetter(_TwapOracleAddress);
    }

    /**
     * @notice Sets assets to use Twap Oracle
     * @param assets The addresses of the assets
     * @param useTwap Boolean array indicating whether each asset uses Twap
     */
    function setTwapAssets(
        address[] calldata assets,
        bool[] calldata useTwap
    ) external onlyAssetListingOrPoolAdmins {
        require(
            assets.length == useTwap.length,
            Errors.INCONSISTENT_PARAMS_LENGTH
        );
        for (uint256 i = 0; i < assets.length; i++) {
            isTwapAsset[assets[i]] = useTwap[i];
            emit TwapAssetUpdated(assets[i], useTwap[i]);
        }
    }

    /// @inheritdoc IPriceOracleGetter
    function getAssetPrice(
        address asset
    ) public view override returns (uint256) {
        if (asset == BASE_CURRENCY) {
            return BASE_CURRENCY_UNIT;
        }

        // Use Twap Oracle for LP tokens
        if (isTwapAsset[asset]) {
            return TWAP_ORACLE.getAssetPrice(asset);
        }

        // Use Pyth for other assets
        bytes32 feedId = priceFeedIds[asset];
        PythStructs.Price memory price = pyth.getPriceUnsafe(feedId);
        require(price.price > 0, "Invalid Pyth price");
        return uint256(uint64(price.price));
    }

    /// @inheritdoc IAaveOracle
    function getAssetsPrices(
        address[] calldata assets
    ) external view override returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = getAssetPrice(assets[i]);
        }
        return prices;
    }

    /// @inheritdoc IAaveOracle
    function getSourceOfAsset(
        address asset
    ) external view override returns (bytes32) {
        return priceFeedIds[asset];
    }

    function _onlyAssetListingOrPoolAdmins() internal view {
        IACLManager aclManager = IACLManager(
            ADDRESSES_PROVIDER.getACLManager()
        );
        require(
            aclManager.isAssetListingAdmin(msg.sender) ||
                aclManager.isPoolAdmin(msg.sender),
            Errors.CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN
        );
    }

    // Add event for Twap asset updates
    event TwapAssetUpdated(address indexed asset, bool useTwap);
}
