// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;


import "../Structs.sol";

interface ILock {
    /// @notice Initializes the lock contract with given parameters
    /// @param _owner Address of the lock owner
    /// @param _token Address of the token to lock
    /// @param _amount Amount of tokens to lock
    /// @param _timers Struct containing startTime, unlockTime, and cliffPeriod
    /// @param _recipient Address that can claim the tokens
    /// @param _slots Number of vesting slots
    /// @param _currentSlot Current vesting slot
    /// @param _releasedAmount Amount of tokens already released
    /// @param _lastClaimedTime Last time tokens were claimed
    /// @param _enableCliff Whether cliff is enabled
    function initialize(
        address _owner,
        address _token,
        uint256 _amount,
        Structs.TimerConfig memory _timers,
        address _recipient,
        uint256 _slots,
        uint256 _currentSlot,
        uint256 _releasedAmount,
        uint256 _lastClaimedTime,
        bool _enableCliff
    ) external;

    function withdraw() external;
    function getOwner() external view returns (address);
    function getToken() external view returns (address);
    function getAmount() external view returns (uint256);
    function getUnlockTime() external view returns (uint256);
    function getCliffPeriod() external view returns (uint256);
    function getRecipient() external view returns (address);
    function getSlots() external view returns (uint256);
    function getCurrentSlot() external view returns (uint256);
    function getReleasedAmount() external view returns (uint256);
    function getLastClaimedTime() external view returns (uint256);
    function getEnableCliff() external view returns (bool);
    function getStartTime() external view returns (uint256);
}
