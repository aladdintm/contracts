// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

contract GovToken is ERC20Capped, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    address constant public BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint256 constant public MAX_SUPPLY = 100_000_000 * 1e18;

    EnumerableSet.AddressSet private _minters;
    address public teamAddress;
    uint256 public teamRate;
    
    constructor(address team_, uint256 teamRate_) public ERC20("Aladdin Governance Token", "ALG") ERC20Capped(MAX_SUPPLY) {
        teamAddress = team_;
        teamRate = teamRate_;
    }

    function burn(uint256 amount) public {
         _burn(_msgSender(), amount);
    }

    function _burn(address from, uint256 amount) internal override {
        super._transfer(from, BURN_ADDRESS, amount);
    }

    function mint(address _to, uint256 _amount) public onlyMinter returns (bool) {
        _mint(_to, _amount);
        if (teamRate > 0) {
            uint256 teamAmount = _amount.mul(teamRate).div(10000);
            _mint(teamAddress, teamAmount);
        }
        return true;
    }

    function setTeamRate(uint256 rate) public onlyOwner {
        require(rate < 2000, "bad rate");
        teamRate = rate;
    }

    function setTeamAddress(address team) public onlyOwner {
        require(team != address(0), "address is zero");
        teamAddress = team;
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