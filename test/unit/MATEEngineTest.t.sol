// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployMATE} from "script/DeployMATE.s.sol";
import {MATEStableCoin} from "src/MATEStableCoin.sol";
import {MATEEngine} from "src/MATEEngine.sol";
import {ERC20Mock} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";

contract MATEEngineTest is Test {
    DeployMATE deployer;
    MATEEngine mateEngine;
    MATEStableCoin mateStableCoin;
    HelperConfig helperConfig;
    address ethUSDPriceFeed;
    address wETH;
    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployMATE();
        (mateStableCoin, mateEngine, helperConfig) = deployer.run();
        (ethUSDPriceFeed,, wETH,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(wETH).mint(USER, STARTING_ERC20_BALANCE);
    }

    // getUSDValue

    function testGetUSDValue() public view {
        uint256 ethAmount = 15 ether; // 15e18
        // 15e18 * $2000 (ETH_USD_PRICE mocked in HelperConfig) = 30000e18
        uint256 expectedUSDValue = 30000e18;
        uint256 actualUSDValue = mateEngine.getUSDValue(wETH, ethAmount);
        assertEq(actualUSDValue, expectedUSDValue);
    }

    // depositCollaborateral

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        // We need to approve the collateral first to be able to run transferFrom
        // ERC20Mock(wETH).approve(address(mateEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(MATEEngine.MATEEngine__NeedsMoreThanZero.selector);
        mateEngine.depositCollateral(wETH, 0);
        vm.stopPrank();
    }
}
