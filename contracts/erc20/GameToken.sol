// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

contract GameToken is ERC20, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    EnumerableSet.AddressSet private _minters;
    
    constructor() public ERC20("Aladdin Token", "ALD") {

    }

    function burn(uint256 amount) public {
         _burn(_msgSender(), amount);
    }

    function _burn(address from, uint256 amount) internal override {
        super._transfer(from, BURN_ADDRESS, amount);
    }

    function mint(address _to, uint256 _amount) public onlyMinter returns (bool) {
        _mint(_to, _amount);
        return true;
    }

    function addMinter(address minter) public onlyOwner returns (bool) {
        require(minter != address(0), "Token: minter is the zero address");
        return _minters.add(minter);
    }

    function delMinter(address minter) public onlyOwner returns (bool) {
        require(minter != address(0), "Token: minter is the zero address");
        return _minters.remove(minter);
    }

    function getMinterLength() public view returns (uint256) {
        return _minters.length();
    }

    function isMinter(address account) public view returns (bool) {
        return _minters.contains(account);
    }

    function getMinter(uint256 index) public view returns (address) {
        require(index <= getMinterLength() - 1, "Token: index out of bounds");
        return _minters.at(index);
    }

    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender), "caller is not the minter");
        _;
    }
}