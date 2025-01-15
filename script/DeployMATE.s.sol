// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MATEStableCoin} from "src/MATEStableCoin.sol";
import {MATEEngine} from "src/MATEEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployMATE is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (MATEStableCoin, MATEEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wETHUSDPriceFeed, address wBTCUSDPriceFeed, address wETH, address wBTC,) = config.activeNetworkConfig();
        tokenAddresses = [wETH, wBTC];
        priceFeedAddresses = [wETHUSDPriceFeed, wBTCUSDPriceFeed];
        vm.startBroadcast(msg.sender);
        MATEStableCoin mateContract = new MATEStableCoin();
        MATEEngine engineContract = new MATEEngine(tokenAddresses, priceFeedAddresses, address(mateContract));

        mateContract.transferOwnership(address(engineContract)); // Updates the Ownable
        vm.stopBroadcast();
        return (mateContract, engineContract, config);
    }
}
