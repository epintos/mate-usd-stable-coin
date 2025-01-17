// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployMATE} from "script/DeployMATE.s.sol";
import {MATEStableCoin} from "src/MATEStableCoin.sol";
import {MATEEngine} from "src/MATEEngine.sol";
import {ERC20Mock} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockFailedMintMATE} from "test/mocks/MockFailedMintMATE.sol";

contract MATEEngineTest is Test {
    DeployMATE deployer;
    MATEEngine mateEngine;
    MATEStableCoin mateStableCoin;
    HelperConfig helperConfig;
    address ethUSDPriceFeed;
    address btcUSDPriceFeed;
    address wETH;
    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_MATE = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address public LIQUIDATOR = makeAddr("LIQUIDATOR");
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    /// EVENTS ///
    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    function setUp() public {
        deployer = new DeployMATE();
        (mateStableCoin, mateEngine, helperConfig) = deployer.run();
        (ethUSDPriceFeed, btcUSDPriceFeed, wETH,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(wETH).mint(USER, STARTING_ERC20_BALANCE);
    }

    // constructor
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    modifier depositedCollateral(address token) {
        vm.startPrank(USER);
        ERC20Mock(token).approve(address(mateEngine), AMOUNT_COLLATERAL);
        mateEngine.depositCollateral(token, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintMATE(address token) {
        vm.startPrank(USER);
        // Approve to deposit collateral
        ERC20Mock(token).approve(address(mateEngine), AMOUNT_COLLATERAL);
        mateEngine.depositCollateralAndMintMATE(token, AMOUNT_COLLATERAL, AMOUNT_MATE);
        vm.stopPrank();
        _;
    }

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(wETH);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(btcUSDPriceFeed);
        vm.expectRevert(MATEEngine.MATEEngine__TokenAddressesAndPriceFeedAdddressesMustBeSameLength.selector);
        new MATEEngine(tokenAddresses, priceFeedAddresses, address(mateStableCoin));
    }

    // getUSDValue
    function testGetUSDValue() public view {
        uint256 ethAmount = 15 ether; // 15e18
        // 15e18 * $2000 (ETH_USD_PRICE mocked in HelperConfig) = 30000e18
        uint256 expectedUSDValue = 30000e18;
        uint256 actualUSDValue = mateEngine.getUSDValue(wETH, ethAmount);
        assertEq(actualUSDValue, expectedUSDValue);
    }

    // getTokenAmountFromUSD
    function testGetTokenAmountFromUSD() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWETH = 0.05 ether; // 1ETH -> $2000. $100 -> 0.05 ETH
        uint256 actualWETH = mateEngine.getTokenAmountFromUSD(wETH, usdAmount);
        assertEq(expectedWETH, actualWETH);
    }

    // getHealthFactor
    function testGetHealthFactor() public depositedCollateralAndMintMATE(wETH) {
        uint256 expectedFactor = 100 ether; // 100e18
        uint256 healthFactor = mateEngine.getHealthFactor(USER);
        assertEq(healthFactor, expectedFactor);
    }

    function testGetHealthFactorCanBeBroken() public depositedCollateralAndMintMATE(wETH) {
        int256 ethUSDUpdatedPrice = 18e8; // 1 ETH = $18

        // Updates ETH/USD price
        // 10 (ETH) * 18$ * 0.5 = 90
        // 90 / 100 = 0.9
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(ethUSDUpdatedPrice);
        uint256 healthFactor = mateEngine.getHealthFactor(USER);
        assertEq(healthFactor, 0.9 ether);
    }

    // depositCollateral
    function testDepositCollateralRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        vm.expectRevert(MATEEngine.MATEEngine__NeedsMoreThanZero.selector);
        mateEngine.depositCollateral(wETH, 0);
        vm.stopPrank();
    }

    function testDepositCollateralRevertsWithNotSupportedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("RANDOM", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(MATEEngine.MATEEngine__NotAllowedToken.selector);
        mateEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralAndGetAccountInfo() public depositedCollateral(wETH) {
        (uint256 totalMATEMinted, uint256 collateralValueInUSD) = mateEngine.getAccountInformation(USER);

        uint256 expectedTotalMATEMinted = 0;
        uint256 expectedDepositCollateralAmount = mateEngine.getTokenAmountFromUSD(wETH, collateralValueInUSD);
        assertEq(totalMATEMinted, expectedTotalMATEMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositCollateralAmount);
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(mateEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(mateEngine));
        emit CollateralDeposited(USER, wETH, AMOUNT_COLLATERAL);
        mateEngine.depositCollateral(wETH, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // redeemCollateral
    function testRedeemCollateralRevertsIfAmountZero() public {
        vm.startPrank(USER);
        vm.expectRevert(MATEEngine.MATEEngine__NeedsMoreThanZero.selector);
        mateEngine.redeemCollateral(wETH, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralUpdatesColateral() public depositedCollateral(wETH) {
        vm.startPrank(USER);
        (, uint256 previousTotalCollateralInUSD) = mateEngine.getAccountInformation(USER);
        uint256 previousTotalCollateral = mateEngine.getTokenAmountFromUSD(wETH, previousTotalCollateralInUSD);
        mateEngine.redeemCollateral(wETH, AMOUNT_COLLATERAL);
        (, uint256 totalCollateralInUSD) = mateEngine.getAccountInformation(USER);
        uint256 totalCollateral = mateEngine.getTokenAmountFromUSD(wETH, totalCollateralInUSD);
        assertEq(previousTotalCollateral - AMOUNT_COLLATERAL, totalCollateral);
        vm.stopPrank();
    }

    function testRedeemCollateralUpdatesUserBalance() public depositedCollateral(wETH) {
        vm.startPrank(USER);
        uint256 initalUserBalance = ERC20Mock(wETH).balanceOf(USER);
        mateEngine.redeemCollateral(wETH, AMOUNT_COLLATERAL);

        uint256 userBalance = ERC20Mock(wETH).balanceOf(USER);
        assertEq(userBalance, initalUserBalance + AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralEmitsEvent() public depositedCollateral(wETH) {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, false, address(mateEngine));
        emit CollateralRedeemed(USER, USER, wETH, AMOUNT_COLLATERAL);
        mateEngine.redeemCollateral(wETH, 1 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfHealthCheckFails() public depositedCollateralAndMintMATE(wETH) {
        vm.startPrank(USER);
        // Health factor fails if we only keep 0.01 ether as collateral
        uint256 newCollateralValue = 0.01 ether;
        uint256 healthFactor =
            mateEngine.calculateHealthFactor(AMOUNT_MATE, mateEngine.getUSDValue(wETH, newCollateralValue));
        vm.expectRevert(abi.encodeWithSelector(MATEEngine.MATEEngine__BreaksHealthFactor.selector, healthFactor));
        mateEngine.redeemCollateral(wETH, AMOUNT_COLLATERAL - newCollateralValue);
        vm.stopPrank();
    }

    // burnMATE
    function testBurnMATEReducesTheUsersMATEAmount() public depositedCollateralAndMintMATE(wETH) {
        vm.startPrank(USER);
        // Approve transfer of MATE back to the contract to burn
        mateStableCoin.approve(address(mateEngine), AMOUNT_MATE);
        mateEngine.burnMATE(AMOUNT_MATE);
        (uint256 totalMATEMinted,) = mateEngine.getAccountInformation(USER);
        assertEq(0, totalMATEMinted);
        vm.stopPrank();
    }

    // mintMATE
    function testMintMATEIncreasesTheContractBalance() public depositedCollateral(wETH) {
        (uint256 initialTotalMATEMinted,) = mateEngine.getAccountInformation(USER);
        vm.prank(USER);
        mateEngine.mintMATE(AMOUNT_MATE);
        (uint256 totalMATEMinted,) = mateEngine.getAccountInformation(USER);
        assertEq(initialTotalMATEMinted + AMOUNT_MATE, totalMATEMinted);
    }

    function testMintMATEUpdatesUserBalance() public depositedCollateral(wETH) {
        vm.prank(USER);
        mateEngine.mintMATE(AMOUNT_MATE);
        uint256 userBalance = mateStableCoin.balanceOf(USER);
        assertEq(AMOUNT_MATE, userBalance);
    }

    function testMintMATERevertsIfHealthCheckIsBroken() public {
        uint256 expectedHealthFactor = 0;
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(MATEEngine.MATEEngine__BreaksHealthFactor.selector, expectedHealthFactor)
        );
        mateEngine.mintMATE(AMOUNT_MATE);
    }

    function testMintMATERevertsIfMintFails() public {
        // Mock setup with failing mint function
        MockFailedMintMATE mockMateStableCoin = new MockFailedMintMATE();
        tokenAddresses = [wETH];
        priceFeedAddresses = [ethUSDPriceFeed];
        MATEEngine mockMATEEngine = new MATEEngine(tokenAddresses, priceFeedAddresses, address(mockMateStableCoin));
        mockMateStableCoin.transferOwnership(address(mockMATEEngine));

        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(mockMATEEngine), AMOUNT_COLLATERAL);
        mockMATEEngine.depositCollateral(wETH, AMOUNT_COLLATERAL);
        vm.expectRevert(MATEEngine.MATEEngine__MintFailed.selector);
        mockMATEEngine.mintMATE(AMOUNT_MATE);
        vm.stopPrank();
    }

    function testMintMATERevertsIfAmountIsNotPositive() public depositedCollateral(wETH) {
        vm.prank(USER);
        vm.expectRevert(MATEEngine.MATEEngine__NeedsMoreThanZero.selector);
        mateEngine.mintMATE(0);
    }

    // depositCollateralAndMintMATE
    function testDepositCollateralAndMintMATERevertsIfHealthCheckIfBroken() public {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(mateEngine), AMOUNT_COLLATERAL);
        (, int256 price,,,) = MockV3Aggregator(ethUSDPriceFeed).latestRoundData();

        // 10 (ETH) * 2000$ = $20000 which is high enought to break the health factor.
        // We need double the amount of collateral for that value
        uint256 amountMATEToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * mateEngine.getAdditionalFeedPrecision())) / mateEngine.getPrecision();
        uint256 healthFactor =
            mateEngine.calculateHealthFactor(amountMATEToMint, mateEngine.getUSDValue(wETH, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(MATEEngine.MATEEngine__BreaksHealthFactor.selector, healthFactor));

        mateEngine.depositCollateralAndMintMATE(wETH, AMOUNT_COLLATERAL, amountMATEToMint);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintMATEUpdatesUserBalance() public depositedCollateralAndMintMATE(wETH) {
        uint256 userBalance = mateStableCoin.balanceOf(USER);
        assertEq(AMOUNT_MATE, userBalance);
    }

    function testDepositCollateralAndMintMATEUpdatesCollateralBalance() public depositedCollateralAndMintMATE(wETH) {
        vm.startPrank(USER);
        uint256 collateralBalance = ERC20Mock(wETH).balanceOf(address(mateEngine));
        assertEq(AMOUNT_COLLATERAL, collateralBalance);
        vm.stopPrank();
    }

    // redeemCollateralForMATE
    function testRedeemCollateralForMATEUpdatesUserMATEBalance() public depositedCollateralAndMintMATE(wETH) {
        vm.startPrank(USER);
        mateStableCoin.approve(address(mateEngine), AMOUNT_MATE);
        uint256 userMATEBalance = mateStableCoin.balanceOf(USER);
        mateEngine.redeemCollateralForMATE(wETH, AMOUNT_COLLATERAL, AMOUNT_MATE);
        uint256 newUserMATEBalance = mateStableCoin.balanceOf(USER);
        assertEq(userMATEBalance - AMOUNT_MATE, newUserMATEBalance);
        vm.stopPrank();
    }

    function testRedeemCollateralForMATEUpdatesUserETHBalance() public depositedCollateralAndMintMATE(wETH) {
        vm.startPrank(USER);
        mateStableCoin.approve(address(mateEngine), AMOUNT_MATE);
        uint256 userCollateralBalance = ERC20Mock(wETH).balanceOf(USER);
        mateEngine.redeemCollateralForMATE(wETH, AMOUNT_COLLATERAL, AMOUNT_MATE);
        uint256 newUserCollateralBalance = ERC20Mock(wETH).balanceOf(USER);
        assertEq(userCollateralBalance + AMOUNT_COLLATERAL, newUserCollateralBalance);
        vm.stopPrank();
    }

    // liquidate
    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(mateEngine), AMOUNT_COLLATERAL);
        mateEngine.depositCollateralAndMintMATE(wETH, AMOUNT_COLLATERAL, AMOUNT_MATE);
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18 => 0.9 health factor
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = mateEngine.getHealthFactor(USER);

        ERC20Mock(wETH).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wETH).approve(address(mateEngine), COLLATERAL_TO_COVER);
        mateEngine.depositCollateralAndMintMATE(wETH, COLLATERAL_TO_COVER, AMOUNT_MATE); // 1.8 health factor
        mateStableCoin.approve(address(mateEngine), AMOUNT_MATE);
        mateEngine.liquidate(wETH, USER, AMOUNT_MATE); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidatedTransfersCollateralToLiquidator() public liquidated {
        uint256 liquidatorCollateralBalance = ERC20Mock(wETH).balanceOf(LIQUIDATOR);
        uint256 tokenAmountFromDebtCovered = mateEngine.getTokenAmountFromUSD(wETH, AMOUNT_MATE);
        uint256 bonusCollateral =
            (tokenAmountFromDebtCovered * mateEngine.getLiquidationBonus()) / mateEngine.getLiquidationPrecision();
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        assertEq(totalCollateralToRedeem, 6_111_111_111_111_111_110);
        assertEq(liquidatorCollateralBalance, totalCollateralToRedeem);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 tokenAmountFromDebtCovered = mateEngine.getTokenAmountFromUSD(wETH, AMOUNT_MATE);
        uint256 bonusCollateral =
            (tokenAmountFromDebtCovered * mateEngine.getLiquidationBonus()) / mateEngine.getLiquidationPrecision();
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        uint256 usdAmountLiquidated = mateEngine.getUSDValue(wETH, totalCollateralToRedeem);
        uint256 expectedUserCollateralValueInUSD =
            mateEngine.getUSDValue(wETH, AMOUNT_COLLATERAL) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUSD) = mateEngine.getAccountInformation(USER);
        uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020;
        assertEq(userCollateralValueInUSD, expectedUserCollateralValueInUSD);
        assertEq(userCollateralValueInUSD, hardCodedExpectedValue);
    }

    function testLiquidateRevertsIfAmountIsZero() public {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(MATEEngine.MATEEngine__NeedsMoreThanZero.selector);
        mateEngine.liquidate(wETH, USER, 0);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfUserHealthFactorIsOk() public depositedCollateralAndMintMATE(wETH) {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(MATEEngine.MATEEngine__HealthFactorOk.selector);
        mateEngine.liquidate(wETH, USER, AMOUNT_MATE);
        vm.stopPrank();
    }

    function testLiquidateLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = mateEngine.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, AMOUNT_MATE);
    }

    function testLiquidateUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = mateEngine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    function testLiquidateUserStillHasMATE() public liquidated {
        uint256 mateBalance = mateStableCoin.balanceOf(USER);
        assertEq(mateBalance, AMOUNT_MATE);
    }

    function testLiquidateLiquidatorBurnedAllMATE() public liquidated {
        uint256 mateBalance = mateStableCoin.balanceOf(LIQUIDATOR);
        assertEq(mateBalance, 0);
    }
}
