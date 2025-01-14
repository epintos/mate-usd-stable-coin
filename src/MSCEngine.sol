// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface MSCEngineInterface {
    function depositCollateralAndMintMsc() external;

    function depositCollaborateral() external;
    
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
contract MSCEngine is MSCEngineInterface {
    function depositCollateralAndMintMsc() external{}

    function depositCollaborateral() external{}
    
    function redeemCollaborateralForMsc() external{}

    function redeemCollateral() external{}

    function mintMsc() external {}
    
    function burnMsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
