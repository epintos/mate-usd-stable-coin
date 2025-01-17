// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedMintMATE is ERC20Burnable, Ownable {
    error MATEStableCoin__MustBeMoreThanZero();
    error MATEStableCoin__BurnAmountExceedsBalance();
    error MATEStableCoin__NotZeroAddress();

    constructor() ERC20("MATEStableCoin", "MATE") Ownable(msg.sender) {}

    function mint(address, /*_to*/ uint256 /*_amount*/ ) external view onlyOwner returns (bool) {
        return false;
    }
}
