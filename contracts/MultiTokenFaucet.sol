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
    using SafeERC20 for IERC20;

    // ****************** Storage ******************

    // Contract admin
    address public admin;
    // Fixed amount of coins to drain
    uint256 public coinsAmount;
    // Fixed amount of tokens to drain
    uint256 public tokenAmount;
    // Native currency name
    string private nativeCoinName;

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

    /*
    * Sets a new contract admin
    */
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

    /*
     * Maps a token Name with its { address & decimals }
     *
     * @param `_tokenName` the token symbol
     * @param `_tokenAddress` address of the token contract
     * @param `_decimals` token decimals 0..18
     *
     * Reverts when:
     *
     * 1. `_tokenAddress` - is not a contract address
     * 2. `_tokenName` - is not supported by the faucet
     * 3. `_decimals` greater than 18
     */
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
        require(_decimals <= 18, "Token decimals must lie between 0 & 18");

        // Update storage
        tokens[_tokenName].tokenAddress = _tokenAddress;
        tokens[_tokenName].decimals = _decimals;

        emit Log(
            msg.sender,
            "Token support added",
            uint256(uint160(_tokenAddress))
        );
    }

    /*
    * Updates the amount of drained coins
    */
    function updateCoinDrainAmount(uint256 _newAmount) external onlyAdmin {
        coinsAmount = _newAmount;
        emit Log(msg.sender, "Coin drain amount updated", _newAmount);
    }

    /*
    * Updates the amount of drained tokens
    */
    function updateTokenDrainAmount(uint256 _newAmount) external onlyAdmin {
        tokenAmount = _newAmount;
        emit Log(msg.sender, "Token drain amount updated", _newAmount);
    }

    // ****************** PUBLIC & EXTERNAL ******************

    // FUNDING THE FAUCET

    /*
     * Sends native coins to the contract
     */
    function donateNativeCoins() public payable {
        // Checks
        require(msg.value > 0, "No native coins sent");

        // STATE UPDATE

        // Left coins update
        available[address(this)] = msg.value;

        emit Log(msg.sender, string.concat("Donated ", nativeCoinName), msg.value);
    }

    /*
     * Sends native ERC20 tokens to the contract
     */
    function donateERC20(string memory _tokenName, uint256 _amount)
        public
    {
        // Get the ERC20 token contract address
        address nativeToken = tokens[_tokenName].tokenAddress;
        uint256 amount = _amount * 10**tokens[_tokenName].decimals;

        // Checks
        require(nativeToken != address(0), "Token contract address unknown.");
        require(amount >= 1, "Minimum amount is 1 token");

        // Safely transfer
        SafeERC20.safeTransferFrom(
            IERC20(nativeToken),
            msg.sender,
            address(this),
            amount
        );

        // STATE UPDATE

        // Left tokens update
        available[tokens[_tokenName].tokenAddress] += amount;

        emit Log(msg.sender, string.concat("Donated ", _tokenName), amount);
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

        emit Log(msg.sender, string.concat("Received ", nativeCoinName), coinsAmount);
    }

    /*
     * Sends native ERC20 tokens to the caller
     */
    function drainToken(string memory _tokenName) external {
        // Get the ERC20 token contract address
        address nativeToken = tokens[_tokenName].tokenAddress;
        // Convert to tokens with decimals
        uint256 amount = tokenAmount * 10**tokens[_tokenName].decimals;

        // Check
        _checkTimelock();
        require(nativeToken != address(0), string.concat(_tokenName, "is not suported"));
        require(available[nativeToken] >= amount, "No such tokens left");

        // Transfer
        IERC20 currentToken = IERC20(nativeToken);
        currentToken.safeTransfer(
            msg.sender,
            amount
        );

        // STATE UPDATE

        // Left tokens update
        available[nativeToken] -= amount;

        // Reset the time lock
        locker[msg.sender] = block.timestamp;

        emit Log(msg.sender, string.concat("Received ", _tokenName), amount);
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
        if (timeLock > uint256(0) && plusOneDay > block.timestamp) {
            revert AlreadyDrainedToday();
        }
    }

}
