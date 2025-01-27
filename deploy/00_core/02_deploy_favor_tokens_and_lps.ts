import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

import {
  ConfigNames,
  eNetwork,
  FAVOR_ETH_ID,
  FAVOR_USDT_ID,
  getReserveAddresses,
  loadPoolConfig,
  UNISWAP_ROUTER_PER_NETWORK,
  V3_CORE_VERSION,
} from "../../helpers";
import { MARKET_NAME } from "../../helpers/env";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const poolConfig = await loadPoolConfig(MARKET_NAME as ConfigNames);

  const network = (
    process.env.FORK ? process.env.FORK : hre.network.name
  ) as eNetwork;
  console.log("network", network);

  // const reserveAssets = await getReserveAddresses(poolConfig, network);
  const USDC = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
  const WETH = "0x980B62Da83eFf3D4576C647993b0c1D7faf17c73";

  console.log("Deploying FavorTokens and creating LPs with account:", deployer);

  // Deploy FAVOR ETH
  const favorETH = await deploy(FAVOR_ETH_ID, {
    from: deployer,
    args: [ethers.utils.parseEther("100"), deployer],
    log: true,
    contract: "FavorETH",
  });
  console.log("FavorETH deployed to:", favorETH.address);

  // // Deploy FAVOR USDT
  // const favorUSDT = await deploy(FAVOR_USDT_ID, {
  //   from: deployer,
  //   args: [ethers.utils.parseUnits("100000000", 6), deployer],
  //   log: true,
  //   contract: "FavorUSDT",
  // });
  // console.log("FavorUSDT deployed to:", favorUSDT.address);

  // Get contract instances
  const WETHContract = await ethers.getContractAt(
    "contracts/core-v3/dependencies/openzeppelin/contracts/IERC20.sol:IERC20",
    WETH
  );
  const favorETHContract = await ethers.getContractAt(
    "FavorETH",
    favorETH.address
  );
  // const favorUSDTContract = await ethers.getContractAt(
  //   "FavorUSDT",
  //   favorUSDT.address
  // );

  const router = await ethers.getContractAt(
    "IUniswapV2Router02",
    UNISWAP_ROUTER_PER_NETWORK[hre.network.name]
  );

  // Approve router
  await (
    await WETHContract.approve(
      UNISWAP_ROUTER_PER_NETWORK[hre.network.name],
      ethers.utils.parseEther("0.1")
    )
  ).wait();

  await (
    await favorETHContract.approve(
      UNISWAP_ROUTER_PER_NETWORK[hre.network.name],
      ethers.utils.parseEther("0.1")
    )
  ).wait();

  // await (
  //   await favorUSDTContract.approve(
  //     UNISWAP_ROUTER_PER_NETWORK[hre.network.name],
  //     ethers.utils.parseUnits("100", 6)
  //   )
  // ).wait();

  // Add initial liquidity ETH/FAVOR ETH

  console.log(
    "Math.floor(Date.now() / 1000) + 1000",
    Math.floor(Date.now() / 1000) + 1000
  );

  await router.addLiquidity(
    WETH,
    favorETH.address,
    ethers.utils.parseEther("0.1"),
    ethers.utils.parseEther("0.1"),
    0,
    0,
    deployer,
    Math.floor(Date.now() / 1000) + 1000
    // { value: ethers.utils.parseEther("1") }
  );

  // await router.addLiquidity(
  //   reserveAssets["USDC"],
  //   favorUSDT.address,
  //   ethers.utils.parseEther("100"),
  //   ethers.utils.parseEther("100"),
  //   0,
  //   0,
  //   deployer,
  //   Math.floor(Date.now() / 1000) + 1000
  //   // { value: ethers.utils.parseEther("1") }
  // );

  const factory = await hre.ethers.getContractAt(
    "IUniswapV2Factory",
    await router.factory()
  );

  const FavorETHPairAddress = await factory.getPair(WETH, favorETH.address);

  console.log("FAVOR ETH/ETH LP Address:", FavorETHPairAddress);

  // const FavorUSDTPairAddress = await factory.getPair(
  //   reserveAssets["USDC"],
  //   favorUSDT.address
  // );

  // console.log("FAVOR USDT/USDT LP Address:", FavorUSDTPairAddress);

  // Set LP pairs in token contracts
  await (
    await favorETHContract.setMarketPair(FavorETHPairAddress, true)
  ).wait();
  // await (await favorUSDTContract.setMarketPair(FavorUSDTPairAddress)).wait();
};

func.id = `FavorTokens:${MARKET_NAME}:aave-v3-core@${V3_CORE_VERSION}`;

func.tags = ["core", "favor"];

func.dependencies = ["before-deploy"];

export default func;
