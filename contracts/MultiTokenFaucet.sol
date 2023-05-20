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

    // ONLY ADMIN FUNCTIONS

    function setNewAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Address zero cannot admin this contract");
        require(newAdmin != admin, "This address is already the admin");
        admin = newAdmin;
    }

    function addTokenSupport(string memory tokenName, address tokenAddress) public onlyAdmin {
        require(_isContract(tokenAddress), "The address is not a contract");
        require(tokens[tokenName] == address(0), "This tokens is already mapped.");
        tokens[tokenName] = tokenAddress;
    }

    // PUBLIC & EXTERNAL FUNCTIONS

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
            _amount
        );
        available[_tokenName] = _amount;
    }

    // PRIVATE FUNCTIONS

    /*
     *   @dev - Verifies that enough tokens are approved for transfer
     *
     *   @param `token` - the address of the local token contract
     *   @param `amount` - the required amount for the transfer
     */
    function _isApprovedEnough(address token, uint256 amount) private view {
        uint256 approved = IERC20(token).allowance(
            msg.sender,
            address(this)
        );
        if (approved < amount) {
            revert InsufficientApproval({required: amount, approved: approved});
        }
    }

    /*
     *   @dev - Checks whether an address belongs to a contract
     *   @param `_address` - the checked address
     *   @returns `true` if the address is a contract | `false` otherwise
     */
    function _isContract(address _address) private view returns (bool) {
        return _address.code.length > 0;
    }
}
