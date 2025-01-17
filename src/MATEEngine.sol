// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {MATEStableCoin} from "./MATEStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MATEEngine
 * @author Esteban Pintos
 *
 * The system is designed to be as minimal as possible, and have the tokens mantain a 1 token = 1 USD value.
 * This stablecoin has the properties:
 * - Exogenous Collateral: wETH & wBTC
 * - Anchored to USD
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH and wBTC.
 *
 * Our MATE System should always be "overcollateralized". At no point, should the value of all
 * collateral be less than the dollar backed value of all MATE in circulation.
 *
 * @notice This contract is the core of the MATE System. It handles all the logic of mining and redeeming MATE, as well
 * as de depositing and withdrawing collateral.
 * @notice This contract is very lossely based on the MakerDAO DSS (DAI) system.
 */
contract MATEEngine is ReentrancyGuard {
    /// ERRORS ///
    error MATEEngine__NeedsMoreThanZero();
    error MATEEngine__TokenAddressesAndPriceFeedAdddressesMustBeSameLength();
    error MATEEngine__NotAllowedToken();
    error MATEEngine__TranferFailed();
    error MATEEngine__BreaksHealthFactor(uint256 healthFactor);
    error MATEEngine__MintFailed();
    error MATEEngine__HealthFactorOk();
    error MATEEngine__HealthFactorNotImproved();

    /// STATE VARIABLES ///
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMATEMinted) private s_MATEMinted;
    address[] private s_collateralTokens;

    MATEStableCoin private immutable i_MATE;

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

    /// MODIFIERS ///
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert MATEEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert MATEEngine__NotAllowedToken();
        }
        _;
    }

    /// FUNCTIONS ///

    // CONSTRUCTOR
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address MATEAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert MATEEngine__TokenAddressesAndPriceFeedAdddressesMustBeSameLength();
        }

        // For example: ETH -> USD, BTC -> USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_MATE = MATEStableCoin(MATEAddress);
    }

    // EXTERNAL FUNCTIONS

    /**
     * Deposits collateral and mints MATE tokens in one transaction
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of the token to be deposited as collateral
     * @param amountMATEToMint The amount of MATE tokens to mint (precision 1e18)
     */
    function depositCollateralAndMintMATE(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountMATEToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintMATE(amountMATEToMint);
    }

    /**
     * Burns MATE and redeems underlying collateral in one transaction
     * @param tokenCollateralAddress The address of the token to be redeemed as collateral
     * @param amountCollateral The amount of the token to be redeemed as collateral
     * @param amountMATEToBurn The amount of MATE tokens to burn
     * @dev redeemCollateral already checks health factor
     */
    function redeemCollateralForMATE(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountMATEToBurn)
        external
    {
        burnMATE(amountMATEToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param collateral The ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param mateDebtToCover The amount of MATE you want to burn to improve the user's health factor (precision 1e18)
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the user's funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for
     * this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't
     * be able to incentive the liquidators.For example, if the price of the collateral plummeted before
     * anyone could be liquidated.
     * @notice This function only reduces the user debt and keeps the MATE in the MATEStableCoin balance. The liquidator
     * MATE gets burned instead.
     */
    function liquidate(address collateral, address user, uint256 mateDebtToCover)
        external
        moreThanZero(mateDebtToCover)
        nonReentrant
    {
        // This is the user that is paying the debt and getting the collateral with a bonus
        address liquidator = msg.sender;

        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert MATEEngine__HealthFactorOk();
        }

        // How much debt in MATE is worth the collateral?
        // If they had $10 in MATE and the price of ETH is $2000, then the debt in ETH is 0.005 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, mateDebtToCover);

        // 0.005 ETH * 1e18 * 0.1 = 5e14 = 0.0005ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        // The would get 0.005 + 0.0005 = 0.0055 ETH
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, liquidator);
        _burnMATE(mateDebtToCover, user, liquidator);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert MATEEngine__HealthFactorNotImproved();
        }

        // Health factor should not be broken for the liquidator
        _revertIfHealthFactorIsBroken(liquidator);
    }

    // PUBLIC FUNCTIONS

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);

        // It is more gas efficient to do this after the transfer
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnMATE(uint256 amount) public moreThanZero(amount) {
        _burnMATE(amount, msg.sender, msg.sender);
    }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of the token to be deposited as collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert MATEEngine__TranferFailed();
        }
    }

    /**
     * @notice follows CEI pattern
     * @param amountMATEToMint The amount of MATE to mint (precision 1e18)
     * @notice they must have more collateral value than the mininum threshold
     */
    function mintMATE(uint256 amountMATEToMint) public moreThanZero(amountMATEToMint) nonReentrant {
        s_MATEMinted[msg.sender] += amountMATEToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_MATE.mint(msg.sender, amountMATEToMint);
        if (!minted) {
            revert MATEEngine__MintFailed();
        }
    }

    // PRIVATE & INTERNAL VIEW FUNCTIONS

    /**
     *
     * @dev Low-level internal function. Do not call unless the function calling it is checking for
     * health factors being broken.
     */
    function _burnMATE(uint256 amount, address onBehalfOf, address mateFrom) private {
        s_MATEMinted[onBehalfOf] -= amount; // In the liquidator, onBehalfOf would be the user we are liquidating
        bool success = i_MATE.transferFrom(mateFrom, address(this), amount); // And we get the MATE from the liquidator
        if (!success) {
            revert MATEEngine__TranferFailed();
        }
        //  liquidators MATE gets burned. The user still has the MATE, but has less MATE (debt) in this contract
        i_MATE.burn(amount);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert MATEEngine__TranferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalMATEMinted, uint256 collateralValueInUSD)
    {
        totalMATEMinted = s_MATEMinted[user];
        collateralValueInUSD = getAccountCollateralValueInUSD(user);
    }

    /**
     *
     * Returns how close to liquidation a user is
     * If a user goes below 100, then they can get liquidated.
     *
     * @param user The address of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalMATEMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(totalMATEMinted, collateralValueInUSD);
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert MATEEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalMATEMinted, uint256 collateralValueInUSD)
        private
        pure
        returns (uint256)
    {
        if (totalMATEMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // Examples:
        // $100e18 ETH collateral and $75 MATE minted
        // 100e18 * 50 / 100 = (50e18 * 1e18) / 75e18 = 6.67e17 < 1e18 - so it can be liquidated

        // $100 ETH collateral and $50 MATE minted
        // 100e18 * 50 / 100 = (50e18 * 1e18) / 50e18 = 1e18 < 1e18? - so it cannot be liquidated
        return (collateralAdjustedForThreshold * PRECISION) / totalMATEMinted;
    }

    // PUBLIC & EXTERNAL VIEW FUNCTIONS

    /**
     * Returns the equivalent amount of token for a given USD amount
     * Example: 1 ETH -> $2000 (calculated using PriceFed). We want to know How much ETH is $10 (e18)
     * ($10e18 * 1e18) / ($2000e8 * 1e10) = 0.005e18 = 5e15 => So $10 is 0.005 ETH
     * @param token The token address
     * @param usdAmountInWei USD amount in Wei (e18)
     */
    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValue += getUSDValue(token, amount);
        }
        return totalCollateralValue;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // If 1 ETH = $1000 => CL will return 1000 * 1e8
        // Amount is in Wei (1e18), so we to multiple price (in 1e8) by 1e10 to match the precision (1e18)
        // Then we divide by 1e18 since they result would be 1e36 => 1e18
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /**
     *
     * @param user Account owner
     * @return totalMATEMinted Total amount of MATE the user
     * @return collateralValueInUSD Total amount of collateral value in USD the user has
     * @notice the amounts are in precision 1e18
     */
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalMATEMinted, uint256 collateralValueInUSD)
    {
        (totalMATEMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    function getAdditionalFeedPrecision() public pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() public pure returns (uint256) {
        return PRECISION;
    }

    function getLiquidationBonus() public pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() public pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function calculateHealthFactor(uint256 totalMATEMinted, uint256 collateralValueInUSD)
        public
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalMATEMinted, collateralValueInUSD);
    }
}
