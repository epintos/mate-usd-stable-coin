// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {MateStableCoin} from "./MateStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMATEEngine {
    function depositCollateralAndMintMATE() external;

    function depositCollaborateral(address, uint256) external;

    function redeemCollaborateralForMATE() external;

    function redeemCollateral() external;

    function mintMATE(uint256) external;

    function burnMATE() external;

    function liquidate() external;

    function getHealthFactor() external view;
}

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
contract MATEEngine is IMATEEngine, ReentrancyGuard {
    // ERRORS
    error MATEEngine__NeedsMoreThanZero();
    error MATEEngine__TokenAddressesAndPriceFeedAdddressesMustBeSameLength();
    error MATEEngine__NotAllowedToken();
    error MATEEngine__TranferFailed();

    // STATE VARIABLES
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMATEMinted) private s_MATEMinted;

    MateStableCoin private immutable i_MATE;

    // EVENTS
    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );

    // MODIFIERS
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

    // FUNCTIONS
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address MATEAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert MATEEngine__TokenAddressesAndPriceFeedAdddressesMustBeSameLength();
        }

        // For example: ETH -> USD, BTC -> USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }

        i_MATE = MateStableCoin(MATEAddress);
    }

    // EXTERNAL FUNCTIONS
    function depositCollateralAndMintMATE() external {}

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of the token to be deposited as collateral
     */
    function depositCollaborateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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

    function redeemCollaborateralForMATE() external {}

    function redeemCollateral() external {}

    /**
     * @notice follows CEI pattern
     * @param amountMATEToMint The amount of MATE to mint
     * @notice they must have more collateral value than the mininum threshold
     */
    function mintMATE(uint256 amountMATEToMint) external moreThanZero(amountMATEToMint) nonReentrant {}

    function burnMATE() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
