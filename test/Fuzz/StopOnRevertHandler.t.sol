// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console} from "../../lib/forge-std/src/Test.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
//Include Price feed updates in the handler
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract StopOnRevertHandler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    MockV3Aggregator public ethUsdPricefeed;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;

    // Ghost Variables
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public usersWithCollateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethUsdPricefeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed((address(weth))));
    }

    function mnintDsc(uint256 amount, uint256 addressSeed) public {
        if(usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed %
             usersWithCollateralDeposited.length];
        
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = 
            dscEngine.getAccountInformation(sender);

        int256 maxDscToMint = (int256(collateralValueInUSD) / 2) - int256(totalDSCMinted);
        if(maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if(amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        //problem with double pushes same address pushed twice
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(
            address(collateral), msg.sender);
        
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if(amountCollateral == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }
    //This Breaks our invariant test suite, it breaks the invariant!!!
    // function updateColateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPricefeed.updateAnswer(newPriceInt);
    // }
    function _getCollateralFromSeed(uint256 collateralSeed) public view returns (ERC20Mock) {
        console.log("");
        console.log("We are in _getCollateralFromSeed() function !!!!!!!!!!!!");
        console.log("");

        if(collateralSeed % 2 == 0){
            return weth;
        } else {
            return wbtc;
        }
    }
}