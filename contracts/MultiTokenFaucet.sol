// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.17 <0.9.0;

import "./SafeERC20.sol";

contract MultiTokenFaucet {

    using Address for address;
    using SafeERC20 for address;
    // ****************** Storage ******************

    // Contract admin
    address public admin;
    // Native currency name
    string nativeCoinName;

    uint256 coins = 100_000_000 gwei; // 0.1 ETH
    uint256 tokenAmount = 100 ether; // 100 tokens with 18 decimals
    // Token name => contract address
    mapping(string => address) public tokens;
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
        tokens[nativeCoinName] = address(this);
        available[address(this)] = msg.value;
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

    function addTokenSupport(string memory _tokenName, address _tokenAddress)
        external
        onlyAdmin
    {
        require(_tokenAddress.isContract(), "The address is not a contract");
        require(
            tokens[_tokenName] == address(0),
            "This tokens is already mapped."
        );
        tokens[_tokenName] = _tokenAddress;

        emit Log(msg.sender, "Token support added", uint256(uint160(_tokenAddress)));
    }

    function updateCoinDrainAmount(uint256 _newAmount) external onlyAdmin {
        coins = _newAmount;
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
        address nativeToken = tokens[_tokenName];

        // Checks
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

        // STATE UPDATE

        // Left tokens update
        available[tokens[_tokenName]] = _amount;

        emit Log(msg.sender, "Donated native token", _amount);
    }

    // GETTING COINS / TOKENS

    /*
     * Send native coins to the caller
     */
    function drainCoin() external {
        // Checks
        _checkTimelock();
        require(available[address(this)] >= coins, "No more native coins left");

        // Transfer
        address payable receiver = payable(msg.sender);
        receiver.transfer(coins);

        // STATE UPDATE

        // Left coins update
        available[address(this)] -= coins;

        // Reset the time lock
        locker[msg.sender] = block.timestamp;

        emit Log(msg.sender, "Recieved native coin", coins);
    }

    /*
     * Send native ERC20 tokens to the caller
     */
    function drainToken(string memory _tokenName) external {
        // Get the ERC20 token contract address
        address nativeToken = tokens[_tokenName];

        // Checks
        _checkTimelock();
        require(nativeToken != address(0), "Unsupported token");
        require(available[nativeToken] >= tokenAmount, "No such tokens left");

        // Transfer
        SafeERC20.safeTransferFrom(
            IERC20(nativeToken),
            address(this),
            msg.sender,
            tokenAmount
        );

        // STATE UPDATE

        // Left tokens update
        available[nativeToken] -= tokenAmount;

        // Reset the time lock
        locker[msg.sender] = block.timestamp;

        emit Log(msg.sender, "Recieved native token", tokenAmount);
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
