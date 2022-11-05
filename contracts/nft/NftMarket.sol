// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../gov/InitializableOwner.sol";
import "../library/TransferHelper.sol";
import "../interfaces/IWETH.sol";


contract NFTMarket is Context, IERC721Receiver, ReentrancyGuard, InitializableOwner {

    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 constant BASE_RATE = 10000;

    struct SalesObject {
        uint256 id;
        uint256 tokenId;
        uint256 startTime;
        uint256 price;
        uint8 status;
        address payable seller;
        address payable buyer;
        IERC721 nft;
    }

    event eveNewSales(
        uint256 indexed id,
        uint256 indexed tokenId, 
        address seller, 
        address nft,
        address buyer, 
        address currency,
        uint256 startTime,
        uint256 price
    );

    event eveSales(
        uint256 indexed id, 
        uint256 indexed tokenId,
        address buyer, 
        address currency,
        uint256 price, 
        uint256 tipsFee,
        uint256 timestamp
    );

    event eveCancelSales(uint256 indexed id, uint256 tokenId);
    event eveNFTReceived(address operator, address from, uint256 tokenId, bytes data);
    event eveSupportCurrency(address currency, bool support);

    uint256 public _salesAmount = 0;

    SalesObject[] _salesObjects;
    
    address public WETH;

    mapping(address => bool) public _seller;
    mapping(address => bool) public _verifySeller;
    mapping(address => bool) public _supportNft;
    bool public _isStartUserSales;

    uint256 public _tipsFeeRate;
    address payable _tipsFeeWallet;

    mapping(uint256 => address) public _saleOnCurrency;
    mapping(address => bool) public _supportCurrency;
    
    constructor() public {}

    function initialize(address payable tipsFeeWallet, address weth) public {
        super._initialize();

        _tipsFeeRate = 500;
        _tipsFeeWallet = tipsFeeWallet;
        WETH = weth;

        addSupportCurrency(TransferHelper.getETH());
    }

    /**
     * check address
     */
    modifier validAddress( address addr ) {
        require(addr != address(0));
        _;
    }

    modifier checkindex(uint index) {
        require(index < _salesObjects.length, "overflow");
        _;
    }

    modifier checkTime(uint index) {
        require(index < _salesObjects.length, "overflow");
        SalesObject storage obj = _salesObjects[index];
        require(obj.startTime <= block.timestamp, "!open");
        _;
    }

    modifier mustNotSellingOut(uint index) {
        require(index < _salesObjects.length, "overflow");
        SalesObject storage obj = _salesObjects[index];
        require(obj.buyer == address(0) && obj.status == 0, "sry, selling out");
        _;
    }

    modifier onlySalesOwner(uint index) {
        require(index < _salesObjects.length, "overflow");
        SalesObject storage obj = _salesObjects[index];
        require(obj.seller == msg.sender || msg.sender == owner(), "author & owner");
        _;
    }

    function seize(IERC20 asset) external onlyOwner returns (uint256 balance) {
        balance = asset.balanceOf(address(this));
        asset.safeTransfer(owner(), balance);
    }

    function addSupportNft(address nft) public onlyOwner validAddress(nft) {
        _supportNft[nft] = true;
    }

    function removeSupportNft(address nft) public onlyOwner validAddress(nft) {
        _supportNft[nft] = false;
    }

    function addSeller(address seller) public onlyOwner validAddress(seller) {
        _seller[seller] = true;
    }

    function removeSeller(address seller) public onlyOwner validAddress(seller) {
        _seller[seller] = false;
    }
    
    function addSupportCurrency(address erc20) public onlyOwner {
        require(_supportCurrency[erc20] == false, "the currency have support");
        _supportCurrency[erc20] = true;
        emit eveSupportCurrency(erc20, true);
    }

    function removeSupportCurrency(address erc20) public onlyOwner {
        require(_supportCurrency[erc20], "the currency can not remove");
        _supportCurrency[erc20] = false;
        emit eveSupportCurrency(erc20, false);
    }

    function addVerifySeller(address seller) public onlyOwner validAddress(seller) {
        _verifySeller[seller] = true;
    }

    function removeVerifySeller(address seller) public onlyOwner validAddress(seller) {
        _verifySeller[seller] = false;
    }

    function setIsStartUserSales(bool isStartUserSales) public onlyOwner {
        _isStartUserSales = isStartUserSales;
    }

    function setTipsFeeWallet(address payable wallet) public onlyOwner {
        _tipsFeeWallet = wallet;
    }

    function getTipsFeeWallet() public view returns(address) {
        return address(_tipsFeeWallet);
    }

    function getSales(uint index) external view checkindex(index) returns(SalesObject memory) {
        return _salesObjects[index];
    }
    
    function getSalesCurrency(uint index) public view returns(address) {
        return _saleOnCurrency[index];
    }

    function setTipsFeeRate(uint256 rate) external onlyOwner {
        _tipsFeeRate = rate;
    }

    function isVerifySeller(uint index) public view checkindex(index) returns(bool) {
        SalesObject storage obj = _salesObjects[index];
        return _verifySeller[obj.seller];
    }

    function cancelSales(uint index) external checkindex(index) onlySalesOwner(index) mustNotSellingOut(index) nonReentrant {
        SalesObject storage obj = _salesObjects[index];
        obj.status = 2;
        obj.nft.safeTransferFrom(address(this), obj.seller, obj.tokenId);

        emit eveCancelSales(index, obj.tokenId);
    }

    function startSales(uint256 tokenId, uint256 price, uint256 startTime, address nft, address currency) external nonReentrant validAddress(nft) returns(uint)
    {
        require(tokenId != 0, "invalid token");
        require(startTime >= block.timestamp, "invalid start time");
        require(_isStartUserSales || _seller[msg.sender] == true || _supportNft[nft] == true, "cannot sales");
        require(_supportCurrency[currency] == true, "not support currency");

        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);

        _salesAmount++;
        SalesObject memory obj;

        obj.id = _salesAmount;
        obj.tokenId = tokenId;
        obj.seller = payable(msg.sender);
        obj.nft = IERC721(nft);
        obj.startTime = startTime;
        obj.price = price;
        
        _saleOnCurrency[obj.id] = currency;
        
        if (_salesObjects.length == 0) {
            SalesObject memory zeroObj;
            zeroObj.status = 2;
            _salesObjects.push(zeroObj);    
        }

        _salesObjects.push(obj);
        
        emit eveNewSales(obj.id, tokenId, msg.sender, nft, address(0x0), currency, startTime, price);
        return _salesAmount;
    }

    function buy(uint index) public nonReentrant mustNotSellingOut(index) checkTime(index) payable 
    {
        SalesObject storage obj = _salesObjects[index];
        require(obj.status == 0, "bad status");
        
        uint256 price = obj.price;
        obj.status = 1;

        uint256 tipsFee = price.mul(_tipsFeeRate).div(BASE_RATE);
        uint256 purchase = price.sub(tipsFee);

        address currencyAddr = _saleOnCurrency[obj.id];
        if (currencyAddr == address(0)) {
            currencyAddr = TransferHelper.getETH();
        }

        if (TransferHelper.isETH(currencyAddr)) {
            require (msg.value >= price, "your price is too low");
            uint256 returnBack = msg.value.sub(price);
            if(returnBack > 0) {
                payable(msg.sender).transfer(returnBack);
            }
            if(tipsFee > 0) {
                IWETH(WETH).deposit{value: tipsFee}();
                IWETH(WETH).transfer(_tipsFeeWallet, tipsFee);
            }
            obj.seller.transfer(purchase);
        } else {
            IERC20(currencyAddr).safeTransferFrom(msg.sender, _tipsFeeWallet, tipsFee);
            IERC20(currencyAddr).safeTransferFrom(msg.sender, obj.seller, purchase);
        }

        obj.nft.safeTransferFrom(address(this), msg.sender, obj.tokenId);
        obj.buyer = payable(msg.sender);

        // fire event
        emit eveSales(index, obj.tokenId, msg.sender, currencyAddr, price, tipsFee, block.timestamp);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data) public override returns (bytes4) {
        //only receive the _nft staff
        if(address(this) != operator) {
            //invalid from nft
            return 0;
        }

        //success
        emit eveNFTReceived(operator, from, tokenId, data);
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}