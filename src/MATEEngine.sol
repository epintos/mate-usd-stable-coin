// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {MATEStableCoin} from "./MATEStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// interface IMATEEngine {
//     function depositCollateralAndMintMATE(address, uint256, uint256) external;

//     function depositCollaborateral(address, uint256) external;

//     function redeemCollaborateralForMATE() external;

//     function redeemCollateral() external;

//     function mintMATE(uint256) external;

//     function burnMATE() external;

//     function liquidate() external;

//     function getHealthFactor() external view;
// }

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
 * collaborateral be less than the dollar backed value of all MATE in circulation.
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

    /// STATE VARIABLES ///
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

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
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
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
     * @param amountMATEToMint The amount of MATE tokens to mint
     */
    function depositCollateralAndMintMATE(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountMATEToMint
    ) external {
        depositCollaborateral(tokenCollateralAddress, amountCollateral);
        mintMATE(amountMATEToMint);
    }

    /**
     * Burns MATE and redeems underlying collateral in one transaction
     * @param tokenCollateralAddress The address of the token to be redeemed as collateral
     * @param amountCollateral The amount of the token to be redeemed as collateral
     * @param amountMATEToBurn The amount of MATE tokens to burn
     * @dev redeemCollateral already checks health factor
     */
    function redeemCollaborateralForMATE(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountMATEToBurn
    ) external {
        burnMATE(amountMATEToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function liquidate() external {}

    // PUBLIC FUNCTIONS

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert MATEEngine__TranferFailed();
        }

        // It is more gas efficient to do this after the transfer
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnMATE(uint256 amount) public moreThanZero(amount) {
        s_MATEMinted[msg.sender] -= amount;
        bool success = i_MATE.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert MATEEngine__TranferFailed();
        }

        i_MATE.burn(amount);

        // This might not be needed
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of the token to be deposited as collateral
     */
    function depositCollaborateral(address tokenCollateralAddress, uint256 amountCollateral)
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
     * @param amountMATEToMint The amount of MATE to mint
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
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalMATEMinted, uint256 collateralValueInUSD)
    {
        totalMATEMinted = s_MATEMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
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
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // Examples:
        // $100 ETH collateral and $75 MATE minted
        // 100 * 50 / 100 = (50 * 100) / 75 = 66.66 < 100? - so it can be liquidated

        // $100 ETH collateral and $50 MATE minted
        // 100 * 50 / 100 = (50 * 100) / 50 = 100 < 100? - so it cannot be liquidated
        return (collateralAdjustedForThreshold * PRECISION) / totalMATEMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert MATEEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    // PUBLIC & EXTERNAL VIEW FUNCTIONS

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValue) {
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

    function getHealthFactor() external view {}
}
