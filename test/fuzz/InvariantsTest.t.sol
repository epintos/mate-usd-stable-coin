// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DeployMATE } from "script/DeployMATE.s.sol";
import { MATEStableCoin } from "src/MATEStableCoin.sol";
import { MATEEngine } from "src/MATEEngine.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Handler } from "./Handler.t.sol";
// import { MockV3Aggregator } from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
// import {ERC20Mock} from
//     "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
// import {MockFailedMintMATE} from "test/mocks/MockFailedMintMATE.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployMATE deployer;
    MATEEngine mateEngine;
    MATEStableCoin mateStableCoin;
    HelperConfig helperConfig;
    address ethUSDPriceFeed;
    address btcUSDPriceFeed;
    address wETH;
    address wBTC;
    Handler handler;

    function setUp() public {
        deployer = new DeployMATE();
        (mateStableCoin, mateEngine, helperConfig) = deployer.run();
        (ethUSDPriceFeed, btcUSDPriceFeed, wETH, wBTC,) = helperConfig.activeNetworkConfig();
        handler = new Handler(mateEngine, mateStableCoin);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = mateStableCoin.totalSupply();
        uint256 totalWETHDeposited = IERC20(wETH).balanceOf(address(mateEngine));
        uint256 totalWBTCDeposited = IERC20(wBTC).balanceOf(address(mateEngine));

        uint256 wETHValueinUSD = mateEngine.getUSDValue(wETH, totalWETHDeposited);
        uint256 wBTCValueinUSD = mateEngine.getUSDValue(wBTC, totalWBTCDeposited);

        console2.log("MATE Total Supply: ", totalSupply);
        console2.log("Total ETH in USD deposited: ", wETHValueinUSD);
        console2.log("Total BTC in USD deposited: ", wBTCValueinUSD);

        assert(wETHValueinUSD + wBTCValueinUSD >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        mateEngine.getAccountCollateralValueInUSD(msg.sender);
        mateEngine.getAccountInformation(msg.sender);
        mateEngine.getAdditionalFeedPrecision();
        mateEngine.getCollateralBalanceOfUser(msg.sender, wETH);
        mateEngine.getCollateralBalanceOfUser(msg.sender, wBTC);
        mateEngine.getCollateralTokens();
        mateEngine.getHealthFactor(msg.sender);
        mateEngine.getLiquidationBonus();
        mateEngine.getLiquidationPrecision();
        mateEngine.getPrecision();
        mateEngine.getTokenAmountFromUSD(wETH, 1);
        mateEngine.getTokenAmountFromUSD(wBTC, 1);
        mateEngine.getUSDValue(wETH, 1);
        mateEngine.getUSDValue(wBTC, 1);
    }
}
