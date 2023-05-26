// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.17 <0.9.0;

import "./SafeERC20.sol";

/*
*   M U L T I  T O K E N  F A U C E T
*
*   **** Admin Functions ****
*
*   1. setNewAdmin
*   2. addTokenSupport
*   3. updateCoinDrainAmount
*   4. updateTokenDrainAmount
*
*   **** Public & External ****
*
*   1. donateNativeCoins
*   2. donateERC20
*   3. drainCoin
*   4. drainToken
*
*   **** Private Functions ****
*
*   1. _checkTimelock
*   2. _isApprovedEnough
*/
contract MultiTokenFaucet {
    using Address for address;
    using SafeERC20 for address;

    // ****************** Storage ******************

    // Contract admin
    address public admin;
    // Native currency name
    string nativeCoinName;
    // Fixed amount of coins to drain
    uint256 public coinsAmount;
    // Fixed amount of tokens to drain
    uint256 public tokenAmount;

    struct Token {
        address tokenAddress;
        uint8 decimals;
    }

    // Token name => Token {contract address, decimals}
    mapping(string => Token) public tokens;
    // Token address => amount available
    mapping(address => uint256) public available;
    // User address => locked time
    mapping(address => uint256) public locker;

    // ****************** Errors ******************
    error InsufficientApproval(uint256 required, uint256 approved);
    error AlreadyDrainedToday();

    // ****************** Events ******************
    event Log(address user, string message, uint256 amount);

    // ****************** Modifiers ******************
    modifier onlyAdmin() {
        require(msg.sender == admin, "Role restricted call.");
        _;
    }

    constructor(string memory _nativeCoinName) payable {
        // Set the admin
        admin = msg.sender;
        // Set the native coin
        nativeCoinName = _nativeCoinName;
        tokens[nativeCoinName].tokenAddress = address(this);
        tokens[nativeCoinName].decimals = 18;
        available[address(this)] = msg.value;
        // Set the transfer amounts
        coinsAmount = 100_000_000 gwei; // 0.1 ETH
        tokenAmount = 100;
    }

    // ****************** ADMIN ******************

    function setNewAdmin(address _newAdmin) external onlyAdmin {
        require(
            _newAdmin != address(0),
            "Address zero cannot admin this contract"
        );
        require(_newAdmin != admin, "This address is already the admin");
        admin = _newAdmin;
        //       Old admin.      message.          New Admin
        emit Log(msg.sender, "Admin updated", uint256(uint160(_newAdmin)));
    }

    function addTokenSupport(
        string memory _tokenName,
        address _tokenAddress,
        uint8 _decimals
    ) external onlyAdmin {
        // Checks
        require(_tokenAddress.isContract(), "The address is not a contract");
        require(
            tokens[_tokenName].tokenAddress == address(0),
            "This tokens is already mapped."
        );
        require(
            0 <= _decimals && _decimals <= 18,
            "Token decimals must lie between 0 & 18"
        );

        // Update storage
        tokens[_tokenName].tokenAddress = _tokenAddress;
        tokens[_tokenName].decimals = _decimals;

        emit Log(
            msg.sender,
            "Token support added",
            uint256(uint160(_tokenAddress))
        );
    }

    function updateCoinDrainAmount(uint256 _newAmount) external onlyAdmin {
        coinsAmount = _newAmount;
        emit Log(msg.sender, "Coin drain amount updated", _newAmount);
    }

    function updateTokenDrainAmount(uint256 _newAmount) external onlyAdmin {
        tokenAmount = _newAmount;
        emit Log(msg.sender, "Token drain amount updated", _newAmount);
    }

    // ****************** PUBLIC & EXTERNAL ******************

    // FUNDING THE FAUCET

    /*
     * Send native coins to the contract
     */
    function donateNativeCoins() public payable {
        // Checks
        require(msg.value > 0, "No native coins sent");

        // STATE UPDATE

        // Left coins update
        available[address(this)] = msg.value;

        emit Log(msg.sender, "Donated native coin", msg.value);
    }

    /*
     * Send native ERC20 tokens to the contract
     */
    function donateERC20(string memory _tokenName, uint256 _amount)
        public
        payable
    {
        // Get the ERC20 token contract address
        address nativeToken = tokens[_tokenName].tokenAddress;
        uint256 amount = _amount * 10 ** tokens[_tokenName].decimals;

        // Checks
        require(nativeToken != address(0), "Token contract address unknown.");
        require(amount >= 1, "Minimum amount is 1 token");
        // Check the user has approved at least the amount
        _isApprovedEnough(nativeToken, amount);

        // Safely transfer
        SafeERC20.safeTransferFrom(
            IERC20(nativeToken),
            msg.sender,
            address(this),
            amount
        );

        // STATE UPDATE

        // Left tokens update
        available[tokens[_tokenName].tokenAddress] = amount;

        emit Log(msg.sender, "Donated native token", amount);
    }

    // GETTING COINS / TOKENS

    /*
     * Send native coins to the caller
     */
    function drainCoin() external {
        // Checks
        _checkTimelock();
        require(
            available[address(this)] >= coinsAmount,
            "No more native coins left"
        );

        // Transfer
        address payable receiver = payable(msg.sender);
        receiver.transfer(coinsAmount);

        // STATE UPDATE

        // Left coins update
        available[address(this)] -= coinsAmount;

        // Reset the time lock
        locker[msg.sender] = block.timestamp;

        emit Log(msg.sender, "Recieved native coin", coinsAmount);
    }

    /*
     * Send native ERC20 tokens to the caller
     */
    function drainToken(string memory _tokenName) external {
        // Get the ERC20 token contract address
        address nativeToken = tokens[_tokenName].tokenAddress;
        // Convert to tokens with decimals
        uint256 amount = tokenAmount * 10 ** tokens[_tokenName].decimals;

        // Checks
        _checkTimelock();
        require(nativeToken != address(0), "Unsupported token");
        require(available[nativeToken] >= amount, "No such tokens left");

        // Transfer
        SafeERC20.safeTransferFrom(
            IERC20(nativeToken),
            address(this),
            msg.sender,
            amount
        );

        // STATE UPDATE

        // Left tokens update
        available[nativeToken] -= amount;

        // Reset the time lock
        locker[msg.sender] = block.timestamp;

        emit Log(msg.sender, "Recieved native token", amount);
    }

    // ****************** PRIVATE FUNCTIONS ******************

    /*
     *   Reverts if still time locked
     */
    function _checkTimelock() private view {
        uint256 timeLock = locker[msg.sender];
        uint256 plusOneDay = timeLock + 1 days;
        // If timeLock == 0 => first timer
        // If timeLock > 0 => check time elapsed
        if (timeLock > uint256(0) && plusOneDay < block.timestamp) {
            revert AlreadyDrainedToday();
        }
    }

    /*
     *   @dev - Verifies that enough tokens are approved for transfer
     *
     *   @param `token` - the address of the local token contract
     *   @param `amount` - the required amount for the transfer
     */
    function _isApprovedEnough(address token, uint256 amount) private view {
        uint256 approved = IERC20(token).allowance(msg.sender, address(this));
        if (approved < amount) {
            revert InsufficientApproval({required: amount, approved: approved});
        }
    }
}
