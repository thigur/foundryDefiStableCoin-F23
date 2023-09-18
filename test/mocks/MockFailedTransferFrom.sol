// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract MockFailedTransferFrom is ERC20Burnable, Ownable {

    error DSC_AmountMustBeMoreThanZero();
    error DSC_BurnAmountExceedsBalance();
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

    function transferFrom(address /*Sender*/, address /*Recipient*/, uint256 /*amount*/)
        public
        pure
        override
        returns (bool) {
            return false;
        }
   }