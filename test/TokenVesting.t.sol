// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/locks/VestingLock.sol";
import "../src/interfaces/ILock.sol";
import "../src/Errors.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 10_000_000 * 10 ** 18); // 10M tokens
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TokenVestingTest is Test {
    // Contracts
    TokenVestingFactory public factory;
    VestingLock public implementation;
    MockERC20 public mockToken;

    // Addresses
    address constant USDC_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant USDC_WHALE = 0x3A3BD7bb9528E159577F7C2e685CC81A765002E2;

    // Test accounts
    address public owner;
    address public recipient;
    address public feeAdmin;
    address public feeCollector;
    address public newFeeAdmin;
    address public newFeeCollector;

    // Test parameters
    uint256 public vestAmount = 1_000_000 * 10 ** 18; // 1M mock tokens
    uint256 public feeAmount = 50 * 10 ** 6; // 50 USDC

    // Time parameters as durations (in seconds)
    uint256 public cliffDuration = 90 days;
    uint256 public vestingDuration = 365 days;
    uint256 public startDelay = 1 days;
    uint256 public slots = 12; // Monthly vesting

    // Calculated time parameters
    uint256 public startTime;
    uint256 public cliffTime;
    uint256 public unlockTime;

    // Deployment tracking
    address public vestingLockAddress;

    function setUp() public {
        // Fork Polygon mainnet
        string memory rpcUrl = vm.envString("POLYGON_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Set up accounts
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");
        newFeeAdmin = makeAddr("newFeeAdmin");
        newFeeCollector = makeAddr("newFeeCollector");

        // Deploy mock token for vesting
        mockToken = new MockERC20("Mock Token", "MOCK");

        // Deploy the implementation contract
        implementation = new VestingLock();

        // Deploy the factory
        factory = new TokenVestingFactory();

        // Get factory's fee admin and collector
        feeAdmin = factory.feeAdmin();
        feeCollector = factory.feeCollector();

        // Fund test accounts
        mockToken.transfer(owner, vestAmount);

        // Get USDC for fee payment
        vm.startPrank(USDC_WHALE);
        IERC20(USDC_POLYGON).transfer(owner, 1000 * 10 ** 6); // 1000 USDC
        IERC20(USDC_POLYGON).transfer(newFeeAdmin, 100 * 10 ** 6); // 100 USDC for new fee admin
        vm.stopPrank();

        //@audit   cliffTime = block.timestamp + cliffDuration;
        // or   cliffTime = startTime + cliffDuration;
        // initialize time parameters
        startTime = block.timestamp + startDelay;
        //cliffTime = block.timestamp + cliffDuration; (1223434738 + 1 day)
        cliffTime = startTime + cliffDuration;
        unlockTime = cliffTime + vestingDuration;
    }

    // Helper function to create a vesting lock
    function createTestVestingLock(bool enableCliff) internal returns (address) {
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        address lock = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, slots, enableCliff
        );

        vm.stopPrank();
        return lock;
    }

    // Helper function to check vesting lock parameters
    function verifyLockParams(address lock, bool enableCliff) internal {
        ILock lockContract = ILock(lock);

        assertEq(lockContract.getOwner(), owner);
        assertEq(lockContract.getToken(), address(mockToken));
        assertEq(lockContract.getAmount(), vestAmount);
        assertEq(lockContract.getUnlockTime(), unlockTime);
        assertEq(lockContract.getCliffPeriod(), cliffTime);
        assertEq(lockContract.getRecipient(), recipient);
        assertEq(lockContract.getSlots(), slots);
        assertEq(lockContract.getCurrentSlot(), 0);
        assertEq(lockContract.getReleasedAmount(), 0);
        assertEq(lockContract.getEnableCliff(), enableCliff);
        assertEq(lockContract.getStartTime(), startTime);
    }

    // TESTS FOR FACTORY CONTRACT

    function test_CreateVestingLock() public {
        // create vesting lock with cliff enabled
        address lock = createTestVestingLock(true);

        // verify lock was created with correct parameters
        verifyLockParams(lock, true);

        // verify token and fee transfers
        assertEq(mockToken.balanceOf(lock), vestAmount);
        assertEq(IERC20(USDC_POLYGON).balanceOf(feeCollector), feeAmount);
    }

    function test_CreateVestingLock_NoCliff() public {
        address lock = createTestVestingLock(false);

        // verify lock was created with cliff disabled
        verifyLockParams(lock, false);
    }

    function test_ZeroAddress_Reverts() public {
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        // test with zero token address
        vm.expectRevert(InvalidToken.selector);
        factory.createVestingLock(address(0), vestAmount, startTime, unlockTime, cliffTime, recipient, slots, true);

        // test with zero recipient address
        vm.expectRevert(ZeroAddress.selector);
        factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, address(0), slots, true
        );
        vm.stopPrank();
    }

    function test_UpdateFeeAdmin() public {
        // current fee admin updates to new fee admin
        vm.prank(feeAdmin);
        factory.updateFeeAdmin(newFeeAdmin);

        // verify new fee admin is set
        assertEq(factory.feeAdmin(), newFeeAdmin);

        // verify old admin cant update fee anymore
        vm.prank(feeAdmin);
        vm.expectRevert(NotFeeAdmin.selector);
        factory.updatelockFeeAmountVesting(100 * 10 ** 6);

        // verify new admin can update fee
        vm.prank(newFeeAdmin);
        factory.updatelockFeeAmountVesting(75 * 10 ** 6);
        assertEq(factory.lockFeeAmountVesting(), 75 * 10 ** 6);
    }

    function test_UpdateFeeAdmin_ZeroAddress_Reverts() public {
        vm.prank(feeAdmin);
        vm.expectRevert(ZeroAddress.selector);
        factory.updateFeeAdmin(address(0));
    }

    function test_UpdateFeeCollector() public {
        // update fee collector
        vm.prank(feeAdmin);
        factory.updateFeeCollector(newFeeCollector);

        // verify new collector is set
        assertEq(factory.feeCollector(), newFeeCollector);

        // create a new lock and verify fees go to new collector
        uint256 collectorBalanceBefore = IERC20(USDC_POLYGON).balanceOf(newFeeCollector);

        address lock = createTestVestingLock(true);

        // verify fee went to new collector
        uint256 collectorBalanceAfter = IERC20(USDC_POLYGON).balanceOf(newFeeCollector);
        assertEq(collectorBalanceAfter - collectorBalanceBefore, feeAmount);
    }

    function test_UpdateFeeCollector_ZeroAddress_Reverts() public {
        vm.prank(feeAdmin);
        vm.expectRevert(ZeroAddress.selector);
        factory.updateFeeCollector(address(0));
    }

    function test_UpdateLockFeeToken() public {
        // deploy a new token to use as fee
        MockERC20 newFeeToken = new MockERC20("New Fee Token", "NFT");

        // update fee token
        vm.prank(feeAdmin);
        factory.updateLockFeeToken(IERC20(address(newFeeToken)));

        // verify new fee token is set
        assertEq(address(factory.lockFeeToken()), address(newFeeToken));

        // Transfer tokens to owner from the test contract
        newFeeToken.transfer(owner, feeAmount * 10); // Send enough tokens to owner

        // prepare for lock creation with new fee token
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        newFeeToken.approve(address(factory), feeAmount);

        // track balance before
        uint256 collectorBalanceBefore = newFeeToken.balanceOf(feeCollector);

        // create lock with new fee token
        address lock = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, slots, true
        );
        vm.stopPrank();

        // verify fee in new token was collected
        uint256 collectorBalanceAfter = newFeeToken.balanceOf(feeCollector);
        assertEq(collectorBalanceAfter - collectorBalanceBefore, feeAmount);
    }

    function test_UpdateLockFeeToken_ZeroAddress_Reverts() public {
        vm.prank(feeAdmin);
        vm.expectRevert(ZeroAddress.selector);
        factory.updateLockFeeToken(IERC20(address(0)));
    }

    function test_UpdateLockFeeAmountVesting() public {
        uint256 newFeeAmount = 75 * 10 ** 6; // 75 USDC

        // update fee amount
        vm.prank(feeAdmin);
        factory.updatelockFeeAmountVesting(newFeeAmount);

        // verify new fee amount is set
        assertEq(factory.lockFeeAmountVesting(), newFeeAmount);

        // create lock with new fee amount
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), newFeeAmount);

        uint256 collectorBalanceBefore = IERC20(USDC_POLYGON).balanceOf(feeCollector);

        address lock = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, slots, true
        );
        vm.stopPrank();

        // verify new fee amount was charged
        uint256 collectorBalanceAfter = IERC20(USDC_POLYGON).balanceOf(feeCollector);
        assertEq(collectorBalanceAfter - collectorBalanceBefore, newFeeAmount);
    }

    function test_WhitelistToken() public {
        // track initial fee collector balance
        uint256 initialFeeCollectorBalance = IERC20(USDC_POLYGON).balanceOf(feeCollector);

        // create first lock - should charge fee
        address lock1 = createTestVestingLock(true);

        // verify fee was charged
        uint256 afterFirstLockBalance = IERC20(USDC_POLYGON).balanceOf(feeCollector);
        assertEq(afterFirstLockBalance - initialFeeCollectorBalance, feeAmount);

        // whitelist the token
        vm.prank(feeAdmin);
        factory.setTokenWhitelist(address(mockToken), true);

        // mint more tokens for owner since first creation used them all
        mockToken.mint(owner, vestAmount);

        // create another lock with same token - should NOT charge fee
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        // no USDC approval needed since token is whitelisted

        address lock2 = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, slots, true
        );
        vm.stopPrank();

        // verify no additional fee was charged
        uint256 afterSecondLockBalance = IERC20(USDC_POLYGON).balanceOf(feeCollector);
        assertEq(afterSecondLockBalance, afterFirstLockBalance);
    }

    function test_GetUserLocks() public {
        // create first lock
        address lock1 = createTestVestingLock(true);

        // mint more tokens for the owner since the first lock used all tokens
        mockToken.mint(owner, vestAmount);

        // create second lock with different parameters
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount / 2);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        address lock2 = factory.createVestingLock(
            address(mockToken),
            vestAmount / 2,
            startTime,
            unlockTime + 30 days,
            cliffTime - 30 days,
            recipient,
            slots * 2,
            false
        );
        vm.stopPrank();

        // get user locks
        address[] memory userLocks = factory.getUserLocks(owner);

        // verify locks
        assertEq(userLocks.length, 2);
        assertEq(userLocks[0], lock1);
        assertEq(userLocks[1], lock2);
    }

    function test_GetRecipientLocks() public {
        // create first lock
        address lock1 = createTestVestingLock(true);

        // create a second lock for a different recipient
        address otherRecipient = makeAddr("otherRecipient");

        // mint more tokens for the owner since the first lock used all tokens
        mockToken.mint(owner, vestAmount);

        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount / 2);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        address lock2 = factory.createVestingLock(
            address(mockToken), vestAmount / 2, startTime, unlockTime, cliffTime, otherRecipient, slots, true
        );
        vm.stopPrank();

        // get recipient locks
        address[] memory recipientLocks = factory.getRecipientLocks(recipient);
        address[] memory otherRecipientLocks = factory.getRecipientLocks(otherRecipient);

        // verify recipient locks
        assertEq(recipientLocks.length, 1);
        assertEq(recipientLocks[0], lock1);

        assertEq(otherRecipientLocks.length, 1);
        assertEq(otherRecipientLocks[0], lock2);
    }

    // TESTS FOR VESTING LOCK CONTRACT

    function test_WithdrawBeforeCliff_Reverts() public {
        address lock = createTestVestingLock(true);

        // try to withdraw before cliff period
        vm.prank(recipient);
        vm.expectRevert(NotClaimableYet.selector);
        VestingLock(lock).withdraw();
    }

    function test_WithdrawByNonRecipient_Reverts() public {
        address lock = createTestVestingLock(true);

        // move past cliff
        vm.warp(cliffTime + 1);

        // try to withdraw as non-recipient
        vm.prank(owner);
        vm.expectRevert(OnlyRecipient.selector);
        VestingLock(lock).withdraw();
    }

    function test_WithdrawNoNewTokens_Reverts() public {
        address lock = createTestVestingLock(true);

        // move just past cliff but not enough for a full slot
        uint256 vestingInterval = vestingDuration / slots;
        vm.warp(cliffTime + 1); // not enough time for a full slot

        // try to withdraw (should revert since no full slots have passed)
        vm.prank(recipient);
        vm.expectRevert(YouClaimedAllAllocatedTokens.selector);
        VestingLock(lock).withdraw();
    }

    function test_WithdrawAtCliff() public {
        address lock = createTestVestingLock(true);

        // calculate vesting interval and tokens per slot
        uint256 vestingInterval = vestingDuration / slots;
        uint256 tokensPerSlot = vestAmount / slots;

        // wrap to after cliff plus one full vesting interval
        vm.warp(cliffTime + vestingInterval);

        // get recipients balance before claim
        uint256 balanceBefore = mockToken.balanceOf(recipient);

        // withdraw tokens
        vm.prank(recipient);
        VestingLock(lock).withdraw();

        // verify token balance increased by one slot's worth
        uint256 balanceAfter = mockToken.balanceOf(recipient);
        assertEq(balanceAfter - balanceBefore, tokensPerSlot);

        // verify state updates
        ILock lockContract = ILock(lock);
        assertEq(lockContract.getCurrentSlot(), 1);
        assertEq(lockContract.getReleasedAmount(), tokensPerSlot);
    }

    function test_WithdrawMultipleSlots() public {
        address lock = createTestVestingLock(true);

        // calculate vesting interval and tokens per slot
        uint256 vestingInterval = vestingDuration / slots;
        uint256 tokensPerSlot = vestAmount / slots;

        // wrap to after cliff plus three full vesting intervals
        vm.warp(cliffTime + (vestingInterval * 3));

        // get recipients balance before claim
        uint256 balanceBefore = mockToken.balanceOf(recipient);

        // Withdraw tokens
        vm.prank(recipient);
        VestingLock(lock).withdraw();

        // Verify token balance increased by three slots' worth
        uint256 balanceAfter = mockToken.balanceOf(recipient);
        assertEq(balanceAfter - balanceBefore, tokensPerSlot * 3);

        // Verify state updates
        ILock lockContract = ILock(lock);
        assertEq(lockContract.getCurrentSlot(), 3);
        assertEq(lockContract.getReleasedAmount(), tokensPerSlot * 3);
    }

    function test_WithdrawIncrementally() public {
        address lock = createTestVestingLock(true);

        // calculate vesting interval and tokens per slot
        uint256 vestingInterval = vestingDuration / slots;
        uint256 tokensPerSlot = vestAmount / slots;

        // wrap to after cliff plus two full vesting intervals
        vm.warp(cliffTime + (vestingInterval * 2));

        // first withdrawal
        vm.prank(recipient);
        VestingLock(lock).withdraw();

        // verify after first withdrawal
        assertEq(mockToken.balanceOf(recipient), tokensPerSlot * 2);
        assertEq(ILock(lock).getCurrentSlot(), 2);
        assertEq(ILock(lock).getReleasedAmount(), tokensPerSlot * 2);

        // wrap to after five full vesting intervals
        vm.warp(cliffTime + (vestingInterval * 5));

        // second withdrawal
        vm.prank(recipient);
        VestingLock(lock).withdraw();

        // verify after second withdrawal (additional 3 slots)
        assertEq(mockToken.balanceOf(recipient), tokensPerSlot * 5);
        assertEq(ILock(lock).getCurrentSlot(), 5);
        assertEq(ILock(lock).getReleasedAmount(), tokensPerSlot * 5);
    }

    function test_WithdrawAfterFullVesting() public {
        address lock = createTestVestingLock(true);

        // warp to after full vesting period
        vm.warp(unlockTime + 1 days);

        // get recipients balance before claim
        uint256 balanceBefore = mockToken.balanceOf(recipient);

        // withdraw tokens
        vm.prank(recipient);
        VestingLock(lock).withdraw();

        // verify tokens transferred (allow for small rounding errors)
        uint256 balanceAfter = mockToken.balanceOf(recipient);
        uint256 transferredAmount = balanceAfter - balanceBefore;

        // check that the transferred amount is very close to the expected vestAmount
        assertApproxEqRel(transferredAmount, vestAmount, 0.000001e18); // 0.0001% tolerance

        // verify state updates
        ILock lockContract = ILock(lock);
        assertEq(lockContract.getCurrentSlot(), slots);
        assertEq(lockContract.getReleasedAmount(), transferredAmount); // use actual transferred amount
    }

    function test_WithdrawAfterFullClaim_Reverts() public {
        address lock = createTestVestingLock(true);

        // warp to after full vesting period
        vm.warp(unlockTime + 1 days);

        // claim all tokens
        vm.prank(recipient);
        VestingLock(lock).withdraw();

        // try to claim again (should revert)
        vm.prank(recipient);
        vm.expectRevert();
        VestingLock(lock).withdraw();
    }

    function test_WithdrawWithoutCliff() public {
        address lock = createTestVestingLock(false);

        // calculate vesting interval and tokens per slot
        uint256 vestingInterval = (unlockTime - startTime) / slots;
        uint256 tokensPerSlot = vestAmount / slots;

        // for a noncliff lock, vesting starts from startTime
        vm.warp(startTime + (vestingInterval * 3) + 1);

        // get recipients balance before claim
        uint256 balanceBefore = mockToken.balanceOf(recipient);

        // withdraw tokens
        vm.prank(recipient);
        VestingLock(lock).withdraw();

        // verify token balance increased by three slots' worth
        uint256 balanceAfter = mockToken.balanceOf(recipient);
        assertEq(balanceAfter - balanceBefore, 3 * tokensPerSlot);

        // verify state updates
        ILock lockContract = ILock(lock);
        assertEq(lockContract.getCurrentSlot(), 3);
        assertEq(lockContract.getReleasedAmount(), 3 * tokensPerSlot);
    }

    // forge test --mt test_GetClaimableAmount -vvv

    function test_GetClaimableAmount() public {
        address lock = createTestVestingLock(true);

        // calculate tokens per slot
        uint256 tokensPerSlot = vestAmount / slots;
        uint256 vestingInterval = vestingDuration / slots;

        // before cliff
        assertEq(VestingLock(lock).getClaimableAmount(), 0);

        // at cliff (but not enough for a slot)
        vm.warp(cliffTime + 1);
        assertEq(VestingLock(lock).getClaimableAmount(), 0);

        // after 1 full slot from cliff
        vm.warp(cliffTime + vestingInterval);
        assertEq(VestingLock(lock).getClaimableAmount(), tokensPerSlot);

        // after 3 full slots from cliff
        vm.warp(cliffTime + (vestingInterval * 3));
        assertEq(VestingLock(lock).getClaimableAmount(), tokensPerSlot * 3);
    }

    function test_GetNextVestingDate() public {
        address lock = createTestVestingLock(true);

        uint256 vestingInterval = vestingDuration / slots;

        // before cliff
        uint256 nextDate = VestingLock(lock).getNextVestingDate();
        assertEq(nextDate, cliffTime + vestingInterval);

        // after cliff but before first full slot
        vm.warp(cliffTime + 1);
        nextDate = VestingLock(lock).getNextVestingDate();
        assertEq(nextDate, cliffTime + vestingInterval);

        // after first full slot
        vm.warp(cliffTime + vestingInterval);

        // claim tokens
        vm.prank(recipient);
        VestingLock(lock).withdraw();

        // next date should be for 2nd slot
        nextDate = VestingLock(lock).getNextVestingDate();
        assertEq(nextDate, cliffTime + (vestingInterval * 2));

        // warp to after all tokens are vested
        vm.warp(unlockTime + 1);

        // claim all remaining tokens
        vm.prank(recipient);
        VestingLock(lock).withdraw();

        // next date should be 0 (fully vested)
        assertEq(VestingLock(lock).getNextVestingDate(), 0);
    }

    // test using different slot configurations

    function test_DifferentSlotConfigurations() public {
        // mint additional tokens to owner to cover multiple tests
        mockToken.mint(owner, vestAmount * 3);

        // test with 4 quarterly slots
        uint256 quarterlySlots = 4;

        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        address quarterlyLock = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, quarterlySlots, true
        );
        vm.stopPrank();

        // calculate quarterly vesting interval
        uint256 quarterlyInterval = vestingDuration / quarterlySlots;
        uint256 tokensPerQuarter = vestAmount / quarterlySlots;

        // warp to after cliff plus one quarterly interval
        vm.warp(cliffTime + quarterlyInterval);

        // withdraw tokens
        vm.prank(recipient);
        VestingLock(quarterlyLock).withdraw();

        // verify correct amount claimed
        assertEq(mockToken.balanceOf(recipient), tokensPerQuarter);
        assertEq(ILock(quarterlyLock).getCurrentSlot(), 1);

        // test with 24 slots
        uint256 biweeklySlots = 24;

        // Approve more tokens from owner
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        address biweeklyLock = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, biweeklySlots, true
        );
        vm.stopPrank();

        // calculate bi-weekly vesting interval
        uint256 biweeklyInterval = vestingDuration / biweeklySlots;
        uint256 tokensPerBiweek = vestAmount / biweeklySlots;

        // completely reset recipients balance to zero
        vm.startPrank(recipient);
        uint256 recipientBalance = mockToken.balanceOf(recipient);
        mockToken.transfer(address(0xdead), recipientBalance);
        vm.stopPrank();

        // verify balance is now zero
        assertEq(mockToken.balanceOf(recipient), 0);

        // warp to after cliff plus 3 bi-weekly intervals
        vm.warp(cliffTime + (biweeklyInterval * 3));

        // withdraw tokens
        vm.prank(recipient);
        VestingLock(biweeklyLock).withdraw();

        // now the balance should be exactly the amount from the biweekly withdrawal
        assertEq(mockToken.balanceOf(recipient), tokensPerBiweek * 3);
        assertEq(ILock(biweeklyLock).getCurrentSlot(), 3);
    }

    // // Test the vesting interval calculation

    function test_VestingInterval() public {
        // mint additional tokens to owner for this test
        mockToken.mint(owner, vestAmount * 2);

        address lockWithCliff = createTestVestingLock(true);

        // expected interval for lock with cliff
        uint256 expectedIntervalWithCliff = (unlockTime - cliffTime) / slots;

        // verify vesting interval calculation
        assertEq(VestingLock(lockWithCliff).vestingInterval(), expectedIntervalWithCliff);

        // create lock without cliff
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        address lockWithoutCliff = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, slots, false
        );
        vm.stopPrank();

        // expected interval for lock without cliff
        uint256 expectedIntervalWithoutCliff = (unlockTime - startTime) / slots;

        // verify vesting interval calculation
        assertEq(VestingLock(lockWithoutCliff).vestingInterval(), expectedIntervalWithoutCliff);
    }

    function test_VestingAmount() public {
        address lock = createTestVestingLock(true);

        // expected amount per slot
        uint256 expectedAmountPerSlot = vestAmount / slots;

        // verify vesting amount calculation
        assertEq(VestingLock(lock).vestingAmount(), expectedAmountPerSlot);
    }

    ///////////////////////////////// FUZZ TESTS /////////////////////////////////////

    // forge test --mt testFuzz_VestingInterval -vvv

    function testFuzz_VestingInterval(
        uint64 unlockTime,
        uint64 startTime,
        uint64 cliffPeriod,
        uint8 slots,
        bool enableCliff
    ) public {
        // bound and assumptions
        vm.assume(slots > 0 && slots <= 100);

        startTime = uint64(bound(startTime, block.timestamp + 1, block.timestamp + 365 days));

        unlockTime = uint64(bound(unlockTime, startTime + 1 days, startTime + 10 * 365 days));

        cliffPeriod = uint64(bound(cliffPeriod, startTime + 1, unlockTime - 1));

        //approvals
        vm.startPrank(owner);
        mockToken.mint(owner, vestAmount);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        // creating the lock with fuzzed parameters
        address lock = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffPeriod, recipient, slots, enableCliff
        );
        vm.stopPrank();

        // calculate expected interval
        uint256 expectedInterval;
        if (enableCliff) {
            expectedInterval = (unlockTime - cliffPeriod) / slots;
        } else {
            expectedInterval = (unlockTime - startTime) / slots;
        }

        // calculate calculation matches contract
        assertEq(VestingLock(lock).vestingInterval(), expectedInterval);
    }

    // forge test --mt testFuzz_VestingAmount -vvv
    function testFuzz_VestingAmount(uint128 amount, uint8 slots) public {
        // assumptions
        vm.assume(amount > 0);
        vm.assume(slots > 0 && slots <= 100);

        // approvals
        vm.startPrank(owner);
        mockToken.mint(owner, amount);
        mockToken.approve(address(factory), amount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        // create the lock with fuzzed amount and slots
        address lock = factory.createVestingLock(
            address(mockToken),
            amount,
            block.timestamp + 1 days,
            block.timestamp + 730 days, // 2 years
            block.timestamp + 30 days,
            recipient,
            slots,
            true
        );
        vm.stopPrank();

        // expected amount per slot
        uint256 expectedAmountPerSlot = amount / slots;

        // verify calculation matches contract
        assertEq(VestingLock(lock).vestingAmount(), expectedAmountPerSlot);
    }

    // forge test --mt testFuzz_WithdrawMechanismWithCliff -vvv
    function testFuzz_WithdrawMechanismWithCliff(
        uint64 vestDuration,
        uint64 cliffDuration,
        uint8 slots,
        uint64 timeAfterCliff
    ) public {
        // assumptions
        vm.assume(vestDuration >= 30 days); // reasonable vesting duration
        vm.assume(vestDuration <= 10 * 365 days); // max 10 years
        vm.assume(cliffDuration > 0 && cliffDuration < vestDuration); // cliff must be positive
        vm.assume(slots > 0 && slots <= 100); // reasonable number of slots
        vm.assume(timeAfterCliff < vestDuration); // time after cliff should be within vesting duration

        // calculate times
        uint64 currentTime = uint64(block.timestamp);
        uint64 startTime = currentTime + 1 days;
        uint64 cliffTime = startTime + cliffDuration;
        uint64 unlockTime = startTime + vestDuration;
        uint64 withdrawTime = cliffTime + timeAfterCliff;

        // ensure withdrawTime doesnt overflow
        vm.assume(withdrawTime >= cliffTime);

        // steup
        vm.startPrank(owner);
        mockToken.mint(owner, vestAmount);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        // Create the lock with cliff enabled
        address lock = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, slots, true
        );
        vm.stopPrank();

        // caculate vesting parameters
        uint256 vestingDuration = unlockTime - cliffTime;
        uint256 vestingInterval = vestingDuration / slots;
        uint256 tokensPerSlot = vestAmount / slots;

        // warp to withdrawal time
        vm.warp(withdrawTime);

        // get the expected claimable amount
        uint256 timeSinceCliff = withdrawTime > cliffTime ? withdrawTime - cliffTime : 0;
        uint256 totalVestedSlots = timeSinceCliff / vestingInterval;
        if (totalVestedSlots > slots) {
            totalVestedSlots = slots;
        }

        uint256 expectedClaimable = totalVestedSlots * tokensPerSlot;

        // check if we should expect a revert
        if (withdrawTime < cliffTime || totalVestedSlots == 0) {
            vm.prank(recipient);
            vm.expectRevert();
            VestingLock(lock).withdraw();
        } else {
            // get initial balances
            uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

            // withdraw tokens
            vm.prank(recipient);
            VestingLock(lock).withdraw();

            // verify recipient received expected amount
            uint256 finalRecipientBalance = mockToken.balanceOf(recipient);
            uint256 received = finalRecipientBalance - initialRecipientBalance;

            // allow for small rounding errors due to integer division
            assertApproxEqAbs(received, expectedClaimable, 1);

            // verify contract state updated correctly
            assertEq(ILock(lock).getCurrentSlot(), totalVestedSlots);
            assertApproxEqAbs(ILock(lock).getReleasedAmount(), expectedClaimable, 1);
        }
    }

    // forge test --mt testFuzz_WithdrawMechanismWithoutCliff -vvv

    function testFuzz_WithdrawMechanismWithoutCliff(uint64 vestDuration, uint8 slots, uint64 timeAfterStart) public {
        // assumptions
        vm.assume(vestDuration >= 30 days); // reasonable vesting duration
        vm.assume(vestDuration <= 5 * 365 days); // max 5 years
        vm.assume(slots > 0 && slots <= 100); // reasonable number of slots
        vm.assume(timeAfterStart < vestDuration); // time after start should be within vesting duration

        // calculate times
        uint64 currentTime = uint64(block.timestamp);
        uint64 startTime = currentTime + 1 days;
        uint64 cliffTime = startTime + 30 days; // Cliff doesn't matter for this test
        uint64 unlockTime = startTime + vestDuration;
        uint64 withdrawTime = startTime + timeAfterStart;

        // Ensure withdrawTime doesn't overflow
        vm.assume(withdrawTime >= startTime);

        // Setup
        vm.startPrank(owner);
        mockToken.mint(owner, vestAmount);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        // Create the lock with cliff disabled
        address lock = factory.createVestingLock(
            address(mockToken),
            vestAmount,
            startTime,
            unlockTime,
            cliffTime, // This is ignored when cliff is disabled
            recipient,
            slots,
            false // Cliff disabled
        );
        vm.stopPrank();

        // Calculate vesting parameters
        uint256 vestingDuration = unlockTime - startTime;
        uint256 vestingInterval = vestingDuration / slots;
        uint256 tokensPerSlot = vestAmount / slots;

        // Warp to withdrawal time
        vm.warp(withdrawTime);

        // Get the expected claimable amount
        uint256 timeSinceStart = withdrawTime > startTime ? withdrawTime - startTime : 0;
        uint256 totalVestedSlots = timeSinceStart / vestingInterval;
        if (totalVestedSlots > slots) {
            totalVestedSlots = slots;
        }

        uint256 expectedClaimable = totalVestedSlots * tokensPerSlot;

        // Check if we should expect a revert
        if (totalVestedSlots == 0) {
            vm.prank(recipient);
            vm.expectRevert(); // YouClaimedAllAllocatedTokens or NotClaimableYet
            VestingLock(lock).withdraw();
        } else {
            // Get initial balances
            uint256 initialRecipientBalance = mockToken.balanceOf(recipient);

            // Withdraw tokens
            vm.prank(recipient);
            VestingLock(lock).withdraw();

            // Verify recipient received expected amount
            uint256 finalRecipientBalance = mockToken.balanceOf(recipient);
            uint256 received = finalRecipientBalance - initialRecipientBalance;

            // Allow for small rounding errors due to integer division
            assertApproxEqAbs(received, expectedClaimable, 1);

            // Verify contract state updated correctly
            assertEq(ILock(lock).getCurrentSlot(), totalVestedSlots);
            assertApproxEqAbs(ILock(lock).getReleasedAmount(), expectedClaimable, 1);
        }
    }

    // forge test --mt testFuzz_GetClaimableAmount -vvv

    function testFuzz_GetClaimableAmount(
        uint64 vestDuration,
        uint64 cliffDuration,
        uint8 slots,
        uint64 timeAfterStart,
        bool enableCliff
    ) public {
        //  assumptions
        vm.assume(vestDuration >= 30 days);
        vm.assume(vestDuration <= 5 * 365 days); // Max 5 years
        vm.assume(cliffDuration > 0 && cliffDuration < vestDuration);
        vm.assume(slots > 0 && slots <= 100);
        vm.assume(timeAfterStart <= vestDuration + 30 days);

        // calculate times
        uint64 currentTime = uint64(block.timestamp);
        uint64 startTime = currentTime + 1 days;
        uint64 cliffTime = startTime + cliffDuration;
        uint64 unlockTime = startTime + vestDuration;
        uint64 checkTime = startTime + timeAfterStart;

        // ensure times dont overflow
        vm.assume(checkTime >= startTime);
        vm.assume(cliffTime < unlockTime);

        // approvals
        vm.startPrank(owner);
        mockToken.mint(owner, vestAmount);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        // create the lock
        address lock = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, slots, enableCliff
        );
        vm.stopPrank();

        // calc vesting parameters
        uint256 vestingInterval;
        if (enableCliff) {
            vestingInterval = (unlockTime - cliffTime) / slots;
        } else {
            vestingInterval = (unlockTime - startTime) / slots;
        }
        uint256 tokensPerSlot = vestAmount / slots;

        // warp to check time
        vm.warp(checkTime);

        // calculate expected claimable amount
        uint256 timePassedForVesting = 0;
        if (enableCliff) {
            // if still in cliff period, nothing is claimable
            if (checkTime < cliffTime) {
                timePassedForVesting = 0;
            } else {
                timePassedForVesting = checkTime - cliffTime;
            }
        } else {
            timePassedForVesting = checkTime > startTime ? checkTime - startTime : 0;
        }

        uint256 totalVestedSlots = timePassedForVesting / vestingInterval;
        if (totalVestedSlots > slots) {
            totalVestedSlots = slots;
        }

        uint256 expectedClaimable = totalVestedSlots * tokensPerSlot;

        // get contracts calculation
        uint256 contractClaimable = VestingLock(lock).getClaimableAmount();

        // verify calculations match ...allowing for small rounding errors
        assertApproxEqAbs(contractClaimable, expectedClaimable, 1);
    }

  
    // forge test --mt testFuzz_MultipleClaims -vvv

    function testFuzz_MultipleClaims(uint64 vestDuration, uint64 cliffDuration, uint8 slots, bool enableCliff) public {
        // assumptions
        vm.assume(vestDuration >= 90 days);
        vm.assume(vestDuration <= 1825 days);
        vm.assume(cliffDuration > 0 && cliffDuration < vestDuration / 2);
        vm.assume(slots >= 3 && slots <= 100);

        // calculate times
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint64 cliffTime = startTime + cliffDuration;
        uint64 unlockTime = startTime + vestDuration;

        // approvals
        vm.startPrank(owner);
        mockToken.mint(owner, vestAmount);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);

        address lock = factory.createVestingLock(
            address(mockToken), vestAmount, startTime, unlockTime, cliffTime, recipient, slots, enableCliff
        );
        vm.stopPrank();

        // Simplified testing approach - use helper function to reduce local variables for avoiding stack too deep errors
        _testMultipleWithdrawals(lock, startTime, cliffTime, unlockTime, slots, enableCliff);
    }

    // helper function to reduce local variables in main test

    function _testMultipleWithdrawals(
        address lock,
        uint64 startTime,
        uint64 cliffTime,
        uint64 unlockTime,
        uint8 slots,
        bool enableCliff
    ) internal {
        // calculate vesting parameters
        uint256 vestingInterval = enableCliff ? (unlockTime - cliffTime) / slots : (unlockTime - startTime) / slots;

        uint256 firstClaimPoint = enableCliff ? cliffTime + vestingInterval : startTime + vestingInterval;

        uint256 tokensPerSlot = vestAmount / slots;
        uint256 totalClaimed = 0;
        uint256 currentSlot = 0;

        // first claim
        vm.warp(firstClaimPoint);

        if (VestingLock(lock).getClaimableAmount() > 0) {
            vm.prank(recipient);
            VestingLock(lock).withdraw();

            totalClaimed += tokensPerSlot;
            currentSlot = 1;

            // basic verification
            assertEq(ILock(lock).getCurrentSlot(), currentSlot);
        }

        // second claim
        vm.warp(firstClaimPoint + (2 * vestingInterval));

        vm.prank(recipient);
        try VestingLock(lock).withdraw() {
            currentSlot = 3; // should now be at slot 3
            assertEq(ILock(lock).getCurrentSlot(), currentSlot);
        } catch {}

        // final claim
        vm.warp(unlockTime + 1);

        vm.prank(recipient);
        try VestingLock(lock).withdraw() {
            uint256 tolerance = 100;
            assertApproxEqAbs(ILock(lock).getReleasedAmount(), vestAmount, tolerance);
            assertApproxEqAbs(mockToken.balanceOf(recipient), vestAmount, tolerance);
            assertEq(ILock(lock).getCurrentSlot(), slots);
        } catch {}

        // verify cant claim more
        vm.warp(unlockTime + 30 days);
        vm.prank(recipient);
        vm.expectRevert();
        VestingLock(lock).withdraw();
    }
}
