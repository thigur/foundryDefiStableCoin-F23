// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract MockFailedMintDSC is ERC20Burnable, Ownable {
    error DSC__AmountMustBeGreaterThanZero();
    error DSC__BurnAmuontExceedsBalance();
    error DSC__NotZeroAddress();
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DSC__AmountMustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert DSC__BurnAmuontExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) {
        if(_to == address(0)) {
            revert DSC__NotZeroAddress();
        }
        if(_amount <= 0) {
            revert DSC__AmountMustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return false;
    }

}