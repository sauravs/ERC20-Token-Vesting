// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../BaseLock.sol";
import "../Errors.sol";

/**
 * @title VestingLock
 * @notice Token lock contract with vesting schedule functionality
 * @dev Allows for linear vesting with optional cliff period
 */
contract VestingLock is BaseLock {
    using SafeERC20 for IERC20;

    /// @notice Emitted when vested tokens are withdrawn
    event TokensWithdrawn(
        address indexed recipient,
        uint256 indexed amount,
        uint256 currentSlot,
        uint256 indexed totalReleased,
        uint256 timestamp
    );

    /// @notice Returns the vesting interval
    /// @dev Calculates the time between each slot, ignoring cliff period
    function vestingInterval() public view returns (uint256) {
        uint256 vestingDuration = this.getUnlockTime();
        return vestingDuration / this.getSlots();
    }

    /// @notice Returns the amount of tokens to be vested per slot
    /// @dev Calculates the amount of tokens to be released per slot
    function vestingAmount() public view returns (uint256) {
        return this.getAmount() / this.getSlots();
    }

    /// @notice Get the amount of tokens that are currently claimable
    /// @return Amount of tokens claimable at this moment
    function getClaimableAmount() public view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 startTime = this.getStartTime();
        uint256 cliffPeriod = this.getCliffPeriod();
        bool enableCliff = this.getEnableCliff();

        // check if we're still in cliff period
        if (enableCliff && currentTime < startTime + cliffPeriod) {
            return 0;
        }

        // calculate time passed since vesting started (after cliff if enabled)
        uint256 timePassedForVesting;

        if (enableCliff) {
            // if cliff is enabled, vesting starts after cliff period
            timePassedForVesting = currentTime > (startTime + cliffPeriod) ? currentTime - (startTime + cliffPeriod) : 0;
        } else {
            // otherwise vesting starts immediately
            timePassedForVesting = currentTime - startTime;
        }

        // calculate how many slots have vested based on time passed
        uint256 totalVestedSlots = timePassedForVesting / vestingInterval();

        // cap at max slots
        if (totalVestedSlots > this.getSlots()) {
            totalVestedSlots = this.getSlots();
        }

        // calculate how many new slots can be claimed now
        uint256 newClaimableSlots = 0;
        if (totalVestedSlots > this.getCurrentSlot()) {
            newClaimableSlots = totalVestedSlots - this.getCurrentSlot();
        }

        // calculate tokens to be released
        return newClaimableSlots * vestingAmount();
    }

    /// @notice Get the next vesting date when tokens will be claimable
    /// @return Timestamp of next vesting event (0 if fully vested)
    function getNextVestingDate() public view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 startTime = this.getStartTime();
        uint256 cliffPeriod = this.getCliffPeriod();
        bool enableCliff = this.getEnableCliff();

        // if all tokens are claimed
        if (this.getCurrentSlot() >= this.getSlots()) {
            return 0; // fully vested
        }

        // if we are before cliff period
        if (enableCliff && currentTime < startTime + cliffPeriod) {
            return startTime + cliffPeriod; // next vesting is when cliff ends
        }

        // actual vesting start (after cliff if enabled)
        uint256 vestingStart = enableCliff ? startTime + cliffPeriod : startTime;

        // calculate next slot unlock time
        uint256 nextSlot = this.getCurrentSlot() + 1;
        uint256 nextVestingTime = vestingStart + (nextSlot * vestingInterval());

        return nextVestingTime;
    }

    /// @notice Get detailed vesting schedule information
    /// @return vestedAmount Total amount that has vested so far
    /// @return claimedAmount Amount that has been claimed
    /// @return claimableAmount Amount available to claim now
    /// @return remainingAmount Amount still locked for future vesting
    /// @return nextVestingDate Timestamp when next amount will vest
    /// @return vestingProgress Percentage of total vesting completed (0-100)
    function getVestingStatus()
        external
        view
        returns (
            uint256 vestedAmount,
            uint256 claimedAmount,
            uint256 claimableAmount,
            uint256 remainingAmount,
            uint256 nextVestingDate,
            uint256 vestingProgress
        )
    {
        uint256 currentTime = block.timestamp;
        uint256 startTime = this.getStartTime();
        uint256 cliffPeriod = this.getCliffPeriod();
        bool enableCliff = this.getEnableCliff();
        uint256 totalAmount = this.getAmount();

        claimedAmount = this.getReleasedAmount();
        claimableAmount = getClaimableAmount();
        nextVestingDate = getNextVestingDate();

        // if we are still in cliff, nothing has vested
        if (enableCliff && currentTime < startTime + cliffPeriod) {
            vestedAmount = 0;
        } else {
            // calculate time passed for vesting
            uint256 vestingStart = enableCliff ? startTime + cliffPeriod : startTime;
            uint256 timePassedForVesting = currentTime > vestingStart ? currentTime - vestingStart : 0;

            // calculate slots vested
            uint256 slotsVested = timePassedForVesting / vestingInterval();
            if (slotsVested > this.getSlots()) {
                slotsVested = this.getSlots();
            }

            vestedAmount = slotsVested * vestingAmount();
        }

        remainingAmount = totalAmount - vestedAmount;

        // calculate progress percentage (0-100)
        if (totalAmount > 0) {
            vestingProgress = (vestedAmount * 100) / totalAmount;
        } else {
            vestingProgress = 0;
        }
    }

    /// @notice Withdraws the vested tokens
    /// @dev Transfers the claimable tokens to the recipient
    function withdraw() external override {
        // only recipient can withdraw tokens
        if (msg.sender != this.getRecipient()) {
            revert OnlyRecipient();
        }

        uint256 currentTime = block.timestamp;
        uint256 startTime = this.getStartTime();
        uint256 cliffPeriod = this.getCliffPeriod();
        bool enableCliff = this.getEnableCliff();

        // check if we're still in cliff period
        if (enableCliff && currentTime < startTime + cliffPeriod) {
            revert NotClaimableYet();
        }

        // calculate time passed since vesting started (after cliff if enabled)
        uint256 timePassedForVesting;

        if (enableCliff) {
            // if cliff is enabled, vesting starts after cliff period
            timePassedForVesting = currentTime > (startTime + cliffPeriod) ? currentTime - (startTime + cliffPeriod) : 0;
        } else {
            // otherwise vesting starts immediately
            timePassedForVesting = currentTime - startTime;
        }

        // calculate how many slots have vested based on time passed
        uint256 totalVestedSlots = timePassedForVesting / vestingInterval();  //@audit if comes in decimal?Rounding?

        // cap at max slots
        if (totalVestedSlots > this.getSlots()) {
            totalVestedSlots = this.getSlots();
        }

        // calculate how many new slots can be claimed now
        uint256 newClaimableSlots = 0;
        if (totalVestedSlots > this.getCurrentSlot()) {
            newClaimableSlots = totalVestedSlots - this.getCurrentSlot();
        }

        // if nothing to claim
        if (newClaimableSlots == 0) {
            revert YouClaimedAllAllocatedTokens();
        }

        // calculate tokens to be released
        uint256 tokensToRelease = newClaimableSlots * vestingAmount();

        // update state
        _updateState(
            this.getCurrentSlot() + newClaimableSlots, // update current slot
            this.getReleasedAmount() + tokensToRelease, // update released amount
            currentTime // update last claimed time
        );

        // transfer tokens to recipient
        IERC20(this.getToken()).safeTransfer(this.getRecipient(), tokensToRelease);

        // emit withdrawal event
        emit TokensWithdrawn(
            this.getRecipient(), tokensToRelease, this.getCurrentSlot(), this.getReleasedAmount(), currentTime
        );
    }
}
