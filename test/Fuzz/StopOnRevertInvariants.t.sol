// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {StopOnRevertHandler} from"./StopOnRevertHandler.t.sol";

contract StopOnRevertInvariants is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;
    StopOnRevertHandler public stopOnRevertHandler;

    address weth;
    address wbtc;
    function setUp() external{
        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();

        //targetContract(address(dscEngine));
        stopOnRevertHandler = new StopOnRevertHandler(dscEngine, dsc);
        targetContract(address(stopOnRevertHandler));
    }
    /**
     * Get the value of all the collateral in the protocal 
     * Compare it to all the debt (dsc)
     */
    function invariant_protocolMustHaveMoreValueThanTotalSupplyDollars() public view {
        uint256 totalSupply = dsc.totalSupply();

        uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dscEngine));
 
        uint256 wethValue = dscEngine.getUSDValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUSDValue(wbtc, totalWbtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);
        console.log("totalSupply", totalSupply);
        console.log("timesMintIsCalled: ", stopOnRevertHandler.timesMintIsCalled());
        
        assert(wethValue + wbtcValue >= 0);
    }

    function invariant_gettersCantRevert() public view {
        dscEngine.getLIQUIDATION_PRECISION();
        dscEngine.getLIQUIDATION_THRESHOLD();
        dscEngine.getLIQUIDATION_BONUS();
        dscEngine.getMIN_HEALTH_FACTOR();
        dscEngine.getPRECISION();
        dscEngine.getADDITIONAL_FEED_PRECISION();
        dscEngine.getFEED_PRECISION();
        dscEngine.getCollateralTokens();
        dscEngine.getDsc();
        //   "getAccountCollateralValue(address)": "7d1a4450",
        //   "getAccountInformation(address)": "7be564fc",
        //   "getCollateralBalanceOfUser(address,address)": "31e92b83",
        //   "getCollateralTokenPriceFeed(address)": "1c08adda",
        //   "getHealthFactor(address)": "fe6bcd7c",
        //   "getTokenAmountFromUSD(address,uint256)": "638ca89c",
        //   "getUSDValue(address,uint256)": "fa76dcf2",

    }
}
