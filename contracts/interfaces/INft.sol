// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface INft is IERC721 {
    function mint(address to) external;
    function _nftId() external returns(uint256);
}