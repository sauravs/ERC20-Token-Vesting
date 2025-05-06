// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./BaseLock.sol";
import "./locks/VestingLock.sol";
import "./interfaces/ILock.sol";
import "./Errors.sol";

/**
 * @title TokenLockFactory
 * @author web3tech.biz
 * @notice Factory contract for creating token vesting locks
 * @dev Uses minimal proxy pattern for gas-efficient deployments
 */
contract TokenVestingFactory is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Clones for address;

    /// @notice Address of the fee admin
    /// @dev Can update fee amounts and token
    address public feeAdmin = 0x80AB0Cb57106816b8eff9401418edB0Cb18ed5c7;

    /// @notice Address of the fee collector
    /// @dev Receives the lock creation fees
    address public feeCollector = 0x80AB0Cb57106816b8eff9401418edB0Cb18ed5c7;

    /// @notice Token used for lock creation fees
    /// @dev Can be any ERC20 token
    IERC20 public lockFeeToken = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); // USDC on polygon mainnet

    /// @notice Fee amount for creating a vesting lock
    /// @dev Can be updated by fee admin
    uint256 public lockFeeAmountVesting = 50 * 10 ** 6; //50 USDC

    /// @notice Implementation address for vesting lock
    /// @dev Used as template for cloning
    address public immutable vestingImpl;

    /// @notice Mapping of whitelisted tokens
    /// @dev No fee for whitelisted tokens

    mapping(address => bool) public whitelistedTokens;

    /// @notice Mapping from owner to their locks
    mapping(address => address[]) public userLocks;

    /// @notice Mapping from recipient to their locks
    mapping(address => address[]) public recipientLocks;

    /// @notice Array of all locks created
    address[] public allLocks;

    /// @notice Emitted when a new lock is created
    /// @param lock Address of the created lock
    /// @param owner Address of the lock owner
    /// @param token Address of the locked token
    /// @param amount Amount of tokens locked

    event LockCreated(address indexed lock, address indexed owner, address indexed token, uint256 amount);

    /// @notice Emitted when Vesting fee is updated
    /// @param newFee New fee amount
    event FeeAmountVestingUpdated(uint256 indexed newFee);

    /// @notice Emitted when fee token is updated
    /// @param newFeeToken New fee token address
    event FeeTokenUpdated(IERC20 indexed newFeeToken);

    /// @notice Emitted when fee admin is updated
    /// @param newFeeAdmin New fee admin address
    event FeeAdminUpdated(address indexed newFeeAdmin);

    /// @notice Emitted when fee collector is updated
    /// @param newFeeCollector New fee collector address
    event FeeCollectorUpdated(address indexed newFeeCollector);

    /// @notice Emitted when token is whitelisted
    /// @param token Address of the token
    /// @param status Whitelist status
    event TokenWhitelisted(address indexed token, bool indexed status);

    /// @notice Modifier to restrict access to fee admin

    modifier onlyFeeAdmin() {
        if (msg.sender != feeAdmin) revert NotFeeAdmin();
        _;
    }
    /**
     * @notice Constructor that sets the implementation and owner
     * @dev The implementation is the address of the VestingLock contract
     */

    constructor() {
        vestingImpl = address(new VestingLock());
    }

    /// @notice Updates the fee amount for creating a vesting lock
    /// @param _newFee New fee amount
    /// @dev Can only be called by the fee admin
    function updatelockFeeAmountVesting(uint256 _newFee) external onlyFeeAdmin {
        lockFeeAmountVesting = _newFee;
        emit FeeAmountVestingUpdated(_newFee);
    }

    /// @notice Updates the fee token
    /// @param _newFeeToken New fee token address
    /// @dev Can only be called by the fee admin

    function updateLockFeeToken(IERC20 _newFeeToken) external onlyFeeAdmin {
        if (address(_newFeeToken) == address(0)) revert ZeroAddress();

        lockFeeToken = _newFeeToken;
        emit FeeTokenUpdated(_newFeeToken);
    }

    /// @notice Updates the fee admin address
    /// @param _newFeeAdmin New fee admin address
    /// @dev Can only be called by the current fee admin

    function updateFeeAdmin(address _newFeeAdmin) external onlyFeeAdmin {
        if (_newFeeAdmin == address(0)) revert ZeroAddress();

        feeAdmin = _newFeeAdmin;
        emit FeeAdminUpdated(_newFeeAdmin);
    }

    /// @notice Updates the fee collector address
    /// @param _newFeeCollector New fee collector address
    /// @dev Can only be called by the fee admin

    function updateFeeCollector(address _newFeeCollector) external onlyFeeAdmin {
        if (_newFeeCollector == address(0)) revert ZeroAddress();

        feeCollector = _newFeeCollector;
        emit FeeCollectorUpdated(_newFeeCollector);
    }

    /// @notice Sets the status of a token in whitelist
    /// @param _token Address of the token
    /// @param _status Whitelist status
    /// @dev Can only be called by the fee admin

    function setTokenWhitelist(address _token, bool _status) external onlyFeeAdmin {
        whitelistedTokens[_token] = _status;
        emit TokenWhitelisted(_token, _status);
    }

    /**
     * @notice Create a new vesting lock for tokens
     * @param token Address of token to be vested
     * @param amount Total Number of tokens to be vested
     * @param startTime  From when the vesting contract starts executing (in seconds)
     * @param unlockTime Duration until full released (in seconds)
     * @param cliffPeriod Duration of cliff period (in seconds)
     * @param recipient Address that will receive vested tokens
     * @param slots Total number of vesting periods
     * @param enableCliff Whether cliff period is enabled
     * @return lock Address of the created lock
     */
    function createVestingLock(
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 unlockTime,
        uint256 cliffPeriod,
        address recipient,
        uint256 slots,
        bool enableCliff
    ) external returns (address lock) {
        // TimerConfig struct to group the time related parameters
        Structs.TimerConfig memory timers =
            Structs.TimerConfig({startTime: startTime, unlockTime: unlockTime, cliffPeriod: cliffPeriod});

        // Clone the implementation
        lock = vestingImpl.clone();

        // initialize the lock
        ILock(lock).initialize(
            msg.sender, // owner
            token,
            amount,
            timers,
            recipient,
            slots,
            0, // current slot
            0, // released amount
            0, // Lalastst claimed time
            enableCliff
        );

        if (!isContractDeployed(address(lock))) {
            revert DeploymentFailed();
        }

        IERC20(token).safeTransferFrom(msg.sender, lock, amount);

        if (!whitelistedTokens[token]) {
            lockFeeToken.safeTransferFrom(msg.sender, feeCollector, lockFeeAmountVesting);
        }

        userLocks[msg.sender].push(lock);
        recipientLocks[recipient].push(lock);
        allLocks.push(lock);

        emit LockCreated(lock, msg.sender, token, amount);
    }

    /// @notice Checks if a contract exists at the given address
    /// @param _contract Address to check
    /// @return bool True if contract exists, false otherwise
    /// @dev Uses assembly to check contract size

    function isContractDeployed(address _contract) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_contract)
        }
        return size > 0;
    }

    /**
     * @notice Get all locks created by a user
     * @param user Address of the user
     * @return Array of lock addresses
     */
    function getUserLocks(address user) external view returns (address[] memory) {
        return userLocks[user];
    }

    /**
     * @notice Get all locks where user is a recipient
     * @param recipient Address of the recipient
     * @return Array of lock addresses
     */
    function getRecipientLocks(address recipient) external view returns (address[] memory) {
        return recipientLocks[recipient];
    }

    /**
     * @notice Get the total number of locks
     * @return Number of locks created
     */
    function totalLocks() external view returns (uint256) {
        return allLocks.length;
    }
}
