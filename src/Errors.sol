// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// TokenLockFactory specific errors

/// @notice Thrown when caller is not fee admin
error NotFeeAdmin();

/// @notice Error thrown when contract deployment fails
error DeploymentFailed();

/// @notice Thrown when address provided is zero address
error ZeroAddress();

// BaseLock specific errors

/// @notice InvalidToken error message
error InvalidToken();

/// @notice InvalidOwner error message
error InvalidOwner();

/// @notice NotOwner error message
error NotOwner();

// Vesting Lock specific errors

/// @notice Thrown when trying to withdraw before unlock time

error NotClaimableYet();

/// @notice Thrown when trying to claim more than allocated tokens
error YouClaimedAllAllocatedTokens();

/// @notice Thrown when trying to withdraw by non-recipient
error OnlyRecipient();
