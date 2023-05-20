// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.17 <0.9.0;

contract MultiTokenFaucet {

    // Storage
    address public admin;
    // Native currency name
    string nativeCoinName;
    // Token name => contract address
    mapping(string => address) public tokens;
    // Token address => amount available
    mapping(address => uint256) public available;
    // User address => locked time
    mapping(address => uint256) public locker;

    modifier onlyAdmin {
        require(msg.sender == admin, "Role restricted call.");
        _;
    }

    constructor(string memory _nativeCoinName) payable {
        admin = msg.sender;
        nativeCoinName = _nativeCoinName;
        tokens[nativeCoinName] = address(this);
        available[address(this)] = msg.value;
    }

    function setNewAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Address zero cannot admin this contract");
        require(newAdmin != admin, "This address is already the admin");
        admin = newAdmin;
    }

    function donateNativeCoins() public payable {
        require(msg.value > 0, "No native coins sent");
        available[address(this)] = msg.value;
    }
}
