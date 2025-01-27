import {
  getChainlinkOracles,
  getPythPriceFeed,
  getPythPriceIds,
} from "../../helpers/market-config-helpers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { COMMON_DEPLOY_PARAMS } from "../../helpers/env";
import {
  UNISWAP_ROUTER_PER_NETWORK,
  V3_CORE_VERSION,
  ZERO_ADDRESS,
} from "../../helpers/constants";
import {
  FALLBACK_ORACLE_ID,
  FAVOR_ETH_ID,
  FAVOR_USDT_ID,
  ORACLE_ID,
  POOL_ADDRESSES_PROVIDER_ID,
  TWAP_ORACLE_ID,
} from "../../helpers/deploy-ids";
import {
  loadPoolConfig,
  ConfigNames,
  getParamPerNetwork,
  checkRequiredEnvironment,
  getReserveAddresses,
} from "../../helpers/market-config-helpers";
import { eNetwork, ICommonConfiguration, SymbolMap } from "../../helpers/types";
import { getPairsTokenAggregator } from "../../helpers/init-helpers";
import { parseUnits } from "ethers/lib/utils";
import { MARKET_NAME } from "../../helpers/env";
import { ethers } from "hardhat";

const func: DeployFunction = async function ({
  getNamedAccounts,
  deployments,
  ...hre
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const poolConfig = await loadPoolConfig(MARKET_NAME as ConfigNames);
  const network = (
    process.env.FORK ? process.env.FORK : hre.network.name
  ) as eNetwork;

  const { OracleQuoteUnit } = poolConfig as ICommonConfiguration;

  const { address: addressesProviderAddress } = await deployments.get(
    POOL_ADDRESSES_PROVIDER_ID
  );

  const fallbackOracleAddress = ZERO_ADDRESS;

  const reserveAssets = await getReserveAddresses(poolConfig, network);
  const pythPriceFeed = await getPythPriceFeed(poolConfig, network);
  const chainlinkAggregators = await getChainlinkOracles(poolConfig, network);
  const pythPriceIds = await getPythPriceIds(poolConfig, network);

  const [assets, sources] = getPairsTokenAggregator(
    reserveAssets,
    pythPriceIds
  );

  // Deploy AaveOracle
  const aaveOracle = await deploy(ORACLE_ID, {
    from: deployer,
    args: [
      addressesProviderAddress,
      pythPriceFeed,
      assets,
      sources,
      // fallbackOracleAddress,
      ZERO_ADDRESS,
      parseUnits("1", OracleQuoteUnit),
    ],
    ...COMMON_DEPLOY_PARAMS,
    contract: "AaveOracle",
  });

  // Deploy TWAPOracle
  const twapOracle = await deploy(TWAP_ORACLE_ID, {
    from: deployer,
    args: [aaveOracle.address],
    log: true,
    contract: "TwapOracle",
  });

  // Set TWAPOracle for AaveOracle
  const aaveOracleContract = await ethers.getContractAt(
    "AaveOracle",
    aaveOracle.address
  );
  await aaveOracleContract.setTwapOracle(twapOracle.address);

  const favorETHLP = await deployments.get(FAVOR_ETH_ID);
  // const favorUSDTLP = await deployments.get(FAVOR_USDT_ID);
  const lpTokens = [favorETHLP.address];

  await aaveOracleContract.setTwapAssets(lpTokens, [true]);

  return true;
};

func.id = `Oracles:${MARKET_NAME}:aave-v3-core@${V3_CORE_VERSION}`;

func.tags = ["market", "oracle"];

func.dependencies = ["before-deploy", "favor-tokens"];

func.skip = async () => checkRequiredEnvironment();

export default func;
