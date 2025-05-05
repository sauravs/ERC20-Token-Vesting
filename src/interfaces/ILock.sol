// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface ILock {
    function initialize(
        address owner,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 unlockTime,
        uint256 cliffPeriod,
        address recepeint,
        uint256 slots,
        uint256 currentSlot,
        uint256 releaseAmount,
        uint256 lastClaimedTime,
        bool enableCliff
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
