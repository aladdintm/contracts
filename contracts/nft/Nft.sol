// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "../library/SignatureChecker.sol";

contract NFT is AccessControl, ERC721, ReentrancyGuard, Initializable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SignatureChecker for EnumerableSet.AddressSet;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    event Mint(address indexed user, uint256 nftId);
    event LockNFT(address operator, uint256[] ids, uint256 timestamp);
    event UnlockNFT(address operator, uint256[] ids, uint256 timestamp);

    string private _baseURI;
    string private _name;
    string private _symbol;
    uint256 public _nftId;

    mapping(uint256 => bool) public lockedNfts;
    mapping(address=>EnumerableSet.UintSet) private userLockedNfts;
    EnumerableSet.AddressSet private _signers;
    mapping(uint256 => bool) public _usedNonce;

    constructor() public ERC721("", "") {}

    function initialize(string memory name_, string memory symbol_) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view override returns (string memory) { return _name; }
    function symbol() public view override returns (string memory) { return _symbol;}
    function setBaseURI(string memory uri) public onlyAdmin { _baseURI = uri; }
    function baseURI() public view override returns (string memory) { return _baseURI; }

    function mint(address to) public whenNotPaused onlyMinter {
        _nftId++;

        _mint(to, _nftId);
        emit Mint(to, _nftId);
    }

    function unlock(uint256[] memory ids) public onlyOperator {
        _unlock(ids);
    }

    function _unlock(uint256[] memory ids) internal {
        for (uint i = 0; i < ids.length; ++i) {
            lockedNfts[ids[i]] = false;
            userLockedNfts[_msgSender()].remove(ids[i]);
        }
        emit UnlockNFT(_msgSender(), ids, block.timestamp);
    }

    function unlockNft(uint256 id, uint128 nonce, bytes calldata signature) public {
        require(_usedNonce[nonce] == false, "nonce already used");

        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encode(address(this), _msgSender(), id, nonce))
        );

        _signers.requireValidSignature(message, signature);
        _usedNonce[nonce] = true;

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        _unlock(ids);
    }

    function lock(uint256[] memory ids) public {
        for (uint i = 0; i < ids.length; ++i) {
            require(!lockedNfts[ids[i]], "already locked");
            require(ownerOf(ids[i]) == _msgSender(), "not owner");
            lockedNfts[ids[i]] = true;
            userLockedNfts[_msgSender()].add(ids[i]);
        }
        emit LockNFT(_msgSender(), ids, block.timestamp);
    }

    function getUserLockedNfts(address user) public view returns(uint256[] memory ret) {
        EnumerableSet.UintSet storage ids = userLockedNfts[user];
        uint len = ids.length();
        if (len == 0) {
            return ret;
        }
        ret = new uint256[](len);
        for(uint i = 0; i < len; ++i) {
            ret[i] = ids.at(i);
        }
    }

    function hodlerNfts(address user) public view returns (uint256[] memory ids) {
        uint len = balanceOf(user);
        if (len == 0) return ids;
        ids = new uint256[](len);
        for (uint i = 0; i < len; ++i) {
            ids[i] = tokenOfOwnerByIndex(user, i);
        }
    }

    function _transfer(address from, address to, uint256 tokenId) internal virtual override {
        require(lockedNfts[tokenId] == false, "locked");
        super._transfer(from, to, tokenId);
    }

    function addSigner(address val) public onlyAdmin() {
        _signers.add(val);
    }

    function getSigners() public view returns (address[] memory ret) {
        uint len = _signers.length();
        ret = new address[](len);
        for (uint i = 0; i < len; ++i) {
            ret[i] = _signers.at(i);
        }
        return ret;
    }

    function addMinter(address val) public onlyAdmin() {
        grantRole(MINTER_ROLE, val);
    }

    function addOperator(address val) public onlyAdmin() {
        grantRole(OPERATOR_ROLE, val);
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "onlyAdmin");
        _;
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, _msgSender()), "minter only");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "operator only");
        _;
    }
}