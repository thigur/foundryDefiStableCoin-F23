// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract MockFailedTransfer is ERC20Burnable, Ownable {

    error DSC_AmountMustBeMoreThanZero();
    error DSC_BurnAmountExceedsBalance();
    /**
     * In future versions of OpenZeppelin contracts package, Ownable must be declared 
     * with an address of the contract owner as a parameter.
     * For example: constructor() ERC20("DecentralizedStableCoin", "DSC") 
     * Ownable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) {} 
    */
error DSC_NotZeroAddress();
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}
   function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if(_amount <= 0) {
            revert DSC_AmountMustBeMoreThanZero();
        }
        if(balance < _amount) {
            revert DSC_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
   }

    function mint(address account, uint256 amount) public {
            _mint(account, amount);
    }

    function transfer(address /*Sender*/, uint256 /*amount*/)
        public
        pure
        override
        returns (bool) {
            return false;
        }
   }