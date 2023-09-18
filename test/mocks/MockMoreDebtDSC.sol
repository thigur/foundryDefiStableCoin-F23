// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MockV3Aggregator} from "./MockV3Aggregator.sol";

/**
 * @title DecentralizedStableCoin
 * @author thigur
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 * 
 * This is the contract ment to be owned by DSCEngine.
 * It is an ERC20 token that can be minted and burned by 
 * the DSCEngine smart contract
 */
contract MockMoreDebtDSC is ERC20Burnable, Ownable {

    error DSC_AmountMustBeMoreThanZero();
    error DSC_BurnAmountExceedsBalance();
    error DSC_NotZeroAddress();

    address mockAggregator;
    constructor(address _mockAggregator) 
        ERC20("DecentralizedStableCoin", "DSC") {
            mockAggregator = _mockAggregator;
        }
   function burn(uint256 _amount) public override onlyOwner {
        // We crash the price
        MockV3Aggregator(mockAggregator).updateAnswer(0);
        uint256 balance = balanceOf(msg.sender);
        if(_amount <= 0) {
            revert DSC_AmountMustBeMoreThanZero();
        }
        if(balance < _amount) {
            revert DSC_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
   }

    function mint(address _to, uint256 _amount) 
        external 
        onlyOwner 
        returns (bool) {
            if (_to == address(0)) {
                revert DSC_NotZeroAddress();
            }
            if (_amount <= 0) {
                revert DSC_AmountMustBeMoreThanZero();
            }
            _mint(_to, _amount);
            return true;
    }

   }