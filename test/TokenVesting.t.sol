// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/locks/VestingLock.sol";
import "../src/Errors.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18); // 1 million tokens with 18 decimals
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
    
    // Addresses from mainnet
    address constant USDC_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant USDC_WHALE = 0x234bb412782E4E6Dd382e086c7622F5eE3F03Fe1;
    
    // Test accounts
    address public owner;
    address public recipient;
    address public newFeeAdmin;
    address public newFeeCollector;
    address public feeAdmin;
    address public feeCollector;
    
    // Test parameters
    uint256 public vestAmount = 1000 * 10**18;  // 1000 mock tokens
    uint256 public vestingDuration = 365 days;
    uint256 public cliffPeriod = 90 days;
    uint256 public slots = 12;  // Monthly vesting
    uint256 public feeAmount = 50 * 10**6;  // 50 USDC (6 decimals)
    
    // Time tracking
    uint256 public startTime;
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
        
        // Deploy vesting implementation
        implementation = new VestingLock();
        
        // Deploy factory
        factory = new TokenVestingFactory();
        
        // Get factory's fee admin and collector
        feeAdmin = factory.feeAdmin();
        feeCollector = factory.feeCollector();
        
        // Distribute tokens for testing
        mockToken.transfer(owner, 10000 * 10**18);  // 10,000 mock tokens
        
        // Get USDC for fee payment
        vm.startPrank(USDC_WHALE);
        IERC20(USDC_POLYGON).transfer(owner, 1000 * 10**6); // 1000 USDC
        IERC20(USDC_POLYGON).transfer(newFeeAdmin, 100 * 10**6); // 100 USDC for new fee admin
        vm.stopPrank();
        
        // Record start time
        startTime = block.timestamp;
    }

    function test_CreateVestingLock() public {
        // approve tokens for locking
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        
        // approve USDC for fee
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);
        
        // create vesting lock
        address lockAddress = factory.createVestingLock(
            address(mockToken),
            vestAmount,
            vestingDuration,
            cliffPeriod,
            recipient,
            slots,
            true // Enable cliff
        );
        vm.stopPrank();
        
        vestingLockAddress = lockAddress;
        
        // verify lock creation
        assertEq(mockToken.balanceOf(lockAddress), vestAmount);
        assertEq(IERC20(USDC_POLYGON).balanceOf(feeCollector), feeAmount);
        
        // verify lock parameters
        ILock lockContract = ILock(lockAddress);
        assertEq(lockContract.getOwner(), owner);
        assertEq(lockContract.getToken(), address(mockToken));
        assertEq(lockContract.getAmount(), vestAmount);
        assertEq(lockContract.getUnlockTime(), vestingDuration);
        assertEq(lockContract.getCliffPeriod(), cliffPeriod);
        assertEq(lockContract.getRecipient(), recipient);
        assertEq(lockContract.getSlots(), slots);
        assertEq(lockContract.getCurrentSlot(), 0);
        assertEq(lockContract.getReleasedAmount(), 0);
        assertTrue(lockContract.getEnableCliff());
    }
    
    function test_WithdrawBeforeCliff_Reverts() public {
        test_CreateVestingLock();
        
        vm.prank(recipient);
        vm.expectRevert(NotClaimableYet.selector);
        VestingLock(vestingLockAddress).withdraw();
    }
    
    function test_WithdrawByNonRecipient_Reverts() public {
        test_CreateVestingLock();
        
        vm.prank(owner);
        vm.expectRevert(OnlyRecipient.selector);
        VestingLock(vestingLockAddress).withdraw();
    }
    
    function test_ZeroAddressChecks_Reverts() public {
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);
        
        // try with zero token address
        vm.expectRevert(InvalidToken.selector);
        factory.createVestingLock(
            address(0), // Zero token address
            vestAmount,
            vestingDuration,
            cliffPeriod,
            recipient,
            slots,
            true
        );
        
        // try with zero recipient address
        vm.expectRevert(ZeroAddress.selector);
        factory.createVestingLock(
            address(mockToken),
            vestAmount,
            vestingDuration,
            cliffPeriod,
            address(0), // Zero recipient address
            slots,
            true
        );
        vm.stopPrank();
        
        // try to update fee token to zero address
        vm.prank(feeAdmin);
        vm.expectRevert(ZeroAddress.selector);
        factory.updateLockFeeToken(IERC20(address(0)));
        
        // try to update fee admin to zero address
        vm.prank(feeAdmin);
        vm.expectRevert(ZeroAddress.selector);
        factory.updateFeeAdmin(address(0));
        
        // try to update fee collector to zero address
        vm.prank(feeAdmin);
        vm.expectRevert(ZeroAddress.selector);
        factory.updateFeeCollector(address(0));
    }

    // function test_ClaimAtCliffEnd_Fail() public {
    //     test_CreateVestingLock();
        
    //     // warp to just after cliff end
    //     vm.warp(startTime + cliffPeriod + 1);
        
    //     // calc expected tokens (one month worth since vesting interval is monthly)
    //     uint256 expectedTokens = vestAmount / slots;
        
    //     // get recipients balance before claim
    //     uint256 balanceBefore = mockToken.balanceOf(recipient);
        
    //     // withdraww tokens
    //     vm.prank(recipient);
    //     VestingLock(vestingLockAddress).withdraw();
        
    //     // verify token balance increased
    //     uint256 balanceAfter = mockToken.balanceOf(recipient);
    //     assertEq(balanceAfter - balanceBefore, expectedTokens);
        
    //     // verify state updates
    //     ILock lockContract = ILock(vestingLockAddress);
    //     assertEq(lockContract.getCurrentSlot(), 1);
    //     assertEq(lockContract.getReleasedAmount(), expectedTokens);
    //     assertEq(lockContract.getLastClaimedTime(), startTime + cliffPeriod + 1);
    // }
    
    function test_ClaimAfterHalfVestingPeriod() public {
        test_CreateVestingLock();
        
        // wrap to halfway through vesting (after cliff)
        vm.warp(startTime + cliffPeriod + vestingDuration / 2);
        
        // calc expected tokens (6 months worth)
        uint256 expectedTokens = (vestAmount / slots) * 6;
        
        // get recipients balance before claim
        uint256 balanceBefore = mockToken.balanceOf(recipient);
        
        // withdraw tokens
        vm.prank(recipient);
        VestingLock(vestingLockAddress).withdraw();
        
        // verify token balance increased
        uint256 balanceAfter = mockToken.balanceOf(recipient);
        assertEq(balanceAfter - balanceBefore, expectedTokens);
        
        // verify state updates
        ILock lockContract = ILock(vestingLockAddress);
        assertEq(lockContract.getCurrentSlot(), 6);
        assertEq(lockContract.getReleasedAmount(), expectedTokens);
    }
    
   
    
    function test_ClaimFullyVestedTwice_Reverts() public {
        test_CreateVestingLock();
        
        // wrap to after full vesting period
        vm.warp(startTime + cliffPeriod + vestingDuration + 1);
        
        // claim all tokens
        vm.prank(recipient);
        VestingLock(vestingLockAddress).withdraw();
        
        // try to claim again
        vm.prank(recipient);
        vm.expectRevert(YouClaimedAllAllocatedTokens.selector);
        VestingLock(vestingLockAddress).withdraw();
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
        factory.updatelockFeeAmountVesting(100 * 10**6);
        
        // verify new admin can update fee
        vm.prank(newFeeAdmin);
        factory.updatelockFeeAmountVesting(75 * 10**6);
        assertEq(factory.lockFeeAmountVesting(), 75 * 10**6);
    }
    
    function test_UpdateFeeCollector() public {
        // update fee collector
        vm.prank(feeAdmin);
        factory.updateFeeCollector(newFeeCollector);
        
        // verify  new collector is set
        assertEq(factory.feeCollector(), newFeeCollector);
        
        // create a new lock and verify fees go to new collector
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);
        
        uint256 collectorBalanceBefore = IERC20(USDC_POLYGON).balanceOf(newFeeCollector);
        
        factory.createVestingLock(
            address(mockToken),
            vestAmount,
            vestingDuration,
            cliffPeriod,
            recipient,
            slots,
            true
        );
        vm.stopPrank();
        
        // verify fee went to new collector
        uint256 collectorBalanceAfter = IERC20(USDC_POLYGON).balanceOf(newFeeCollector);
        assertEq(collectorBalanceAfter - collectorBalanceBefore, feeAmount);
    }
    
    function test_UpdateFeeAmount() public {
        // update fee amount
        uint256 newFeeAmount = 25 * 10**6; // 25 USDC
        vm.prank(feeAdmin);
        factory.updatelockFeeAmountVesting(newFeeAmount);
        
        // verify new fee amount is set
        assertEq(factory.lockFeeAmountVesting(), newFeeAmount);
        
        // create a lock with new fee amount
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), newFeeAmount);
        
        uint256 collectorBalanceBefore = IERC20(USDC_POLYGON).balanceOf(feeCollector);
        
        factory.createVestingLock(
            address(mockToken),
            vestAmount,
            vestingDuration,
            cliffPeriod,
            recipient,
            slots,
            true
        );
        vm.stopPrank();
        
        // verify new fee amount was charged
        uint256 collectorBalanceAfter = IERC20(USDC_POLYGON).balanceOf(feeCollector);
        assertEq(collectorBalanceAfter - collectorBalanceBefore, newFeeAmount);
    }
    
  
    
    function test_GetUserAndRecipientLocks() public {
        // create first lock
        test_CreateVestingLock();
        address lock1 = vestingLockAddress;
        
        // create second lock with different parameters
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount / 2);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);
        
        address lock2 = factory.createVestingLock(
            address(mockToken),
            vestAmount / 2,
            vestingDuration * 2,
            0, // No cliff
            recipient,
            24, // 24 slots
            false // No cliff
        );
        vm.stopPrank();
        
        // get user locks (owner)
        address[] memory userLocks = factory.getUserLocks(owner);
        
        // get recipient locks
        address[] memory recipientLocks = factory.getRecipientLocks(recipient);
        
        // verify user locks
        assertEq(userLocks.length, 2);
        assertEq(userLocks[0], lock1);
        assertEq(userLocks[1], lock2);
        
        // verify recipient locks
        assertEq(recipientLocks.length, 2);
        assertEq(recipientLocks[0], lock1);
        assertEq(recipientLocks[1], lock2);
    }
    
    function test_VestingWithoutCliff() public {
        // create a lock without cliff
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);
        
        address lockAddress = factory.createVestingLock(
            address(mockToken),
            vestAmount,
            vestingDuration,
            0, // No cliff period
            recipient,
            slots,
            false // Disable cliff
        );
        vm.stopPrank();
        
        // warp just a bit into the future (1/12th of vesting period)
        vm.warp(startTime + (vestingDuration / slots) + 1);
        
        // should be able to claim immediately
        vm.prank(recipient);
        VestingLock(lockAddress).withdraw();
        
        // verify 1 slot claimed
        assertEq(mockToken.balanceOf(recipient), vestAmount / slots);
        assertEq(ILock(lockAddress).getCurrentSlot(), 1);
    }

    function test_WhitelistedToken() public {
        // first check fee is required
        uint256 initialFeeCollectorBalance = IERC20(USDC_POLYGON).balanceOf(feeCollector);
        
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        IERC20(USDC_POLYGON).approve(address(factory), feeAmount);
        factory.createVestingLock(
            address(mockToken),
            vestAmount,
            vestingDuration,
            cliffPeriod,
            recipient,
            slots,
            true
        );
        vm.stopPrank();
        
        // verify fee was charged
        uint256 newFeeCollectorBalance = IERC20(USDC_POLYGON).balanceOf(feeCollector);
        assertEq(newFeeCollectorBalance - initialFeeCollectorBalance, feeAmount);
        
        // now whitelist the token
        vm.prank(feeAdmin);
        factory.setTokenWhitelist(address(mockToken) , true);
        
        // create another lock with same token, should not charge fee
        vm.startPrank(owner);
        mockToken.approve(address(factory), vestAmount);
        
        // no USDC approval needed now
        
        uint256 feeCollectorBalanceBeforeWhitelisted = IERC20(USDC_POLYGON).balanceOf(feeCollector);
        
        factory.createVestingLock(
            address(mockToken),
            vestAmount,
            vestingDuration,
            cliffPeriod,
            recipient,
            slots,
            true
        );
        vm.stopPrank();
        
        // verify no additional fee was charged
        uint256 feeCollectorBalanceAfterWhitelisted = IERC20(USDC_POLYGON).balanceOf(feeCollector);
        assertEq(feeCollectorBalanceAfterWhitelisted, feeCollectorBalanceBeforeWhitelisted);
    }




    // function test_ClaimIncrementalAmounts_Failing() public {
    //     test_CreateVestingLock();
        
    //     // Warp to 3 months after cliff (4 months total)
    //     vm.warp(startTime + cliffPeriod + 90 days);
        
    //     // Claim first batch
    //     vm.prank(recipient);
    //     VestingLock(vestingLockAddress).withdraw();
        
    //     // Verify correct amount claimed (3 months worth)
    //     assertEq(mockToken.balanceOf(recipient), (vestAmount / slots) * 3);
    //     assertEq(ILock(vestingLockAddress).getCurrentSlot(), 3);
        
    //     // Warp to 3 more months later (7 months total)
    //     vm.warp(startTime + cliffPeriod + 180 days);
        
    //     // Claim second batch
    //     vm.prank(recipient);
    //     VestingLock(vestingLockAddress).withdraw();
        
    //     // Verify additional tokens claimed (3 more months)
    //     assertEq(mockToken.balanceOf(recipient), (vestAmount / slots) * 6);
    //     assertEq(ILock(vestingLockAddress).getCurrentSlot(), 6);
    // }


      // function test_GetVestingStatus_Failing() public {
    //     test_CreateVestingLock();
        
    //     // before cliff
    //     (
    //         uint256 vestedAmount,
    //         uint256 claimedAmount,
    //         uint256 claimableAmount,
    //         uint256 remainingAmount,
    //         uint256 nextVestingDate,
    //         uint256 vestingProgress
    //     ) = VestingLock(vestingLockAddress).getVestingStatus();
        
    //     assertEq(vestedAmount, 0);
    //     assertEq(claimedAmount, 0);
    //     assertEq(claimableAmount, 0);
    //     assertEq(remainingAmount, vestAmount);
    //     assertEq(nextVestingDate, startTime + cliffPeriod);
    //     assertEq(vestingProgress, 0);
        
    //     // after cliff but before any claims
    //     vm.warp(startTime + cliffPeriod + 30 days);
        
    //     (
    //         vestedAmount,
    //         claimedAmount,
    //         claimableAmount,
    //         remainingAmount,
    //         nextVestingDate,
    //         vestingProgress
    //     ) = VestingLock(vestingLockAddress).getVestingStatus();
        
    //     assertEq(vestedAmount, vestAmount / slots);
    //     assertEq(claimedAmount, 0);
    //     assertEq(claimableAmount, vestAmount / slots);
    //     assertEq(remainingAmount, vestAmount - (vestAmount / slots));
    //     assertEq(vestingProgress, 100 / slots); // 8% for 12 slots
        
    //     // after claiming
    //     vm.prank(recipient);
    //     VestingLock(vestingLockAddress).withdraw();
        
    //     (
    //         vestedAmount,
    //         claimedAmount,
    //         claimableAmount,
    //         remainingAmount,
    //         nextVestingDate,
    //         vestingProgress
    //     ) = VestingLock(vestingLockAddress).getVestingStatus();
        
    //     assertEq(vestedAmount, vestAmount / slots);
    //     assertEq(claimedAmount, vestAmount / slots);
    //     assertEq(claimableAmount, 0);
    //     assertEq(remainingAmount, vestAmount - (vestAmount / slots));
    // }
    


}