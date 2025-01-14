// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {MateStableCoin} from "./MateStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMSCEngine {
    function depositCollateralAndMintMsc() external;

    function depositCollaborateral(address, uint256) external;

    function redeemCollaborateralForMsc() external;

    function redeemCollateral() external;

    function mintMsc() external;

    function burnMsc() external;

    function liquidate() external;

    function getHealthFactor() external view;
}

/**
 * @title MSCEngine
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
 * Our MSC System should always be "overcollateralized". At no point, should the value of all
 * collaborateral be less than the dollar backed value of all MSC in circulation.
 *
 * @notice This contract is the core of the MSC System. It handles all the logic of mining and redeeming MSC, as well
 * as de depositing and withdrawing collateral.
 * @notice This contract is very lossely based on the MakerDAO DSS (DAI) system.
 */
contract MSCEngine is IMSCEngine, ReentrancyGuard {
    // ERRORS
    error MSCEngine__NeedsMoreThanZero();
    error MSCEngine__TokenAddressesAndPriceFeedAdddressesMustBeSameLength();
    error MSCEngine__NotAllowedToken();
    error MSCEngine__TranferFailed();

    // STATE VARIABLES
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    MateStableCoin private immutable i_msc;

    // EVENTS
    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );

    // MODIFIERS
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert MSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert MSCEngine__NotAllowedToken();
        }
        _;
    }

    // FUNCTIONS
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address mscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert MSCEngine__TokenAddressesAndPriceFeedAdddressesMustBeSameLength();
        }

        // For example: ETH -> USD, BTC -> USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }

        i_msc = MateStableCoin(mscAddress);
    }

    // EXTERNAL FUNCTIONS
    function depositCollateralAndMintMsc() external {}

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
            revert MSCEngine__TranferFailed();
        }
    }

    function redeemCollaborateralForMsc() external {}

    function redeemCollateral() external {}

    function mintMsc() external {}

    function burnMsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
