// SPDX-License-Identifier: MIT

// This is the V1 of the NFT shares contract.
// The NFT shares contract allow you do split an NFT into multiple ERC20 shares
// After the initial offering has ended the admin can take out the proceeds and remaining shares
// After the initial offering any one can create a buy order for one of the shares
// If you onw one of the shares you can sell it to one of the buyers
// If you own all shares you can redeem the NFT token


pragma solidity ^0.7.3;

import './DefihubConstants.sol';

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/math/Math.sol';

contract NftSharesV1 is ERC20 {
    // Using statements
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    using Address for address;

    /*********************************
        Contract State variables 
    *********************************/

    // The admin / deployer of the inital share offering 
    address public admin;

    // The initial share price and the total amount of shares
    uint public initialSharePrice;
    uint public totalAmountOfNftShares;
    
    // The NFT and share buying token data
    uint public nftId;
    IERC721 public nft;
    IERC20 public tokenToBuyWIth;

    // Boolean that changes when the NFT is redeemed
    bool nftIsRedeemed = false;
    bool adminHasRedeemedProfits = false;

    // Initial share offering duration parameters
    uint public intialShareOfferingDurationInDays;
    uint public endOfInitalShareOffering = 0;
    uint public initialShareOfferingStartTime = 0;

    // Struct of a buy oder to buy a share after the ISO has concluded 
    struct BuyOrder {
        uint amountToBuy;
        uint pricePerShare;
    }

    /***********************
            Modifiers 
    ***********************/

    // The created buy orders
    mapping(address => BuyOrder) public buyOrders;

    // Only admin modifer, guards function so only the admin can call them
    modifier onlyAdmin() {
        require(msg.sender == admin, 'Only the admin is allowed to do this!');
        _;
    }

    modifier isoNotEnded() {
        require(block.timestamp < endOfInitalShareOffering, 'Nft initial share offering has ended.');
        _;
    }

    modifier isoHasEnded() {
        require(block.timestamp > endOfInitalShareOffering, 'Nft initial share offering has ended.');
        _;
    }

    modifier onlyIfNftNotRedeemed() {
        require(nftIsRedeemed == false, 'The NFT is already redeemed!');
        _;
    }

    // Constructor for the contract and the ERC20 created for the shared
    constructor(
        string memory _shareName, 
        string memory _shareSymbol, 
        uint _nftId,
        address _nftTokenAddress, 
        address _tokenToBuyWith,
        uint _initialSharePrice,
        uint _totalAmountOfNftShares,
        uint _durationInDays,
        address _admin
    ) ERC20(_shareName, _shareSymbol) {
        // Set the NFT data and transfer it to the contract
        nftId = _nftId;
        nft = IERC721(_nftTokenAddress);
        nft.transferFrom(msg.sender, address(this), nftId);

        // Set the token to buy the shares with
        tokenToBuyWIth = IERC20(_tokenToBuyWith);

        // Set the inital share offering data
        initialSharePrice = _initialSharePrice;
        totalAmountOfNftShares = _totalAmountOfNftShares;
        intialShareOfferingDurationInDays = _durationInDays;
        uint durationToAdd = _durationInDays.mul(DefihubConstants.DAY_MULTIPLIER);
        endOfInitalShareOffering = block.timestamp.add(durationToAdd);
        initialShareOfferingStartTime = block.timestamp;

        // Set the admin of the contract
        admin = _admin;

    }

    /***************************
        external view returns 
    ****************************/

    function sharesLeftInIso() external view returns (uint) {
        return totalAmountOfNftShares - totalSupply();
    }

    function timeLeftInIso() external view returns (uint) {
        return block.timestamp.sub(initialShareOfferingStartTime.add(intialShareOfferingDurationInDays.mul(86400)));
    }

    /***************************
              Fucntions
    ****************************/

    // Buy a share of the NFT in the initial share offering
    function buyNftShare(uint amountOfSharesToBuy) external isoNotEnded {
        require(initialShareOfferingStartTime > 0, 'Nft initial share offering has not started yet.');
        require(totalSupply() + amountOfSharesToBuy <= totalAmountOfNftShares, 'There are not enough shares left.');

        uint totalPriceForShares = amountOfSharesToBuy * initialSharePrice;
        uint feeAmount = totalPriceForShares.mul(DefihubConstants.NFT_SHARES_FEE_BP).div(DefihubConstants.BASE_POINTS);

        tokenToBuyWIth.safeTransferFrom(msg.sender, DefihubConstants.FEE_ADDRESS, feeAmount);
        tokenToBuyWIth.safeTransferFrom(msg.sender, admin, totalPriceForShares);
        _mint(msg.sender, amountOfSharesToBuy);
        emit boughtSharesFromIso(msg.sender, amountOfSharesToBuy, totalPriceForShares);
    }

    // Withdraw any ramaining shares after the initial share offering has ended
    function withdrawRemainingSharesAndProfits() external onlyAdmin isoHasEnded {
        require(adminHasRedeemedProfits == false, 'You can only redeem the profits and left overs once.');

        uint unsoldRftShares = totalAmountOfNftShares.sub(totalSupply());

        if (unsoldRftShares > 0 && totalSupply() > 0) {
            _mint(admin, unsoldRftShares);
        }

        // If no shares are sold, send the NFT back as well
        if (totalSupply() == 0) {
            nft.transferFrom(address(this), admin, nftId);
            nftIsRedeemed = true;
        }

        adminHasRedeemedProfits = true;
        emit succesfullyWithdrawn(true);
    }

    // increase the duration of the intial offering
    function increaseIsoDuration(uint extraDays) external onlyAdmin isoNotEnded {
        uint timeToAdd = extraDays.mul(DefihubConstants.DAY_MULTIPLIER);
        intialShareOfferingDurationInDays = intialShareOfferingDurationInDays.add(extraDays);
        endOfInitalShareOffering.add(timeToAdd);
        emit IsoDurationIncreaed(extraDays);
    }

    // Create a buy order for NFT shares after the initial offering has ended
    function placeBuyOrderForSoldShares(uint amountWillingToBuy, uint priceOfferedPerShare) external onlyIfNftNotRedeemed isoHasEnded {
        require(amountWillingToBuy > 0, 'You need to place an order for more then 0 shares.');
        require(priceOfferedPerShare > 0, 'You need to place an order for more then 0 shares.');
        require(totalSupply() >= amountWillingToBuy, 'There are not enough shares out there to buy.');

        uint totalOrderAmount = amountWillingToBuy * priceOfferedPerShare;
        require(tokenToBuyWIth.balanceOf(msg.sender) >= totalOrderAmount, 'You have not enough tokens to place the buy order.');

        tokenToBuyWIth.safeTransferFrom(msg.sender, address(this), totalOrderAmount);
        BuyOrder memory createdOrder = BuyOrder({ amountToBuy: amountWillingToBuy, pricePerShare: priceOfferedPerShare });
        buyOrders[msg.sender] = createdOrder;
        emit OrderPlaced(msg.sender, totalOrderAmount, amountWillingToBuy);
    }

    // Cancel the buy order you placed
    function cancelOrder() external isoHasEnded {
        require(buyOrders[msg.sender].amountToBuy > 0, 'You have no open orders to cancel');
        uint amountToReceiveBackFromContract = buyOrders[msg.sender].amountToBuy * buyOrders[msg.sender].pricePerShare;
        tokenToBuyWIth.safeTransfer(msg.sender, amountToReceiveBackFromContract);
        buyOrders[msg.sender].amountToBuy = 0;
        buyOrders[msg.sender].pricePerShare = 0;
        emit orderCanceled(msg.sender, amountToReceiveBackFromContract);
    }

    // Sell you NFT shares to one of the buy orders
    function sellNftShare(address buyOrder, uint amountOfSharesToSell) external isoHasEnded {
        require(balanceOf(msg.sender) >= amountOfSharesToSell, 'You dont have enough Nft shares to sell.');
        require(buyOrders[buyOrder].amountToBuy >= amountOfSharesToSell, 'This order does not want to buy enough shares.');
        
        uint totalAmountToReceive = amountOfSharesToSell * buyOrders[buyOrder].pricePerShare;
        uint feeAmount = totalAmountToReceive.mul(DefihubConstants.NFT_SHARES_FEE_BP).div(DefihubConstants.BASE_POINTS);
        uint amountForSeller = totalAmountToReceive.sub(feeAmount);

        transferFrom(msg.sender, buyOrder, amountOfSharesToSell);
        tokenToBuyWIth.safeTransfer(msg.sender, amountForSeller);
        tokenToBuyWIth.safeTransfer(DefihubConstants.FEE_ADDRESS, feeAmount);
        buyOrders[buyOrder].amountToBuy = buyOrders[buyOrder].amountToBuy.sub(amountOfSharesToSell);
        emit NftShareSold(totalAmountToReceive, amountOfSharesToSell);
    }

    // If you own all NFT shares you can redeem the underlying NFT
    function redeemNft() external isoHasEnded onlyIfNftNotRedeemed {
        require(balanceOf(msg.sender) == totalAmountOfNftShares, 'You need all NFT shares to redeem the underlying NFT.');
        
        // Transfer the shares back to the contract and the NFT to the msg.sender
        transferFrom(msg.sender, address(this), totalAmountOfNftShares);
        nft.transferFrom(address(this), msg.sender, nftId);
        nftIsRedeemed = true;
        emit NftRedeemed(true);
    }

    /*********************
            EVENTS 
    *********************/
    event NftRedeemed(bool success);
    event succesfullyWithdrawn(bool success);
    event IsoDurationIncreaed(uint durationAdded);
    event NftShareSold(uint totalAmountToReceive, uint amountSold);
    event orderCanceled(address indexed user, uint amountReceived);
    event OrderPlaced(address indexed user, uint amountInContract, uint amountToReceive);
    event boughtSharesFromIso(address indexed user, uint amountBought, uint amountPaid);
}