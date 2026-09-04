// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LearningVault
 * @notice A small Ether vault intended to demonstrate common Solidity patterns.
 * @dev This is an educational example. Have production contracts independently
 *      reviewed and thoroughly tested before using them with real assets.
 */
contract LearningVault {
    // -------------------------------------------------------------------------
    // State variables
    // -------------------------------------------------------------------------

    /// @notice Account allowed to perform administrative actions.
    address public owner;

    /// @notice Stops deposits, withdrawals, and internal transfers when true.
    bool public paused;

    /// @notice Sum of all user balances tracked by this contract.
    uint256 public totalTrackedBalance;

    /// @dev Each user's claim on Ether held by this contract.
    mapping(address => uint256) private balances;

    /// @dev A minimal reentrancy lock used by withdraw().
    bool private withdrawalLocked;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event ValueTransferred(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event PauseChanged(bool isPaused);
    event SurplusWithdrawn(address indexed recipient, uint256 amount);

    // -------------------------------------------------------------------------
    // Custom errors (cheaper than long revert strings)
    // -------------------------------------------------------------------------

    error NotOwner();
    error ContractPaused();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 available, uint256 requested);
    error EtherTransferFailed();
    error ReentrantCall();
    error InsufficientSurplus(uint256 available, uint256 requested);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier nonReentrant() {
        if (withdrawalLocked) revert ReentrantCall();
        withdrawalLocked = true;
        _;
        withdrawalLocked = false;
    }

    // -------------------------------------------------------------------------
    // Constructor and Ether receipt
    // -------------------------------------------------------------------------

    /**
     * @notice Sets the deploying account as the first owner.
     */
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @notice Treats Ether sent directly to the contract as a deposit.
     */
    receive() external payable {
        _deposit(msg.sender, msg.value);
    }

    // -------------------------------------------------------------------------
    // User actions
    // -------------------------------------------------------------------------

    /**
     * @notice Deposits Ether and credits it to the caller's tracked balance.
     */
    function deposit() external payable whenNotPaused {
        _deposit(msg.sender, msg.value);
    }

    /**
     * @notice Withdraws part of the caller's tracked balance.
     * @dev Uses checks-effects-interactions: validation first, state changes
     *      second, and the external Ether transfer last.
     * @param amount Amount of wei to withdraw.
     */
    function withdraw(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 available = balances[msg.sender];
        if (amount > available) {
            revert InsufficientBalance(available, amount);
        }

        balances[msg.sender] = available - amount;
        totalTrackedBalance -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert EtherTransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Moves tracked value to another user without sending Ether out.
     * @param recipient Account that will receive the balance credit.
     * @param amount Amount of wei-denominated credit to move.
     */
    function transferValue(
        address recipient,
        uint256 amount
    ) external whenNotPaused {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 available = balances[msg.sender];
        if (amount > available) {
            revert InsufficientBalance(available, amount);
        }

        balances[msg.sender] = available - amount;
        balances[recipient] += amount;

        // totalTrackedBalance is unchanged because value stays in the vault.
        emit ValueTransferred(msg.sender, recipient, amount);
    }

    // -------------------------------------------------------------------------
    // Read-only getters
    // -------------------------------------------------------------------------

    /** @notice Returns the tracked balance belonging to an account. */
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /** @notice Returns the actual Ether balance held by this contract. */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Returns Ether not assigned to users.
     * @dev A positive surplus can arise if Ether is forcibly sent to the
     *      contract without calling deposit() or receive().
     */
    function getSurplus() public view returns (uint256) {
        return address(this).balance - totalTrackedBalance;
    }

    // -------------------------------------------------------------------------
    // Owner/admin actions
    // -------------------------------------------------------------------------

    /** @notice Pauses or unpauses normal user actions. */
    function setPaused(bool newPausedState) external onlyOwner {
        paused = newPausedState;
        emit PauseChanged(newPausedState);
    }

    /** @notice Transfers administrative control to a nonzero address. */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /**
     * @notice Withdraws only untracked surplus Ether, never user deposits.
     * @param recipient Address that receives the surplus.
     * @param amount Amount of surplus wei to withdraw.
     */
    function withdrawSurplus(
        address payable recipient,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 available = getSurplus();
        if (amount > available) {
            revert InsufficientSurplus(available, amount);
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert EtherTransferFailed();

        emit SurplusWithdrawn(recipient, amount);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _deposit(address account, uint256 amount) internal {
        if (paused) revert ContractPaused();
        if (amount == 0) revert ZeroAmount();

        balances[account] += amount;
        totalTrackedBalance += amount;
        emit Deposited(account, amount);
    }
}
