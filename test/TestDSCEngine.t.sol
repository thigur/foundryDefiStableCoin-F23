/**
 * @title Decentralized Stablecoin
 * @author thigur
 * @notice From Foundry Defi|Stablecoin Lesson 12 by Patric Collins 
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol"; 
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract TestDSCEngine is Test {

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPricFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPricFeed, , weth, , ) = config.activeNetworkConfig();
    }

    /////////////////
    // Price Tests //
    /////////////////
    function testGetUSDValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = dsce.getUSDValue(weth, ethAmount);
        assertEq(expectedUSD, actualUSD);
    }

    //////////////////////////////
    // Deposit Collateral Tests //
    //////////////////////////////
    function testReversIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    }



}