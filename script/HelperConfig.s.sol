// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {MATEStableCoin} from "src/MATEStableCoin.sol";
import {MATEEngine} from "src/MATEEngine.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wETHUSDPriceFeed;
        address wBTCUSDPriceFeed;
        address wETH;
        address wBTC;
        uint256 deployerAccount;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public constant wETH_INITIAL_BALANCE = 1000e8;
    uint256 public constant wBTC_INITIAL_BALANCE = 1000e8;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaETHConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilETHConfig();
        }
    }

    function getSepoliaETHConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            wETHUSDPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBTCUSDPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerAccount: 0x0 // TODO: Remove
        });
    }

    function getOrCreateAnvilETHConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wETHUSDPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUSDPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wETHMock = new ERC20Mock("Wrapped ETH", "wETH", msg.sender, wETH_INITIAL_BALANCE);
        MockV3Aggregator btcUSDPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wBTCMock = new ERC20Mock("Wrapped BTC", "wBTC", msg.sender, wBTC_INITIAL_BALANCE);
        vm.stopBroadcast();

        return NetworkConfig({
            wETHUSDPriceFeed: address(ethUSDPriceFeed),
            wBTCUSDPriceFeed: address(btcUSDPriceFeed),
            wETH: address(wETHMock),
            wBTC: address(wBTCMock),
            deployerAccount: 0x0 // TODO: Remove
        });
    }
}
