// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILock.sol";
import "./Errors.sol";

/// @title Base Lock Contract
/// @notice Abstract contract implementing core locking functionality
/// @dev Base contract for token vesting functionality
abstract contract BaseLock is ILock {
    /// @notice Owner of the lock contract
    address private owner;

    /// @notice Address of the locked token
    address private token;

    /// @notice Recipient of the locked tokens
    address private recipient;

    /// @notice Amount of tokens locked
    uint256 private amount;

    /// @notice Timestamp when total amount of tokens unlock
    uint256 private unlockTime;

    /// @notice Duration till cliff period ends
    uint256 private cliffPeriod;

    /// @notice Total number of vesting slots
    uint256 private slots;

    /// @notice Current vesting slot
    uint256 private currentSlot;

    /// @notice Amount of tokens released
    uint256 private releasedAmount;

    /// @notice Timestamp of last claim
    uint256 private lastClaimedTime;

    /// @notice Start time of the lock contract
    uint256 private startTime;

    /// @notice Enable cliff period
    bool private enableCliff;

    /// @notice Initialization status
    bool private initialized;

    /// @notice Emitted when a lock is initialized
    event LockInitialized(
        address indexed owner,
        address indexed token,
        uint256 amount,
        uint256 unlockTime,
        uint256 cliffPeriod,
        address indexed recipient,
        uint256 slots,
        bool enableCliff,
        uint256 startTime
    );

    /// @notice Emitted when state is updated
    event StateUpdated(uint256 indexed currentSlot, uint256 indexed releasedAmount, uint256 indexed lastClaimedTime);

    /// @notice Restricts function to contract owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Initializes the lock contract
    /// @dev Can only be called once
    function initialize(
        address _owner,
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _cliffPeriod,
        address _recepeint,
        uint256 _slots,
        uint256 _currentSlot,
        uint256 _releasedAmount,
        uint256 _lastClaimedTime,
        bool _enableCliff
    ) external virtual {
        require(!initialized, "Already initialized");

        if (_token == address(0)) revert InvalidToken();
        if (_owner == address(0)) revert InvalidOwner();
        if (_recepeint == address(0)) revert ZeroAddress();

        owner = _owner;
        token = _token;
        amount = _amount;
        unlockTime = _unlockTime;
        cliffPeriod = _cliffPeriod;
        recipient = _recepeint;
        slots = _slots;
        currentSlot = _currentSlot;
        releasedAmount = _releasedAmount;
        lastClaimedTime = _lastClaimedTime;
        enableCliff = _enableCliff;
        startTime = block.timestamp;
        initialized = true;

        emit LockInitialized(
            _owner, _token, _amount, _unlockTime, _cliffPeriod, _recepeint, _slots, _enableCliff, startTime
        );
    }

    /// @notice Returns the owner of the lock contract
    function getOwner() external view returns (address) {
        return owner;
    }

    /// @notice Returns the locked token address
    function getToken() external view returns (address) {
        return token;
    }

    /// @notice Returns the locked amount
    function getAmount() external view returns (uint256) {
        return amount;
    }

    /// @notice Returns the unlock time
    function getUnlockTime() external view returns (uint256) {
        return unlockTime;
    }

    /// @notice Returns the cliff period
    function getCliffPeriod() external view returns (uint256) {
        return cliffPeriod;
    }

    /// @notice Returns the recipient address
    function getRecipient() external view returns (address) {
        return recipient;
    }

    /// @notice Returns the number of vesting slots
    function getSlots() external view returns (uint256) {
        return slots;
    }

    /// @notice Returns the current vesting slot
    function getCurrentSlot() external view returns (uint256) {
        return currentSlot;
    }

    /// @notice Returns the released amount
    function getReleasedAmount() external view returns (uint256) {
        return releasedAmount;
    }

    /// @notice Returns the last claimed time
    function getLastClaimedTime() external view returns (uint256) {
        return lastClaimedTime;
    }

    /// @notice Returns the start time
    function getStartTime() external view returns (uint256) {
        return startTime;
    }

    /// @notice Returns the cliff status
    function getEnableCliff() external view returns (bool) {
        return enableCliff;
    }

    /// @notice Function to withdraw tokens
    function withdraw() external virtual;

    /// @notice Updates the lock state
    function _updateState(uint256 _currentSlot, uint256 _releasedAmount, uint256 _lastClaimedTime) internal {
        currentSlot = _currentSlot;
        releasedAmount = _releasedAmount;
        lastClaimedTime = _lastClaimedTime;
        emit StateUpdated(_currentSlot, _releasedAmount, _lastClaimedTime);
    }
}
