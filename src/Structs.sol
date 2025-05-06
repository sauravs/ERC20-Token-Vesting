// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Common Structs
/// @notice Contains common structs used throughout the protocol
library Structs {
    /// @notice Timer configuration struct for vesting schedule
    struct TimerConfig {
        uint256 startTime;  //Timestamp when the vesting contract get activated
        uint256 unlockTime; //  Timestamp when total amount of tokens unlock
        uint256 cliffPeriod; // Duration till cliff period ends
    }
}