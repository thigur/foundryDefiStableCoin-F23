/**
 * @title Decentralized Stablecoin
 * @author thigur
 * @notice From Foundry Defi|Stablecoin Lesson 12 by Patric Collins 
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {StdCheats} from "forge-std/StdCheats.sol";
import {Test, console} from "../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {MockMoreDebtDSC} from "./mocks/MockMoreDebtDSC.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "./mocks/MockFailedMintDSC.sol";
import {MockFailedTransfer} from "./mocks/MockFailedTransfer.sol";
import {MockFailedTransferFrom} from "./mocks/MockFailedTransferFrom.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";


contract TestDSCEngine is Test {

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPricFeed;
    address btcUsdPricFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant ZERO_ETH = 0 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant AMOUNT_TO_BURN = AMOUNT_TO_MINT/2;  //Burn half the amount minted
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant EXPECTED_HEALTH_FACTOR = 100 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;


    // if redeemFrom != redeemedTo, then it was liquidated
    event CollateralRedeemed(
        address indexed redeemFrom, 
        address indexed redeemTo, 
        address indexed token,
        uint256 amount
    );

    //Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPricFeed, btcUsdPricFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    /**
     * Make sure we are reverting correctly when the lengths are not the same
     * test this: revert BSDEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
     */
    function testRevertIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPricFeed);
        priceFeedAddresses.push(btcUsdPricFeed);

        vm.expectRevert(DSCEngine.BSDEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////
    // Price Tests //
    /////////////////
    /**
     * TODO: Update this test to use the actual price of the price feed
     * TODO: not to use this hardcoded 30000e18 value
     */
    function testGetUSDValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = dscEngine.getUSDValue(weth, ethAmount);
        assertEq(expectedUSD, actualUSD);
    }

    function testGetTokenAmountFromUSD() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actuWeth = dscEngine.getTokenAmountFromUSD((weth), usdAmount);
        assertEq(expectedWeth, actuWeth);
    }
        
    //////////////////////////////
    // Deposit Collateral Tests //
    //////////////////////////////

    function testRevertIfTransferFromFails() public {
        //Arrange - setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPricFeed];
        
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );

        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        //Arrange - user
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        //Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    function testReversIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    /**
     * Test depositCollateral() function
     */
    function testRevertsWithUnapporvedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAlloweToken.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, ZERO_ETH);
        
    }
    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDSscMinted, uint256 collateralValueInUsd) = 
            dscEngine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expetedDepositedAmount = dscEngine.getTokenAmountFromUSD(weth, collateralValueInUsd);
        assertEq(totalDSscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expetedDepositedAmount);
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }
    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPricFeed).latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * 
            dscEngine.getADDITIONAL_FEED_PRECISION())) / dscEngine.getPRECISION();
        vm.startPrank(USER);
        ERC20Mock(weth).approve((address(dscEngine)), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            amountToMint, 
            dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(
                DSCEngine.DSCEngine__BrokenHealthFactor.selector, 
                expectedHealthFactor));
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint);
        
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    ///////////////////
    // mintDsc Tests //
    ///////////////////

    /**
     * This test needs it's own custom setup
     * Test depositCollateralAndMintDSC() function
     */
    function testRevertsIfMintFails() public {
        //Arrange - Setup
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPricFeed];
        address owner = msg.sender;

        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDscEngine));
        //Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve((address(mockDscEngine)), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth,AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDSC(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPricFeed).latestRoundData();
        uint256 amountToMint = AMOUNT_COLLATERAL * 
            (uint256(price) * 
            dscEngine.getADDITIONAL_FEED_PRECISION()) / 
            dscEngine.getPRECISION();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor = 
            dscEngine.calculateHealthFactor(
                amountToMint,
                dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL)
        );
        vm.expectRevert(abi.encodeWithSelector(
            DSCEngine.DSCEngine__BrokenHealthFactor.selector, 
            expectedHealthFactor)
        );
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();      
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        dscEngine.mintDSC(AMOUNT_TO_MINT);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);   
    }

    ///////////////////
    // burnDsc Tests //
    ///////////////////
    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve((address(dscEngine)), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDSC(0);
        vm.stopPrank();
    }

    /**
     * Not sure what is being tested here!!!
     * Todo Seems to pass for any value.
     */
    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDSC(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        uint256 userBalance = dsc.balanceOf(USER);

        dscEngine.burnDSC(AMOUNT_TO_BURN);
        vm.stopPrank();

        userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_BURN);
    }

    ////////////////////////////
    // redeemCollateral Tests //
    ////////////////////////////
    //This test needs it's own setup
    function testRevertsIfTransferFails() public {
        //Arrange -setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPricFeed];
        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.mint(USER, AMOUNT_COLLATERAL);
        
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscEngine));

        //Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        //Act /Assert
        mockDscEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();    
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateralForDSC(weth, 0, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////
    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assertEq(healthFactor, EXPECTED_HEALTH_FACTOR);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8;  //1 ETH = $18
        //Remember we need $150 at all times for $100 worth of debt

        MockV3Aggregator(ethUsdPricFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        //$180 collateral / 200 debt = 0.9
        console.log("userHealthFactor: " , userHealthFactor);
        assert(userHealthFactor == 0.9 ether);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////
    function testMustImproveHealthFactorOnLiquidation() public {
        //Arrange - setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPricFeed);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPricFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDscEngine));
        //Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        mockDscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        //Arrange - Liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);
        
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockDscEngine), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockDscEngine.depositCollateralAndMintDSC(weth, collateralToCover, AMOUNT_TO_MINT);
        mockDsc.approve(address(mockDscEngine), debtToCover);
        //Act
        int256 ethUsdUpdatedPrice = 18e8;  //1 ETH = $18
        MockV3Aggregator(ethUsdPricFeed).updateAnswer(ethUsdUpdatedPrice);
        //Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockDscEngine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDSC(weth, collateralToCover, AMOUNT_TO_MINT);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        int256 ethUSDUpdatedPrice = 18e8;  //1 ETH = $18

        MockV3Aggregator(ethUsdPricFeed).updateAnswer(ethUSDUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDSC(weth, collateralToCover, AMOUNT_TO_MINT);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.liquidate(weth, USER, AMOUNT_TO_MINT);  //covering the whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = dscEngine.getTokenAmountFromUSD(weth, AMOUNT_TO_MINT) + 
            (dscEngine.getTokenAmountFromUSD(weth, AMOUNT_TO_MINT) / 
                dscEngine.getLIQUIDATION_BONUS());
        uint256 hardCodedExpected = 6111111111111111110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        //How much did the user lose
        uint256 amountLiquidated = dscEngine.getTokenAmountFromUSD(weth, AMOUNT_TO_MINT)
            + (dscEngine.getTokenAmountFromUSD(weth, AMOUNT_TO_MINT) / 
                dscEngine.getLIQUIDATION_BONUS());

        uint256 usdAmountLiquidated = dscEngine.getUSDValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = 
            dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = dscEngine.getAccountInformation(USER);        
        uint256 hardCodedExpectedValue = 70000000000000000020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);   
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dscEngine.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, AMOUNT_TO_MINT);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq( userDscMinted, 0);
    }

    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////
    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = dscEngine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPricFeed);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMIN_HEALTH_FACTOR() public {
        uint256 minHealthFactor = dscEngine.getMIN_HEALTH_FACTOR();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = dscEngine.getLIQUIDATION_THRESHOLD();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = dscEngine.getAccountInformation(USER);
        uint256 expectedCollateralValue = dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 collateralValue = dscEngine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = dscEngine.getUSDValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetSsc() public {
        address dscAddress = dscEngine.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testLiquidationPrecision() public {
        uint256 expectedLiquidationPre = 100;
        uint256 actualLiquidationPrecision = dscEngine.getLIQUIDATION_PRECISION();
        assertEq(actualLiquidationPrecision, expectedLiquidationPre);
    }
}