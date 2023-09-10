// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    //errors
    error DecentralizedStableCoin_AmountLessThanZero();
    error DecentralizedStableCoin_BrunAmountExceedsBalance();
    error DecentralizedStableCoin_NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") {}
    /**
     * In future versions of OpenZeppelin contracts package, Ownable must be 
     * declared with an address of the contract owner as a parameter. https://github.com/OpenZeppelin/openzeppelin-contracts/commit/13d5e0466a9855e9305119ed383e54fc913fdc60
     * @param _amount to be burned
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf((msg.sender));
        if(_amount <= 0) {
            revert DecentralizedStableCoin_AmountLessThanZero();
        }
        if(balance < _amount) {
            revert DecentralizedStableCoin_BrunAmountExceedsBalance();
        }
        //override the burn after doing all the stuff above
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if(_to == address(0)) {
            //dont let people mint to the zero address
            revert DecentralizedStableCoin_NotZeroAddress();
        }
        if(_amount <= 0) {
            revert DecentralizedStableCoin_AmountLessThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

}