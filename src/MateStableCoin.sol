// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MateStableCoin
 * @author Esteban Pintos
 * Collateral: Exogenous (wETH & wBTC)
 * Minting: Algorithmic
 * Relative Stability: Anchored to USD
 *
 * This is the contract meant to be governted by MSCEngine. This contract is just the ERC20 implementation of our
 * stablecoin system.
 */
contract MateStableCoin is ERC20Burnable, Ownable {
    error MateStableCoin__MustBeMoreThanZero();
    error MateStableCoin__BurnAmountExceedsBalance();
    error MateStableCoin__NotZeroAddress();

    constructor() ERC20("MateStableCoin", "MATE") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert MateStableCoin__MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert MateStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert MateStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert MateStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
