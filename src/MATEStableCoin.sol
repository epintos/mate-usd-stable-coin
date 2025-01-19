// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MATEStableCoin
 * @author Esteban Pintos
 * Collateral: Exogenous (wETH & wBTC)
 * Minting: Algorithmic
 * Relative Stability: Anchored to USD
 *
 * This is the contract meant to be governted by MSCEngine. This contract is just the ERC20 implementation of our
 * stablecoin system.
 */
contract MATEStableCoin is ERC20Burnable, Ownable {
    error MATEStableCoin__MustBeMoreThanZero();
    error MATEStableCoin__BurnAmountExceedsBalance();
    error MATEStableCoin__NotZeroAddress();

    constructor() ERC20("MATEStableCoin", "MATE") Ownable(msg.sender) { }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert MATEStableCoin__MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert MATEStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert MATEStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert MATEStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
