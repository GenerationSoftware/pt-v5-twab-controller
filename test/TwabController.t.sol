// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

import { TwabController, SameDelegateAlreadySet, CannotTransferToSponsorshipAddress, MINIMUM_PERIOD_LENGTH, PeriodLengthTooShort, SPONSORSHIP_ADDRESS, TransferToZeroAddress, PeriodOffsetInFuture } from "../src/TwabController.sol";
import { TwabLib, TimestampNotFinalized, MAX_CARDINALITY, InvalidTimeRange } from "../src/libraries/TwabLib.sol";
import { TwabLib } from "../src/libraries/TwabLib.sol";
import { ObservationLib } from "../src/libraries/ObservationLib.sol";
import { BaseTest } from "./utils/BaseTest.sol";

contract TwabControllerTest is BaseTest {
  TwabController public twabController;
  address public mockVault = address(0x1234);
  ERC20 public token;
  uint32 public constant PERIOD_LENGTH = 1 days;
  uint32 public constant PERIOD_OFFSET = 10 days;

  event IncreasedBalance(
    address indexed vault,
    address indexed user,
    uint96 amount,
    uint96 delegateAmount
  );

  event DecreasedBalance(
    address indexed vault,
    address indexed user,
    uint96 amount,
    uint96 delegateAmount
  );

  event ObservationRecorded(
    address indexed vault,
    address indexed user,
    uint96 balance,
    uint96 delegateBalance,
    bool isNew,
    ObservationLib.Observation observation
  );

  event Delegated(address indexed vault, address indexed delegator, address indexed delegate);

  event IncreasedTotalSupply(address indexed vault, uint96 amount, uint96 delegateAmount);

  event DecreasedTotalSupply(address indexed vault, uint96 amount, uint96 delegateAmount);

  event TotalSupplyObservationRecorded(
    address indexed vault,
    uint96 balance,
    uint96 delegateBalance,
    bool isNew,
    ObservationLib.Observation observation
  );

  function setUp() public override {
    super.setUp();

    // Ensure time is >= the hardcoded offset.
    vm.warp(PERIOD_OFFSET);

    twabController = new TwabController(PERIOD_LENGTH, PERIOD_OFFSET);
    token = new ERC20("Test", "TST");
  }

  function testConstructor_periodOffsetInFuture() public {
    // After current timestamp
    vm.expectRevert(abi.encodeWithSelector(PeriodOffsetInFuture.selector, block.timestamp + 1));
    new TwabController(PERIOD_LENGTH, uint32(block.timestamp + 1));
  }

  function testConstructor_PeriodLengthTooShort() public {
    vm.expectRevert(abi.encodeWithSelector(PeriodLengthTooShort.selector));
    new TwabController(MINIMUM_PERIOD_LENGTH - 1, PERIOD_OFFSET);
  }

  function testGetAccount() external {
    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.cardinality, 0);

    for (uint256 i = 0; i < MAX_CARDINALITY; i++) {
      assertEq(account.observations[i].cumulativeBalance, 0);
      assertEq(account.observations[i].timestamp, 0);
    }
  }

  function testGetTotalSupplyAccount() external {
    TwabLib.Account memory account = twabController.getTotalSupplyAccount(mockVault);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.cardinality, 0);

    for (uint256 i = 0; i < MAX_CARDINALITY; i++) {
      assertEq(account.observations[i].cumulativeBalance, 0);
      assertEq(account.observations[i].timestamp, 0);
    }
  }

  function testPeriodEndOnOrAfter_beforeOffset() public {
    assertEq(twabController.periodEndOnOrAfter(PERIOD_OFFSET - 1), PERIOD_OFFSET);
  }

  function testPeriodEndOnOrAfter_atOffset() public {
    assertEq(twabController.periodEndOnOrAfter(PERIOD_OFFSET), PERIOD_OFFSET);
  }

  function testPeriodEndOnOrAfter_midPeriod() public {
    assertEq(
      twabController.periodEndOnOrAfter(PERIOD_OFFSET + PERIOD_LENGTH / 2),
      PERIOD_OFFSET + PERIOD_LENGTH
    );
  }

  function testPeriodEndOnOrAfter_firstPeriod() public {
    assertEq(
      twabController.periodEndOnOrAfter(PERIOD_OFFSET + PERIOD_LENGTH),
      PERIOD_OFFSET + PERIOD_LENGTH
    );
  }

  function testPeriodEndOnOrAfter_secondPeriod() public {
    assertEq(
      twabController.periodEndOnOrAfter(PERIOD_OFFSET + PERIOD_LENGTH * 2),
      PERIOD_OFFSET + PERIOD_LENGTH * 2
    );
  }

  function testBalanceOf() external {
    assertEq(twabController.balanceOf(mockVault, alice), 0);

    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);

    vm.stopPrank();
  }

  function testIsShutdownAt() public {
    assertEq(twabController.isShutdownAt(PERIOD_OFFSET), false, "at beginning");
    assertEq(twabController.isShutdownAt(PERIOD_OFFSET + PERIOD_LENGTH), false, "after first period");
    assertEq(twabController.isShutdownAt((type(uint32).max/PERIOD_LENGTH)*PERIOD_LENGTH + uint256(PERIOD_OFFSET)), false, "at end of last period");
    assertEq(twabController.isShutdownAt(type(uint32).max + uint256(PERIOD_OFFSET)), true, "at end");
    assertEq(twabController.isShutdownAt(type(uint32).max + uint256(PERIOD_OFFSET) + 1), true, "after end");
  }

  function testLastObservationAt() public {
    assertEq(twabController.lastObservationAt(), uint256(PERIOD_OFFSET) + (type(uint32).max/PERIOD_LENGTH)*PERIOD_LENGTH);
  }

  function testGetBalanceAt_beforeHistoryStarted() public {
    // ensure times are finalized
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    // Before history started
    assertEq(twabController.getBalanceAt(mockVault, alice, 0), 0);
    // At history start
    assertEq(twabController.getBalanceAt(mockVault, alice, PERIOD_OFFSET), 0);
  }

  function testGetBalanceAt_safeBalance_success() public {
    vm.startPrank(mockVault);

    // Mint at history start
    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    // In second period
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);

    // balance is safe and non-zero
    assertEq(twabController.getBalanceAt(mockVault, alice, PERIOD_OFFSET), _amount);
  }

  function testGetBalanceAt_safeBalance_and_unsafeBalance() public {
    vm.startPrank(mockVault);

    // Mint at history start
    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    // In second period
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);

    // mint again
    twabController.mint(alice, _amount);

    // only safe balance
    assertEq(twabController.getBalanceAt(mockVault, alice, PERIOD_OFFSET), _amount);
  }

  function testTotalSupply_empty() public {
    assertEq(twabController.totalSupply(address(this)), 0);
  }

  function testTotalSupply_single() public {
    twabController.mint(alice, 10e18);
    assertEq(twabController.totalSupply(address(this)), 10e18);
  }

  function testTotalSupplyDelegateBalance_empty() public {
    assertEq(twabController.totalSupplyDelegateBalance(address(this)), 0);
  }

  function testTotalSupplyDelegateBalance_single() public {
    twabController.mint(alice, 10e18);
    assertEq(twabController.totalSupplyDelegateBalance(address(this)), 10e18);
  }

  function testGetTotalSupplyAt_empty() public {
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) - 1), 0);
  }

  function testGetTotalSupplyAt_single_before() public {
    vm.warp(PERIOD_OFFSET);
    twabController.mint(bob, 10e18);
    assertEq(twabController.getTotalSupplyAt(mockVault, PERIOD_OFFSET - 1), 0);
  }

  function testGetTotalSupplyAt_single_on() public {
    vm.warp(PERIOD_OFFSET);
    twabController.mint(bob, 10e18);
    assertEq(twabController.getTotalSupplyAt(mockVault, PERIOD_OFFSET), 0);
  }

  function testGetTwabBetween_noSnap() public {
    uint32 secondPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(secondPeriodStart);
    twabController.mint(alice, 1000e18);
    vm.warp(secondPeriodStart + PERIOD_LENGTH);
    twabController.mint(alice, 1000e18);
    assertEq(
      twabController.getTwabBetween(
        address(this),
        alice,
        secondPeriodStart,
        secondPeriodStart + PERIOD_LENGTH
      ),
      1000e18
    );
  }

  function testGetTwabBetween_notFinalized_partial() public {
    uint32 firstPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(firstPeriodStart);
    vm.expectRevert(
      abi.encodeWithSelector(
        TimestampNotFinalized.selector,
        firstPeriodStart + PERIOD_LENGTH,
        firstPeriodStart
      )
    );
    twabController.getTwabBetween(
      address(this),
      alice,
      firstPeriodStart,
      firstPeriodStart + PERIOD_LENGTH / 2
    );
  }

  function testGetTwabBetween_finalized() public {
    uint32 firstPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(firstPeriodStart + PERIOD_LENGTH);
    twabController.mint(alice, 1000e18);
    assertEq(
      twabController.getTwabBetween(
        address(this),
        alice,
        firstPeriodStart,
        firstPeriodStart + PERIOD_LENGTH
      ),
      0
    );
  }

  function testGetTwabBetween_snapStart() public {
    uint32 firstPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(firstPeriodStart);
    twabController.mint(alice, 1000e18);
    vm.warp(firstPeriodStart + PERIOD_LENGTH / 2);
    twabController.mint(alice, 1000e18);
    vm.warp(firstPeriodStart + PERIOD_LENGTH);
    assertEq(
      twabController.getTwabBetween(
        address(this),
        alice,
        firstPeriodStart - PERIOD_LENGTH / 2,
        firstPeriodStart + PERIOD_LENGTH
      ),
      1500e18
    );
  }

  function testGetTwabBetween_snapEnd() public {
    uint32 firstPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(firstPeriodStart);
    twabController.mint(alice, 1000e18);
    vm.warp(firstPeriodStart + PERIOD_LENGTH / 2);
    twabController.mint(alice, 1000e18);
    vm.warp(firstPeriodStart + PERIOD_LENGTH);
    assertEq(
      twabController.getTwabBetween(address(this), alice, firstPeriodStart, firstPeriodStart + 1),
      1500e18
    );
  }

  function testGetTimestampPeriod() public {
    assertEq(twabController.getTimestampPeriod(PERIOD_OFFSET), 0);
    assertEq(twabController.getTimestampPeriod(PERIOD_OFFSET - 1), 0);
    assertEq(twabController.getTimestampPeriod(PERIOD_OFFSET + PERIOD_LENGTH), 1);
  }

  function testCurrentOverwritePeriodStartedAt_beginning() public {
    assertEq(twabController.currentOverwritePeriodStartedAt(), PERIOD_OFFSET);
  }

  function testCurrentOverwritePeriodStartedAt_partway() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH / 2);
    assertEq(twabController.currentOverwritePeriodStartedAt(), PERIOD_OFFSET);
  }

  function testCurrentOverwritePeriodStartedAt_next() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(twabController.currentOverwritePeriodStartedAt(), PERIOD_OFFSET + PERIOD_LENGTH);
  }

  /// It should not be possible for a twab measurement to change after the period has finalized.
  function testGetTotalSupplyTwabBetween_regression() public {
    uint32 secondPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(secondPeriodStart);

    twabController.mint(alice, 1000e18);

    vm.warp(secondPeriodStart + PERIOD_LENGTH);

    twabController.mint(alice, 1000e18);

    vm.warp(secondPeriodStart + PERIOD_LENGTH * 2);

    uint256 balance = twabController.getTotalSupplyTwabBetween(
      address(this),
      secondPeriodStart + PERIOD_LENGTH,
      secondPeriodStart + PERIOD_LENGTH * 2
    );

    assertEq(balance, 2000e18);

    vm.warp(secondPeriodStart + PERIOD_LENGTH * 2 + PERIOD_LENGTH / 4);

    twabController.mint(alice, 2222e18);

    vm.warp(secondPeriodStart + PERIOD_LENGTH * 2 + PERIOD_LENGTH / 2);

    twabController.mint(bob, 44444e18);

    vm.warp(secondPeriodStart + PERIOD_LENGTH * 3);

    assertEq(
      balance,
      twabController.getTotalSupplyTwabBetween(
        address(this),
        secondPeriodStart + PERIOD_LENGTH,
        secondPeriodStart + PERIOD_LENGTH * 2
      ),
      "mint after"
    );
  }

  function testGetTotalSupplyTwabBetween_noSnap() public {
    uint32 secondPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(secondPeriodStart);
    twabController.mint(alice, 1000e18);
    vm.warp(secondPeriodStart + PERIOD_LENGTH);
    twabController.mint(alice, 1000e18);
    assertEq(
      twabController.getTotalSupplyTwabBetween(
        address(this),
        secondPeriodStart,
        secondPeriodStart + PERIOD_LENGTH
      ),
      1000e18
    );
  }

  function testGetTotalSupplyTwabBetween_notFinalized_partial() public {
    uint32 firstPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(firstPeriodStart);
    vm.expectRevert(
      abi.encodeWithSelector(
        TimestampNotFinalized.selector,
        firstPeriodStart + PERIOD_LENGTH,
        firstPeriodStart
      )
    );
    twabController.getTotalSupplyTwabBetween(
      address(this),
      firstPeriodStart,
      firstPeriodStart + PERIOD_LENGTH / 2
    );
  }

  function testGetTotalSupplyTwabBetween_finalized() public {
    uint32 firstPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(firstPeriodStart + PERIOD_LENGTH);
    twabController.mint(alice, 1000e18);
    assertEq(
      twabController.getTotalSupplyTwabBetween(
        address(this),
        firstPeriodStart,
        firstPeriodStart + PERIOD_LENGTH
      ),
      0
    );
  }

  function testGetTotalSupplyTwabBetween_snapStart() public {
    uint32 firstPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(firstPeriodStart);
    twabController.mint(alice, 1000e18);
    vm.warp(firstPeriodStart + PERIOD_LENGTH / 2);
    twabController.mint(alice, 1000e18);
    vm.warp(firstPeriodStart + PERIOD_LENGTH);
    assertEq(
      twabController.getTotalSupplyTwabBetween(
        address(this),
        firstPeriodStart - PERIOD_LENGTH / 2,
        firstPeriodStart + PERIOD_LENGTH
      ),
      1500e18
    );
  }

  function testGetTotalSupplyTwabBetween_snapEnd() public {
    uint32 firstPeriodStart = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(firstPeriodStart);
    twabController.mint(alice, 1000e18);
    vm.warp(firstPeriodStart + PERIOD_LENGTH / 2);
    twabController.mint(alice, 1000e18);
    vm.warp(firstPeriodStart + PERIOD_LENGTH);
    assertEq(
      twabController.getTotalSupplyTwabBetween(
        address(this),
        firstPeriodStart,
        firstPeriodStart + 1
      ),
      1500e18
    );
  }

  function testGetTotalSupplyAt_init() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(PERIOD_OFFSET)), 0);
  }

  function testGetTotalSupplyAt_nonZero() public {
    uint96 _mintAmount = 1000e18;
    vm.startPrank(mockVault);
    vm.warp(PERIOD_OFFSET);
    twabController.mint(alice, _mintAmount);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(PERIOD_OFFSET)), _mintAmount);
  }

  function testTotalSupply() public {
    assertEq(twabController.totalSupply(mockVault), 0);
    uint96 _mintAmount = 1000e18;
    vm.startPrank(mockVault);
    twabController.mint(alice, _mintAmount);
    assertEq(twabController.totalSupply(mockVault), _mintAmount);
  }

  function testTotalSupplyDelegateBalance() public {
    assertEq(twabController.totalSupply(mockVault), 0);
    uint96 _mintAmount = 1000e18;
    vm.startPrank(mockVault);
    twabController.mint(alice, _mintAmount); //delegates by default
    twabController.sponsor(alice);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);
  }

  function testSponsorship() external {
    uint256 aliceTwab;
    uint256 totalSupplyTwab;
    uint256 bobTwab;
    uint96 amount = 100e18;
    uint32 t0 = PERIOD_OFFSET;
    uint32 t05 = t0 + PERIOD_LENGTH / 2;
    uint32 t1 = t0 + PERIOD_LENGTH;
    uint32 t2 = t1 + PERIOD_LENGTH;
    uint32 t3 = t2 + PERIOD_LENGTH;

    vm.startPrank(mockVault);
    vm.warp(t05);
    twabController.mint(alice, amount);
    vm.warp(t1);
    twabController.sponsor(alice);
    vm.warp(t2);
    twabController.transfer(alice, bob, amount / 2);
    vm.warp(t3);

    // Alice's TWAB is the same as total supply TWAB
    aliceTwab = twabController.getTwabBetween(mockVault, alice, t0, t1);
    totalSupplyTwab = twabController.getTotalSupplyTwabBetween(mockVault, t0, t1);
    assertEq(aliceTwab, amount / 2, "for the first period alice has half");
    assertEq(aliceTwab, totalSupplyTwab, "alice has total supply");

    // Alice now has zero, due to sponsorship
    aliceTwab = twabController.getTwabBetween(mockVault, alice, t1, t2);
    totalSupplyTwab = twabController.getTotalSupplyTwabBetween(mockVault, t1, t2);
    assertEq(aliceTwab, 0);
    assertEq(totalSupplyTwab, 0);

    // Alice's TWAB is still 0 due to sponsorship
    // Bob's TWAB is 1/2 amount, the same as total supply TWAB
    aliceTwab = twabController.getTwabBetween(mockVault, alice, t2, t3);
    bobTwab = twabController.getTwabBetween(mockVault, bob, t2, t3);
    totalSupplyTwab = twabController.getTotalSupplyTwabBetween(mockVault, t2, t3);
    assertEq(aliceTwab, 0);
    assertEq(bobTwab, amount / 2);
    assertEq(totalSupplyTwab, amount / 2);
  }

  function testSponsorshipDelegation() external {
    assertEq(twabController.totalSupply(mockVault), 0);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);

    uint96 _amount = 1000e18;

    vm.startPrank(mockVault);
    twabController.mint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);

    assertEq(twabController.totalSupply(mockVault), _amount);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _amount);

    twabController.sponsor(alice);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    address _sponsorshipAddress = SPONSORSHIP_ADDRESS;
    assertEq(twabController.balanceOf(mockVault, _sponsorshipAddress), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, _sponsorshipAddress), 0);

    assertEq(twabController.totalSupply(mockVault), _amount);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);

    changePrank(alice);
    twabController.delegate(mockVault, bob);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);

    assertEq(twabController.totalSupply(mockVault), _amount);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _amount);

    vm.stopPrank();
  }

  function testSimpleSponsorshipDelegation() external {
    assertEq(twabController.totalSupply(mockVault), 0);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);

    uint96 _amount = 10;

    vm.startPrank(mockVault);
    twabController.mint(alice, _amount);
    twabController.mint(bob, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.balanceOf(mockVault, bob), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, SPONSORSHIP_ADDRESS), 0);

    twabController.sponsor(bob);
    vm.stopPrank();
    vm.prank(alice);
    twabController.delegate(mockVault, bob);

    // Balances stay the same
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.balanceOf(mockVault, bob), _amount);
    // Delegate balances have changed
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, SPONSORSHIP_ADDRESS), 0);
  }

  function testMint_afterTimerange() public {
    vm.startPrank(mockVault);
    vm.warp(type(uint48).max);
    twabController.mint(alice, 1000e18);
    vm.warp(type(uint64).max);
    assertEq(twabController.balanceOf(mockVault, alice), 1000e18);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 1000e18);
    assertEq(twabController.getBalanceAt(mockVault, alice, type(uint48).max), 0);
    assertEq(twabController.getTotalSupplyAt(mockVault, type(uint48).max), 0);

    twabController.burn(alice, 1000e18);
    assertEq(twabController.balanceOf(mockVault, alice), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    vm.stopPrank();
  }

  function testMint() external {
    uint96 _amount = 1000e18;
    vm.expectEmit(true, true, false, true);
    emit IncreasedBalance(mockVault, alice, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit ObservationRecorded(
      mockVault,
      alice,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({
        cumulativeBalance: 0,
        balance: _amount,
        timestamp: uint32(block.timestamp) - PERIOD_OFFSET
      })
    );

    vm.expectEmit(true, false, false, true);
    emit IncreasedTotalSupply(mockVault, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit TotalSupplyObservationRecorded(
      mockVault,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({
        cumulativeBalance: 0,
        balance: _amount,
        timestamp: uint32(block.timestamp) - PERIOD_OFFSET
      })
    );

    vm.startPrank(mockVault);

    twabController.mint(alice, _amount);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, _amount);
    assertEq(accountDetails.delegateBalance, _amount);

    vm.stopPrank();
  }

  function testBurn() external {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    vm.expectEmit(true, true, false, true);
    emit DecreasedBalance(mockVault, alice, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit ObservationRecorded(
      mockVault,
      alice,
      0,
      0,
      false,
      ObservationLib.Observation({
        cumulativeBalance: 0,
        balance: 0,
        timestamp: uint32(block.timestamp) - PERIOD_OFFSET
      })
    );

    vm.expectEmit(true, false, false, true);
    emit DecreasedTotalSupply(mockVault, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit TotalSupplyObservationRecorded(
      mockVault,
      0,
      0,
      false,
      ObservationLib.Observation({
        cumulativeBalance: 0,
        balance: 0,
        timestamp: uint32(block.timestamp) - PERIOD_OFFSET
      })
    );
    twabController.burn(alice, _amount);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 0, "account details balance matches");
    assertEq(accountDetails.delegateBalance, 0, "account details delegate balance matches");

    vm.stopPrank();
  }

  function testMint_max() public {
    vm.warp(100 days);
    vm.startPrank(mockVault);
    twabController.mint(alice, type(uint96).max);
    uint256 currentTime = uint256(type(uint32).max) + 100 days;
    console2.log("currentTime", currentTime);
    // 4303607295
    vm.warp(currentTime);
    twabController.burn(alice, 100);
    // get the twab up until the very end (excluding last period so we don't have an endtime beyond the records)
    assertEq(
      twabController.getTwabBetween(
        mockVault,
        alice,
        100 days,
        uint256(type(uint32).max) + PERIOD_OFFSET - PERIOD_LENGTH
      ),
      type(uint96).max
    );
    vm.stopPrank();
  }

  function testGetTwabBetween_max() public {
    vm.warp(100 days);
    vm.startPrank(mockVault);
    twabController.mint(alice, type(uint96).max);
    uint256 currentTime = uint256(type(uint32).max) + 100 days;
    console2.log("currentTime", currentTime);
    // 4303607295
    vm.warp(currentTime);
    twabController.burn(alice, 100);
    // get the twab up until the very end (excluding last period so we don't have an endtime beyond the records)
    assertEq(
      twabController.getTwabBetween(
        mockVault,
        alice,
        100 days,
        uint256(type(uint32).max) + PERIOD_OFFSET - PERIOD_LENGTH
      ),
      type(uint96).max
    );
    vm.stopPrank();
  }

  function testIsNewEvent() external {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    vm.expectEmit(true, true, false, true);
    emit IncreasedBalance(mockVault, alice, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit ObservationRecorded(
      mockVault,
      alice,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({
        cumulativeBalance: 0,
        balance: _amount,
        timestamp: uint32(block.timestamp) - PERIOD_OFFSET
      })
    );

    vm.expectEmit(true, false, false, true);
    emit IncreasedTotalSupply(mockVault, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit TotalSupplyObservationRecorded(
      mockVault,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({
        cumulativeBalance: 0,
        balance: _amount,
        timestamp: uint32(block.timestamp) - PERIOD_OFFSET
      })
    );
    twabController.mint(alice, _amount);

    vm.expectEmit(true, true, false, true);
    emit DecreasedBalance(mockVault, alice, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit ObservationRecorded(
      mockVault,
      alice,
      0,
      0,
      false,
      ObservationLib.Observation({
        cumulativeBalance: 0,
        balance: 0,
        timestamp: uint32(block.timestamp) - PERIOD_OFFSET
      })
    );

    vm.expectEmit(true, false, false, true);
    emit DecreasedTotalSupply(mockVault, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit TotalSupplyObservationRecorded(
      mockVault,
      0,
      0,
      false,
      ObservationLib.Observation({
        cumulativeBalance: 0,
        balance: 0,
        timestamp: uint32(block.timestamp) - PERIOD_OFFSET
      })
    );
    twabController.burn(alice, _amount);
    vm.stopPrank();
  }

  function testTransfer() external {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);

    changePrank(alice);
    twabController.delegate(mockVault, bob);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);

    changePrank(mockVault);
    twabController.transfer(alice, charlie, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, charlie), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, charlie), _amount);

    vm.stopPrank();
  }

  function testTransfer_rejectSponsorshipAddress() public {
    twabController.mint(alice, 100e18);
    address sponsorship = SPONSORSHIP_ADDRESS;
    vm.expectRevert(abi.encodeWithSelector(CannotTransferToSponsorshipAddress.selector));
    twabController.transfer(alice, sponsorship, 100e18);
  }

  /* ============ delegate ============ */

  function testDelegate() external {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    assertEq(twabController.delegateOf(mockVault, alice), alice);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);

    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);

    assertEq(twabController.delegateBalanceOf(mockVault, charlie), 0);
    assertEq(twabController.balanceOf(mockVault, charlie), 0);

    changePrank(alice);
    twabController.delegate(mockVault, bob);

    assertEq(twabController.delegateOf(mockVault, alice), bob);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);

    assertEq(twabController.balanceOf(mockVault, charlie), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, charlie), 0);

    twabController.delegate(mockVault, charlie);

    assertEq(twabController.delegateOf(mockVault, alice), charlie);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);

    assertEq(twabController.balanceOf(mockVault, charlie), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, charlie), _amount);

    changePrank(mockVault);
    twabController.mint(alice, _amount);

    uint96 _totalAmount = _amount * 2;

    assertEq(twabController.balanceOf(mockVault, alice), _totalAmount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, charlie), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, charlie), _totalAmount);

    vm.stopPrank();
  }

  function testDelegateOf_default() public {
    assertEq(twabController.delegateOf(mockVault, alice), alice);
  }

  function testDelegateOf_sponsorship() public {
    vm.startPrank(mockVault);
    twabController.sponsor(alice);
    assertEq(twabController.delegateOf(mockVault, alice), SPONSORSHIP_ADDRESS);
  }

  function testDelegateOf_addressZero() public {
    vm.startPrank(alice);
    twabController.delegate(mockVault, address(0));
    assertEq(twabController.delegateOf(mockVault, alice), SPONSORSHIP_ADDRESS);
  }

  function testDelegateOf_address() public {
    address bob = makeAddr("bob");
    vm.startPrank(alice);
    twabController.delegate(mockVault, bob);
    assertEq(twabController.delegateOf(mockVault, alice), bob);
  }

  function testMint_lastObservation() public {
    vm.startPrank(mockVault);
    uint96 _amount = 1000e18;
    uint lastAt = twabController.lastObservationAt();
    console2.log("LAST AT", lastAt);
    vm.warp(lastAt);
    twabController.mint(alice, _amount);
    vm.warp(lastAt + PERIOD_LENGTH);
    assertEq(twabController.getBalanceAt(mockVault, alice, lastAt), _amount);
    vm.stopPrank();
  }

  function testMint_toZero() public {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    vm.expectRevert(abi.encodeWithSelector(TransferToZeroAddress.selector));
    twabController.mint(address(0), _amount);
  }

  function testTransfer_toZero() public {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);
    vm.expectRevert(abi.encodeWithSelector(TransferToZeroAddress.selector));
    twabController.transfer(alice, address(0), _amount);
  }

  function testDelegate_toSelf() public {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    assertEq(twabController.delegateOf(mockVault, alice), alice);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
  }

  function testDelegate_interpretBurnAddressAsSponsorship() external {
    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);
    vm.startPrank(alice);
    twabController.delegate(address(this), address(0));
    assertEq(twabController.totalSupplyDelegateBalance(address(this)), 0);
    assertEq(twabController.delegateBalanceOf(address(this), bob), 0);
    assertEq(twabController.delegateBalanceOf(address(this), alice), 0);
    twabController.delegate(address(this), bob);
    assertEq(twabController.totalSupplyDelegateBalance(address(this)), _amount);
    assertEq(twabController.delegateBalanceOf(address(this), bob), _amount);
    assertEq(twabController.delegateBalanceOf(address(this), alice), 0);
    vm.stopPrank();
  }

  function testDelegateToSponsorship() external {
    address _sponsorshipAddress = SPONSORSHIP_ADDRESS;

    assertEq(twabController.delegateOf(mockVault, alice), alice);

    vm.startPrank(mockVault);
    twabController.sponsor(alice);

    assertEq(twabController.delegateOf(mockVault, alice), _sponsorshipAddress);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, _sponsorshipAddress), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, _sponsorshipAddress), 0);

    vm.stopPrank();
  }

  function testDelegateAlreadySet() external {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(SameDelegateAlreadySet.selector, alice));
    twabController.delegate(mockVault, alice);

    vm.stopPrank();
  }

  /* ============ TWAB ============ */

  struct ObservationInfo {
    uint32 timestamp;
    uint96 amount;
    uint16 expectedIndex;
  }

  function mintAndValidate(
    address vault,
    address user,
    ObservationInfo memory observation
  ) internal {
    vm.startPrank(vault);
    vm.warp(observation.timestamp);
    twabController.mint(user, observation.amount);
    TwabLib.Account memory account = twabController.getAccount(vault, user);
    assertEq(
      account.observations[observation.expectedIndex].timestamp,
      observation.timestamp - PERIOD_OFFSET,
      "timestamp"
    );
    assertEq(
      account.observations[observation.expectedIndex + 1].timestamp,
      0,
      "next index timestamp"
    );
    assertEq(
      account.details.nextObservationIndex,
      observation.expectedIndex + 1,
      "next observation index"
    );
    assertEq(account.details.cardinality, observation.expectedIndex + 1, "cardinality");
    vm.stopPrank();
  }

  function burnAndValidate(
    address vault,
    address user,
    ObservationInfo memory observation
  ) internal {
    vm.startPrank(vault);
    vm.warp(observation.timestamp);
    twabController.burn(user, observation.amount);
    TwabLib.Account memory account = twabController.getAccount(vault, user);
    assertEq(
      account.observations[observation.expectedIndex].timestamp,
      observation.timestamp - PERIOD_OFFSET,
      "burnAndValidate timestamp"
    );
    assertEq(
      account.observations[observation.expectedIndex + 1].timestamp,
      0,
      "burnAndValidate next timestamp"
    );
    assertEq(
      account.details.nextObservationIndex,
      observation.expectedIndex + 1,
      "burnAndValidate next observation index"
    );
    assertEq(
      account.details.cardinality,
      observation.expectedIndex + 1,
      "burnAndValidate cardinality"
    );
    vm.stopPrank();
  }

  function mintAndValidateMultiple(
    address vault,
    address user,
    ObservationInfo[] memory observations
  ) internal {
    uint256 totalBalance = 0;
    for (uint256 i = 0; i < observations.length; i++) {
      // Update TWAB and validate it overwrote properly
      mintAndValidate(vault, user, observations[i]);

      // Validate balances
      uint256 balance = twabController.balanceOf(vault, user);
      uint256 delegateBalance = twabController.delegateBalanceOf(vault, user);
      totalBalance += observations[i].amount;
      assertEq(balance, totalBalance, "balance");
      assertEq(delegateBalance, totalBalance, "delegate balance");
    }
  }

  function testOverwriteObservations_HappyPath() external {
    uint96 amount = 1e18;
    uint32 periodTenth = PERIOD_LENGTH / 10;
    uint32 t0 = PERIOD_OFFSET;
    uint32 t1 = PERIOD_OFFSET + PERIOD_LENGTH;
    uint32 t2 = PERIOD_OFFSET + PERIOD_LENGTH * 2;
    ObservationInfo[] memory testObservations = new ObservationInfo[](2);
    testObservations[0] = ObservationInfo(t0, amount, 0);
    testObservations[1] = ObservationInfo(t0 + periodTenth, amount, 0);
    // testObservations[2] = ObservationInfo(t0 + (periodTenth * 2), amount, 0);
    // testObservations[3] = ObservationInfo(t0 + (periodTenth * 3), amount, 0);
    // testObservations[4] = ObservationInfo(t1, amount, 1);
    // testObservations[5] = ObservationInfo(t1 + periodTenth, amount, 1);
    // testObservations[6] = ObservationInfo(t2, amount, 2);
    // testObservations[7] = ObservationInfo(t2 + periodTenth, amount, 2);
    mintAndValidateMultiple(mockVault, alice, testObservations);
  }

  function testOverwriteObservations_LongPeriodBetween() external {
    uint96 amount = 1e18;
    uint32 periodTenth = PERIOD_LENGTH / 10;
    uint32 t0 = PERIOD_OFFSET;
    uint32 t1 = PERIOD_OFFSET + PERIOD_LENGTH;
    uint32 t2 = PERIOD_OFFSET + (PERIOD_LENGTH * 42);
    ObservationInfo[] memory testObservations = new ObservationInfo[](7);
    testObservations[0] = ObservationInfo(t0, amount, 0);
    testObservations[1] = ObservationInfo(t0 + periodTenth, amount, 0);
    testObservations[2] = ObservationInfo(t1 + periodTenth, amount, 1);
    testObservations[3] = ObservationInfo(t1 + (periodTenth * 2), amount, 1);
    testObservations[4] = ObservationInfo(t1 + (periodTenth * 3), amount, 1);
    testObservations[5] = ObservationInfo(t2 + periodTenth, amount, 2);
    testObservations[6] = ObservationInfo(t2 + (periodTenth * 2), amount, 2);
    mintAndValidateMultiple(mockVault, alice, testObservations);
  }

  function testOverwriteObservations_FullStateCheck() external {
    uint96 amount = 1e18;
    uint32 periodTenth = PERIOD_LENGTH / 10;
    uint32 t0 = PERIOD_OFFSET;
    uint32 t1 = PERIOD_OFFSET + PERIOD_LENGTH;
    uint32 t2 = PERIOD_OFFSET + (PERIOD_LENGTH * 2);
    ObservationInfo[] memory testObservations = new ObservationInfo[](5);
    testObservations[0] = ObservationInfo(t0, amount, 0);
    testObservations[1] = ObservationInfo(t1 + 100, amount, 1);

    // now into t2, and all observations within t2 should collapse
    testObservations[2] = ObservationInfo(t2, amount, 2);
    testObservations[3] = ObservationInfo(t2 + (periodTenth * 8), amount, 2);
    testObservations[4] = ObservationInfo(t2 + (periodTenth * 9), amount, 2);
    mintAndValidateMultiple(mockVault, alice, testObservations);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    assertEq(
      account.observations[0].cumulativeBalance,
      0,
      "first observation has no cumulative bal"
    );

    assertEq(
      account.observations[1].cumulativeBalance,
      86500e18,
      "second obs has 1 period of prev bal"
    );
    assertEq(
      account.observations[1].timestamp,
      t1 + 100 - PERIOD_OFFSET,
      "second obs has 1 period of prev bal"
    );

    assertEq(
      account.observations[2].cumulativeBalance,
      501020e18,
      "third period includes three obs"
    );
    assertEq(
      account.observations[2].timestamp,
      t2 + (periodTenth * 9) - PERIOD_OFFSET,
      "third period has last timestamp"
    );

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestObservation(
      mockVault,
      alice
    );

    assertEq(twab.cumulativeBalance, account.observations[2].cumulativeBalance);
    assertEq(twab.timestamp, account.observations[2].timestamp);
    assertEq(index, 2);
  }

  function testGetOldestAndNewestObservation() external {
    (uint16 newestIndex, ObservationLib.Observation memory newestObservation) = twabController
      .getNewestObservation(mockVault, alice);

    assertEq(newestObservation.cumulativeBalance, 0);
    assertEq(newestObservation.timestamp, 0);
    assertEq(newestIndex, MAX_CARDINALITY - 1);

    (uint16 oldestIndex, ObservationLib.Observation memory oldestObservation) = twabController
      .getOldestObservation(mockVault, alice);

    assertEq(oldestObservation.cumulativeBalance, 0);
    assertEq(oldestObservation.timestamp, 0);
    assertEq(oldestIndex, 0);

    vm.startPrank(mockVault);
    uint96 _amount = 1000e18;

    // Wrap around the TWAB storage
    uint32 t = PERIOD_OFFSET;
    for (uint256 i = 0; i <= MAX_CARDINALITY; i++) {
      vm.warp(t);
      twabController.mint(alice, _amount);
      t += PERIOD_LENGTH;
    }

    (newestIndex, newestObservation) = twabController.getNewestObservation(mockVault, alice);

    assertEq(newestObservation.timestamp, (PERIOD_LENGTH * (MAX_CARDINALITY)), "newest timestamp");
    assertEq(newestIndex, 0, "newest index");

    (oldestIndex, oldestObservation) = twabController.getOldestObservation(mockVault, alice);

    assertEq(oldestObservation.timestamp, PERIOD_LENGTH, "oldest timestamp");
    assertEq(oldestIndex, 1, "oldest index");

    vm.warp(newestObservation.timestamp + PERIOD_LENGTH + PERIOD_OFFSET);

    uint256 aliceTwab = twabController.getTwabBetween(
      mockVault,
      alice,
      oldestObservation.timestamp + PERIOD_OFFSET,
      newestObservation.timestamp + PERIOD_OFFSET
    );
    uint256 totalSupplyTwab = twabController.getTotalSupplyTwabBetween(
      mockVault,
      oldestObservation.timestamp + PERIOD_OFFSET,
      newestObservation.timestamp + PERIOD_OFFSET
    );

    assertEq(aliceTwab, totalSupplyTwab);

    vm.stopPrank();
  }

  function testGetOldestAndNewestTotalSupplyObservation() external {
    (uint16 newestIndex, ObservationLib.Observation memory newestObservation) = twabController
      .getNewestTotalSupplyObservation(mockVault);

    assertEq(newestObservation.cumulativeBalance, 0, "newest obs cumulativeBalance");
    assertEq(newestObservation.timestamp, 0, "newest timestamp");
    assertEq(newestIndex, MAX_CARDINALITY - 1, "newest index");

    (uint16 oldestIndex, ObservationLib.Observation memory oldestObservation) = twabController
      .getOldestTotalSupplyObservation(mockVault);

    assertEq(oldestObservation.cumulativeBalance, 0, "oldest cumulativeBalance");
    assertEq(oldestObservation.timestamp, 0, "oldest timestamp");
    assertEq(oldestIndex, 0, "oldest index");

    vm.startPrank(mockVault);
    uint96 _amount = 1000e18;

    // Wrap around the TWAB storage
    uint32 t = PERIOD_OFFSET;
    for (uint256 i = 0; i <= MAX_CARDINALITY; i++) {
      vm.warp(t);
      twabController.mint(alice, _amount);
      t += PERIOD_LENGTH;
    }

    (newestIndex, newestObservation) = twabController.getNewestTotalSupplyObservation(mockVault);

    assertEq(newestObservation.timestamp, (PERIOD_LENGTH * (MAX_CARDINALITY)));
    assertEq(newestIndex, 0);

    (oldestIndex, oldestObservation) = twabController.getOldestObservation(mockVault, alice);

    assertEq(oldestObservation.timestamp, PERIOD_LENGTH);
    assertEq(oldestIndex, 1);

    vm.stopPrank();
  }

  function testTwabEquivalence() external {
    vm.startPrank(mockVault);
    uint96 _amount = 100e18;

    twabController.mint(alice, _amount);
    twabController.mint(bob, _amount);
    utils.timeTravel(PERIOD_LENGTH); // lock in the previous amounts
    twabController.transfer(alice, bob, _amount / 2);
    utils.timeTravel(PERIOD_LENGTH); // lock in the transfer
    twabController.mint(alice, _amount);
    twabController.mint(bob, _amount);

    uint32 currentTime = uint32(block.timestamp);

    uint256 aliceTwab = twabController.getTwabBetween(mockVault, alice, PERIOD_OFFSET, currentTime);
    uint256 bobTwab = twabController.getTwabBetween(mockVault, bob, PERIOD_OFFSET, currentTime);
    uint256 totalSupplyTwab = twabController.getTotalSupplyTwabBetween(
      mockVault,
      PERIOD_OFFSET,
      currentTime
    );

    assertLt(aliceTwab, bobTwab);
    // Sum of Alice and Bob's TWABs should be less than or equal to the total supply TWAB
    assertApproxEqAbs(aliceTwab + bobTwab, totalSupplyTwab, 1);

    vm.stopPrank();
  }

  function testFlashLoanMitigation() external {
    uint96 largeAmount = 1000000e18;
    uint32 drawStart = PERIOD_OFFSET;
    uint32 drawEnd = drawStart + (PERIOD_LENGTH * 24); // Assume 24 periods in a day for testing purposes.

    vm.warp(drawEnd + PERIOD_LENGTH);
    // Store actual balance during draw N at the end of draw N+1
    uint256 actualDrawBalance = twabController.getTwabBetween(mockVault, alice, drawStart, drawEnd);

    // "Flash loan" deposit immediately at draw start
    mintAndValidate(mockVault, alice, ObservationInfo(drawStart, largeAmount, 0));

    // Withdraw in the same block
    // Note - Second event in the same block doesn't trigger a new event. Observation will have no concept of the flash loan.
    // The flash loan will only be counted for the period of time it was held. Since all of this happens in the same block it will not be captured.
    burnAndValidate(mockVault, alice, ObservationInfo(drawStart, largeAmount, 0));

    vm.warp(drawEnd + PERIOD_LENGTH * 3);

    uint256 manipulatedDrawBalance = twabController.getTwabBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd + PERIOD_LENGTH * 2
    );

    assertEq(manipulatedDrawBalance, actualDrawBalance, "draw balance");
  }

  function testImmediateWithdrawalMitigation() external {
    uint96 largeAmount = 1000000e18;
    uint32 drawStart = PERIOD_OFFSET + PERIOD_LENGTH; // Offset draws and periods by 1 to ensure hardcoded value is safe.
    uint32 drawEnd = drawStart + (PERIOD_LENGTH * 24); // Assume 24 periods in a day for testing purposes.

    // Deposit immediately before draw start
    mintAndValidate(mockVault, alice, ObservationInfo(drawStart - 1 seconds, largeAmount, 0));

    // Withdraw immediately after draw start
    burnAndValidate(mockVault, alice, ObservationInfo(drawStart + 1 seconds, largeAmount, 1));

    // Store actual balance during draw N at the end of draw N+1
    vm.warp(drawEnd);
    uint actualDrawBalance = twabController.getTwabBetween(mockVault, alice, drawStart, drawEnd);

    // Overwrite with large amount to force average across the entire draw period
    mintAndValidate(mockVault, alice, ObservationInfo(drawEnd + 1 seconds, largeAmount, 2));

    vm.warp(drawEnd + 1 seconds);
    uint256 manipulatedDrawBalance = twabController.getTwabBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    assertEq(manipulatedDrawBalance, actualDrawBalance);
  }

  /* ============ hasFinalized ============ */

  function testHasFinalized() external {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    assertTrue(twabController.hasFinalized(PERIOD_OFFSET));
  }

  function testGasUsage_OneObservation() public {
    uint gasBefore;
    uint gasAfter;

    vm.warp(PERIOD_OFFSET + 100 * PERIOD_LENGTH);
    twabController.mint(alice, 1e18);
    vm.warp(PERIOD_OFFSET + MAX_CARDINALITY * PERIOD_LENGTH);

    uint endTime = PERIOD_OFFSET + (MAX_CARDINALITY * PERIOD_LENGTH);

    gasBefore = gasleft();
    twabController.getTwabBetween(address(this), alice, uint32(PERIOD_OFFSET), uint32(endTime));
    gasAfter = gasleft();

    console2.log("Gas used: ", gasBefore - gasAfter);
  }

  function testGasUsage_FullObservations() public {
    uint gasBefore;
    uint gasAfter;

    fillObservationsBuffer(address(this), alice);
    uint startTime = PERIOD_OFFSET + PERIOD_LENGTH * 100;
    uint endTime = PERIOD_OFFSET + (MAX_CARDINALITY * PERIOD_LENGTH);

    gasBefore = gasleft();
    twabController.getTwabBetween(address(this), alice, uint32(startTime), uint32(endTime));
    gasAfter = gasleft();

    console2.log("Gas used: ", gasBefore - gasAfter);
  }

  function fillObservationsBuffer(address vault, address user) internal {
    vm.startPrank(vault);
    uint32 t = PERIOD_OFFSET;
    for (uint256 i = 0; i <= MAX_CARDINALITY; i++) {
      vm.warp(t);
      twabController.mint(user, 1e18);
      t += PERIOD_LENGTH;
    }
    vm.stopPrank();
  }
}
