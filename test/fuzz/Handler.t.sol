// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { MATEStableCoin } from "src/MATEStableCoin.sol";
import { MATEEngine } from "src/MATEEngine.sol";
import { ERC20Mock } from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Handler is Test {
    MATEEngine mateEngine;
    MATEStableCoin mateStableCoin;
    ERC20Mock wETH;
    ERC20Mock wBTC;

    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUSDPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // we don't use uint256 so we can add more collateral later if needed

    constructor(MATEEngine _mateEngine, MATEStableCoin _mateStableCoin) {
        mateEngine = _mateEngine;
        mateStableCoin = _mateStableCoin;
        address[] memory collateralTokens = mateEngine.getCollateralTokens();
        wETH = ERC20Mock(collateralTokens[0]);
        wBTC = ERC20Mock(collateralTokens[1]);

        ethUSDPriceFeed = MockV3Aggregator(mateEngine.getCollateralTokenPriceFeed(address(wETH)));
    }

    function mintMATE(uint256 amount, uint256 addressSeed) public {
        vm.assume(usersWithCollateralDeposited.length > 0);
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalMATEMinted, uint256 collateralValueInUSD) = mateEngine.getAccountInformation(sender);
        int256 maxMATEToMint = (int256(collateralValueInUSD) / 2) - int256(totalMATEMinted);
        vm.assume(maxMATEToMint >= 0);
        amount = bound(amount, 0, uint256(maxMATEToMint));
        vm.assume(amount > 0);
        vm.startPrank(sender);
        mateEngine.mintMATE(amount);
        vm.stopPrank();
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(mateEngine), amountCollateral);
        mateEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender); // this might include duplicates
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        (uint256 totalMATEMinted, uint256 collateralValueInUSD) = mateEngine.getAccountInformation(msg.sender);
        vm.assume(collateralValueInUSD * 50 / 100 < totalMATEMinted);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = mateEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        vm.assume(amountCollateral > 0);
        vm.startPrank(msg.sender);
        mateEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // This is proof that if the price drops quickly, the system breaks.
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUSDPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return wETH;
        } else {
            return wBTC;
        }
    }
}
