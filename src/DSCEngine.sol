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
 * @notice This contract is the core of the DSC system. Handles all the logic 
 * for mining and redeeming DSC, as well as depositing and withdrawing collateral
 * This contract is VERY loosely based on the MaerDAO DSS (DAI) syste.
 * This DSC should always be "overcollateralized". The value should NOT 
 * be <+ to the backed value of all the DSC.
 */
    import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
    import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
    import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
    import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
    import {ERC20Burnable, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
    import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
    import {OracleLib} from "../src/libraries/OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
    
    ////////////////////
    ///    Errors   ///
    ////////////////////
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__NotAlloweToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__BrokenHealthFactor(uint256);
    error BSDEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();

     ////////////////////
    ///    Types   ///
    ////////////////////
    using OracleLib for AggregatorV3Interface;

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
    event CollateralDeposited(
        address indexed user, 
        address indexed token, 
        uint256 indexed amount
    );

    event  CollateralRedeemed(
        address indexed redeemFrom, 
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

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
     * @param tokenCollateralAddress: The ERC20 token address of the collateral your depositing
     * @param amountCollateral: The amount of collateral to deposit
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint)   external 
            moreThanZero(amountCollateral)
            isAllowedToken(tokenCollateralAddress)
        {
            depositCollateral(tokenCollateralAddress, amountCollateral);
            mintDSC(amountDscToMint);
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
        uint256 amountCollateral ) public 
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant        //safe but gass intensive
    {
        //Effects
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;  //Updating the collateral
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        //Interactions
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }

    }

    /**
     * 
     * @param tokenCollateralAddress: The collateral address to redee
     * @param amountCollateral: Amount of collateral to redeem
     * @param amountDSCToBurn: Amount DSC to burn
     * @notice Burn DSC and Redeem Underlying Collateral in one transaction
     */
    function redeemCollateralForDSC(
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountDSCToBurn) external {
            burnDSC(amountDSCToBurn);
            redeemCollateral(tokenCollateralAddress, amountCollateral);
            //redeemCollateral above, already reverts if health factor is broken
        }

    /**
     * In order to redeem collateral:
     * Health factor must be over 1 AFTER collateral pulled
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) 
        public moreThanZero(amountCollateral)
        nonReentrant 
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountDscToMint: Amount of decentralized stablecoin to mint
     * @notice One must have more collateral value than the min threshold
     */
    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender] += amountDscToMint;
        //if one has minted too much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if(minted != true) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * Wen user is done with these tokens
     * @param amount to burn
     */
    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);  //May not be hit
    }

    /**
     * If someone is almost undercollateralized, contract will 
     * pay you to liquidate the undercollateralized user
     * Choose user to liquidate
     * Can partially liquidate user to healty status
     */
    function liquidate(address collateral, address user, uint256 debtToCover) 
        external 
        moreThanZero(debtToCover)
        nonReentrant {
            //Check healthfactor of the user is this user liquid-atable?
            uint256 startingUserHealthFactor = _healthFactor(user);
            if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
                revert DSCEngine__HealthFactorOk();
            }
            uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);

            //Calculate incentive/LIQUIDATION_BONUS
            uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
            uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
            _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

            // need to burn the DSC being liquidated
            _burnDSC(debtToCover, user, msg.sender);  //msg.sender is the liquidator

            //Make sure health factor is better
            uint256 endingUserHealthFactor = _healthFactor(user);
            if(endingUserHealthFactor <= startingUserHealthFactor) {
                revert DSCEngine__HealthFactorNotImproved();
            }

            //Call revert if liquidator's health factor worsens by liquidating the DSC
            _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////////////////////////////////
    ///   Private & Internal View & Pure Functions  ///
    ///////////////////////////////////////////////////

    /**
     * @dev Low-level internal function. Only call to check health factor.
     */
    function _burnDSC(uint256 amountUSDToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountUSDToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountUSDToBurn);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountUSDToBurn);


    }

    function _redeemCollateral (
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        address from, 
        address to) private {
            s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
            emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
            bool success = IERC20(tokenCollateralAddress).transfer((to), amountCollateral);
            if(!success) {
                revert DSCEngine__TransferFailed();
            }
    }
    
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
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BrokenHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////////////////////////
    // External, Public, View & Pure Functions //
    /////////////////////////////////////////////
    /**
     * Loop through the collateral token, get the amount of DSC user has,
     * map it to the price, to caluclate the USD value
     */

    function calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD) 
    external
    pure
    returns (uint256) {
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) 
        public 
        view 
        returns(uint256) {
        // Get price of ETH (tokem)
        // $/ETH ??, $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //(, int256 price,,,) = priceFeed.latestRoundData();
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * 
            ADDITIONAL_FEED_PRECISION));
    }
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

    function getUSDValue(
        address token, 
        uint256 amount) 
        public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //(, int256 price,,,) = priceFeed.latestRoundData();
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralBalanceOfUser(
        address USER,
        address token) external view returns (uint256) {
        return s_collateralDeposited[USER][token];
    }

    function getAccountInformation(address user) 
        external 
        view 
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD) {
            (totalDSCMinted, collateralValueInUSD)  = _getAccountInformatioin(user);
    }

    ////////////////////////
    //  Getter Functions  //
    ////////////////////////

    // functon getActiveConfigNetwork() public  returns() {
    //     return 
    // }

    function getLIQUIDATION_PRECISION() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }
    function getLIQUIDATION_THRESHOLD() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLIQUIDATION_BONUS() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMIN_HEALTH_FACTOR() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getPRECISION() external pure returns (uint256) {
        return PRECISION;
    }

    function getADDITIONAL_FEED_PRECISION() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getFEED_PRECISION() external pure returns (uint256) {
        return FEED_PRECISION;
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }
}