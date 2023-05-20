// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.17 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    // Errors
    error InsufficientApproval(uint256 required, uint256 approved);

    // Modifiers
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

    function donateERC20(string memory _tokenName, uint256 _amount) public payable {
        // Get the ERC20 token contract address
        address nativeToken = tokens[_tokenName];
        require(nativeToken != address(0), "Token contract address unknown.");
        require(_amount > 0, "Cannot accept 0 tokens");
        // Check the user has approved at least the amount
        _isApprovedEnough(nativeToken, _amount);
        // Safely transfer
        SafeERC20.safeTransferFrom(
            IERC20(nativeToken),
            msg.sender,
            address(this),
            amount
        )
    }

    function _isApprovedEnough(address token, uint256 amount) private view {
        uint256 approved = IERC20(token).allowance(
            msg.sender,
            address(this)
        );
        if (approved < amount) {
            revert InsufficientApproval({required: amount, approved: approved});
        }
    }
}
