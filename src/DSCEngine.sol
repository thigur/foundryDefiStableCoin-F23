/**
 * @title Decentralized Stablecoin
 * @author thigur
 * @notice From Foundry Defi|Stablecoin Lesson 12 by Patric Collins 
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title DSCEngine
 * @author thigur
 * @notice This contract is the core of the DSC system. Handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing collateral
 * This contract is VERY loosely based on the MaerDAO DSS (DAI) syste.
 * This DSC should always be "overcollateralized". The value should NOT be <+ to the backed value of all the DSC.
 */
    import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
    import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
    import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
    import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
    import {ERC20Burnable, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
    import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    
    ////////////////////
    ///    Errors   ///
    ////////////////////
    error DSCEngine__MintFailed();
    error DSCEngine__NotAlloweToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__BrokenHealthFactor(uint256);
    error BSDEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();

    ////////////////////
    //State Varialbles//
    ////////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;
    address[] private s_collateralTokens;

    mapping(address token => address priceFeed) private s_priceFeeds;  //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////
    //     Events    //
    ////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    ////////////////////
    ///   Modifiers  ///
    ////////////////////
    modifier moreThanZero(uint256 amount) {
        if(amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAlloweToken();
        }
        _;
    }
        
    ////////////////////
    ///   Functions  ///
    ////////////////////
    constructor(
        address[] memory tokenAddress, 
        address[] memory priceFeedAddresses, 
        address dscAddress
        ) {
             //if there are more tokens then there are price feeds, there is a problem
            if(tokenAddress.length != priceFeedAddresses.length) {
                revert BSDEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
            }
            // USD Price Feeds eg. ETH/USD, BTC/USD, MKR/USD, etc...
            for(uint256 i = 0; i < tokenAddress.length; i++) {
                s_priceFeeds[tokenAddress[i]] = priceFeedAddresses[i];
                s_collateralTokens.push(tokenAddress[i]);
            }
            i_dsc = DecentralizedStableCoin(dscAddress);
        }

    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral yourdepositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMinDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
        )   external 
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
        {
        //depositCollateral(tokenCollateralAddress, amountCollateral);
        //mintDSC(amountDscToMint);
        //revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI Check, effects, Interactions
     * @param tokenCollateralAddress: The address of the token to deposit as collateral
     * @param amountCollateral: Amount of collateral to deposit
     */
    function depositCollateral(
        //Checks
        address tokenCollateralAddress,
        uint256 amountCollateral ) external 
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant        //safe but gass intensive
    {
        //Effects
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;  //Updating the collateral
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        //Interactions
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }

    }
    
    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    /**
     * @notice follows CEI
     * @param amountDscToMint: Amount of decentralized stablecoin to mint
     * @notice One must have more collateral value than the min threshold
     */
    function mintDSC(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDscToMint;
        //if one has minted too much
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if(minted != true) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {} //how healthy people are

    ///////////////////////////////////////////////////
    ///   Private & Internal View & Pure Functions  ///
    ///////////////////////////////////////////////////


    function _getAccountInformatioin(address user) 
        private 
        view 
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD) {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * 
     * Returns how close to liquidation a user is.
     * If the user goes below 1, they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformatioin(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD)
        internal
        pure
        returns (uint256) {
            if(totalDSCMinted == 0) return type(uint256).max;
            uint256 collateralAdjustedForThreshold = 
                (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
            return (collateralAdjustedForThreshold *1e18) / totalDSCMinted;
        }

    /**
     * @notice Check health factor (do they have enough collateral?)
     * @notice Revert if they do not
     * @param user The person minting DSC
     */
    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BrokenHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////////////////////////
    // External & Public View & Pure Functions //
    /////////////////////////////////////////////
    /**
     * Loop through the collateral token, get the amount of DSC user has,
     * map it to the price, to caluclate the USD value
     */
    function getAccountCollateralValue(address user) 
        public 
        view 
        returns (uint256 totalCollateralValueInUSD) {
        for(uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    // //Todo  is this function really necessary????
    // function _getUSDValue(
    //     address token, 
    //     uint256 amount //in WEI
    //     ) external view returns (uint256) {
    //         return __getUSDValue();
    // }



    ////////////////////////
    //  Getter Functions  //
    ////////////////////////

    // functon getActiveConfigNetwork() public  returns() {
    //     return 
    // }
}