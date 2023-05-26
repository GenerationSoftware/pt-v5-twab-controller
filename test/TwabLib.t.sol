// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { BaseSetup } from "test/utils/BaseSetup.sol";
import { TwabLib } from "src/libraries/TwabLib.sol";
import { TwabLibMock } from "test/mocks/TwabLibMock.sol";
import { ObservationLib, MAX_CARDINALITY } from "src/libraries/ObservationLib.sol";

contract TwabLibTest is BaseSetup {
  TwabLibMock public twabLibMock;
  uint32 public DRAW_LENGTH = 1 days;

  function _computeCumulativeBalance(
    uint256 _currentCumulativeBalance,
    uint256 _currentDelegateBalance,
    uint256 _timeElapsed
  ) internal pure returns (uint256) {
    return _currentCumulativeBalance + (_currentDelegateBalance * _timeElapsed);
  }

  function setUp() public override {
    super.setUp();

    twabLibMock = new TwabLibMock();

    // Ensure time is >= the hardcoded offset.
    vm.warp(TwabLib.PERIOD_OFFSET);
  }

  /* ============ increaseBalances ============ */

  function testIncreaseBalanceHappyPath() public {
    uint96 _amount = 1000e18;
    uint32 _initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _currentTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    vm.warp(_currentTimestamp);

    (ObservationLib.Observation memory _observation, bool _isNew, bool _isRecorded) = twabLibMock
      .increaseBalances(_amount, 0);

    TwabLib.AccountDetails memory accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, _amount);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.nextObservationIndex, 0);
    assertEq(accountDetails.cardinality, 0);
    assertEq(_observation.balance, 0);
    assertEq(_observation.cumulativeBalance, 0);
    assertEq(_observation.timestamp, 0);
    assertFalse(_isNew);
    assertFalse(_isRecorded);

    // No Observation has been recorded since delegate balance hasn't changed so balance is 0
    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), 0);
    assertEq(twabLibMock.getBalanceAt(_currentTimestamp), 0);
  }

  function testIncreaseDelegateBalanceHappyPath() public {
    uint96 _amount = 1000e18;
    uint32 _initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _currentTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    vm.warp(_currentTimestamp);

    (ObservationLib.Observation memory _observation, bool _isNew, bool _isRecorded) = twabLibMock
      .increaseBalances(0, _amount);

    TwabLib.AccountDetails memory accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation.cumulativeBalance, 0);
    assertEq(_observation.timestamp, _currentTimestamp);
    assertTrue(_isNew);
    assertTrue(_isRecorded);

    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), 0);
    assertEq(twabLibMock.getBalanceAt(_currentTimestamp), _amount);
  }

  function testIncreaseDelegateBalanceSameBlock() public {
    uint96 _amount = 1000e18;
    uint96 _totalAmount = _amount * 2;

    uint32 _currentTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    vm.warp(_currentTimestamp);

    // Increase delegateBalance twice
    twabLibMock.increaseBalances(0, _amount);

    (ObservationLib.Observation memory _observation, bool _isNew, bool _isRecorded) = twabLibMock
      .increaseBalances(0, _amount);

    TwabLib.AccountDetails memory accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _totalAmount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation.cumulativeBalance, 0);
    assertTrue(_isRecorded);
    assertEq(_observation.timestamp, _currentTimestamp);
    assertFalse(_isNew);

    assertEq(twabLibMock.getBalanceAt(_currentTimestamp), _totalAmount);
  }

  function testIncreaseDelegateBalanceMultipleRecords() public {
    uint96 _amount = 1000e18;
    uint96 _totalAmount = _amount * 2;

    uint32 _initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(_initialTimestamp);
    (ObservationLib.Observation memory _observation1, bool _isNew, bool _isRecorded) = twabLibMock
      .increaseBalances(0, _amount);

    TwabLib.AccountDetails memory accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation1.cumulativeBalance, 0);
    assertEq(_observation1.timestamp, _initialTimestamp);
    assertTrue(_isNew);

    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), _amount);

    vm.warp(_secondTimestamp);

    ObservationLib.Observation memory _observation2;
    (_observation2, _isNew, _isRecorded) = twabLibMock.increaseBalances(0, _amount);

    accountDetails = twabLibMock.getAccountDetails();

    // Check balance
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _totalAmount);
    assertEq(accountDetails.nextObservationIndex, 2);
    assertEq(accountDetails.cardinality, 2);
    assertEq(
      _observation2.cumulativeBalance,
      _computeCumulativeBalance(
        _observation1.cumulativeBalance,
        _amount,
        _observation2.timestamp - _observation1.timestamp
      )
    );
    assertEq(_observation2.timestamp, _secondTimestamp);
    assertTrue(_isNew);

    assertEq(twabLibMock.getBalanceAt(_secondTimestamp), _totalAmount);
  }

  /* ============ decreaseBalances ============ */

  function testDecreaseBalanceHappyPath() public {
    uint96 _amount = 1000e18;

    (ObservationLib.Observation memory _observation, bool _isNew, bool _isRecorded) = twabLibMock
      .increaseBalances(_amount, 0);

    (_observation, _isNew, _isRecorded) = twabLibMock.decreaseBalances(
      _amount,
      0,
      "Revert message"
    );

    TwabLib.AccountDetails memory accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.nextObservationIndex, 0);
    assertEq(accountDetails.cardinality, 0);
  }

  function testDecreaseDelegateBalanceHappyPath() public {
    uint96 _amount = 1000e18;

    uint32 _initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(_initialTimestamp);
    (ObservationLib.Observation memory _observation, bool _isNew, bool _isRecorded) = twabLibMock
      .increaseBalances(0, _amount);

    TwabLib.AccountDetails memory accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation.cumulativeBalance, 0);
    assertEq(_observation.timestamp, _initialTimestamp);
    assertTrue(_isNew);

    vm.warp(_secondTimestamp);
    (_observation, _isNew, _isRecorded) = twabLibMock.decreaseBalances(
      0,
      _amount,
      "Revert message"
    );

    accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.nextObservationIndex, 2);
    assertEq(accountDetails.cardinality, 2);
    assertEq(_observation.cumulativeBalance, _computeCumulativeBalance(0, _amount, DRAW_LENGTH));
    assertEq(_observation.timestamp, _secondTimestamp);
    assertTrue(_isNew);

    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), _amount);
    assertEq(twabLibMock.getBalanceAt(_secondTimestamp), 0);
  }

  function testDecreaseDelegateBalanceRevert() public {
    uint96 _amount = 1000e18;

    uint32 _initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(_initialTimestamp);
    (ObservationLib.Observation memory _observation, bool _isNew, bool _isRecorded) = twabLibMock
      .increaseBalances(0, _amount);

    TwabLib.AccountDetails memory accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation.cumulativeBalance, 0);
    assertEq(_observation.timestamp, _initialTimestamp);
    assertTrue(_isNew);

    vm.warp(_secondTimestamp);

    // Decrease more than current balance available
    vm.expectRevert(bytes("Revert message"));
    (_observation, _isNew, _isRecorded) = twabLibMock.decreaseBalances(
      _amount + 1,
      0,
      "Revert message"
    );

    // Decrease more than current delegateBalance available
    vm.expectRevert(bytes("Revert message"));
    (_observation, _isNew, _isRecorded) = twabLibMock.decreaseBalances(
      0,
      _amount + 1,
      "Revert message"
    );
  }

  function testDecreaseDelegateBalanceMultipleRecords() public {
    uint96 _amount = 1000e18;
    uint96 _halfAmount = _amount / 2;

    uint32 _initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    uint32 _thirdTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 3);

    vm.warp(_initialTimestamp);
    (ObservationLib.Observation memory _observation, bool _isNew, bool _isRecorded) = twabLibMock
      .increaseBalances(0, _amount);

    TwabLib.AccountDetails memory accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation.cumulativeBalance, 0);
    assertEq(_observation.timestamp, _initialTimestamp);
    assertTrue(_isNew);

    vm.warp(_secondTimestamp);
    ObservationLib.Observation memory _observation2;
    (_observation2, _isNew, _isRecorded) = twabLibMock.decreaseBalances(
      0,
      _halfAmount,
      "Revert message"
    );

    accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _halfAmount);
    assertEq(accountDetails.nextObservationIndex, 2);
    assertEq(accountDetails.cardinality, 2);
    assertEq(_observation2.cumulativeBalance, _computeCumulativeBalance(0, _amount, DRAW_LENGTH));
    assertEq(_observation2.timestamp, _secondTimestamp);
    assertTrue(_isNew);

    vm.warp(_thirdTimestamp);
    (_observation, _isNew, _isRecorded) = twabLibMock.decreaseBalances(
      0,
      _halfAmount,
      "Revert message"
    );

    accountDetails = twabLibMock.getAccountDetails();

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.nextObservationIndex, 3);
    assertEq(accountDetails.cardinality, 3);
    assertEq(
      _observation.cumulativeBalance,
      _computeCumulativeBalance(_observation2.cumulativeBalance, _halfAmount, DRAW_LENGTH)
    );
    assertEq(_observation.timestamp, _thirdTimestamp);
    assertTrue(_isNew);
  }

  /* ============ oldestObservation, newestObservation ============ */

  function testOldestAndNewestTwab() public {
    uint96 _amount = 1000e18;

    uint32 _initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    uint32 _thirdTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 3);

    (uint16 _oldestIndex, ObservationLib.Observation memory _oldestObservation) = twabLibMock
      .getOldestObservation();

    (uint16 _newestIndex, ObservationLib.Observation memory _newestObservation) = twabLibMock
      .getNewestObservation();

    assertEq(_oldestIndex, 0);
    assertEq(_oldestObservation.cumulativeBalance, 0);
    assertEq(_oldestObservation.timestamp, 0);

    // Newest TWAB is the last index on an empty TWAB array
    assertEq(_newestIndex, MAX_CARDINALITY - 1);
    assertEq(_newestObservation.cumulativeBalance, 0);
    assertEq(_newestObservation.timestamp, 0);

    vm.warp(_initialTimestamp);
    twabLibMock.increaseBalances(0, _amount);

    vm.warp(_secondTimestamp);
    twabLibMock.increaseBalances(0, _amount);

    (
      uint16 _secondNewestIndex,
      ObservationLib.Observation memory _secondNewestObservation
    ) = twabLibMock.getNewestObservation();

    assertEq(_secondNewestIndex, 1);

    vm.warp(_thirdTimestamp);
    twabLibMock.decreaseBalances(0, _amount, "Revert message");

    (_oldestIndex, _oldestObservation) = twabLibMock.getOldestObservation();
    (_newestIndex, _newestObservation) = twabLibMock.getNewestObservation();

    assertEq(_oldestIndex, 0);
    assertEq(_oldestObservation.cumulativeBalance, 0);
    assertEq(_oldestObservation.timestamp, _initialTimestamp);
    assertEq(_newestIndex, 2);
    assertEq(
      _newestObservation.cumulativeBalance,
      _computeCumulativeBalance(
        _secondNewestObservation.cumulativeBalance,
        _amount * 2,
        _newestObservation.timestamp - _secondNewestObservation.timestamp
      )
    );
    assertEq(_newestObservation.timestamp, _thirdTimestamp);
  }

  /* ============ getTwabBetween ============ */

  function averageDelegateBalanceBetweenSingleSetup()
    public
    returns (uint32 initialTimestamp, uint32 currentTimestamp, uint96 amount)
  {
    amount = 1000e18;
    initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    currentTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(initialTimestamp);
    twabLibMock.increaseBalances(0, amount);
  }

  function testGetTwabBetweenSingleBefore() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp,

    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_initialTimestamp - 100, _initialTimestamp - 50);

    assertEq(_balance, 0);
  }

  function testGetTwabBetweenSingleBeforeIncluding() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp,

    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_initialTimestamp - 100, _initialTimestamp);

    assertEq(_balance, 0);
  }

  function testGetTwabBetweenSingleFuture() public {
    (uint32 _initialTimestamp, , uint96 amount) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_initialTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_initialTimestamp - 50, _initialTimestamp + 50);

    assertEq(_balance, amount / 2);
  }

  function testGetTwabBetweenSingleCentered() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp,

    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_initialTimestamp - 50, _initialTimestamp + 50);

    assertEq(_balance, 500e18);
  }

  function testGetTwabBetweenSingleAfter() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp,

    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_initialTimestamp + 50, _initialTimestamp + 51);

    assertEq(_balance, 1000e18);
  }

  function testGetAverageBalanceBetween_LargeOverwrite() external {
    uint32 drawStart = TwabLib.PERIOD_OFFSET;
    uint32 drawEnd = drawStart + DRAW_LENGTH;
    uint96 amount = 1e18;
    uint96 largeAmount = 1000000e18;

    vm.warp(uint32(drawStart - (2 * DRAW_LENGTH)));
    twabLibMock.increaseBalances(amount, amount);
    vm.warp(uint32(drawStart - (2 * DRAW_LENGTH) + (DRAW_LENGTH / 2)));
    twabLibMock.decreaseBalances(amount, amount, "Revert");
    vm.warp(uint32(drawStart - 1 seconds));
    twabLibMock.increaseBalances(largeAmount, largeAmount);
    vm.warp(uint32(drawStart + 1 seconds));
    twabLibMock.decreaseBalances(largeAmount, largeAmount, "Revert");
    vm.warp(uint32(drawEnd + DRAW_LENGTH - 1 seconds));
    twabLibMock.increaseBalances(largeAmount, largeAmount);

    uint256 averageBalance = twabLibMock.getTwabBetween(drawStart, drawEnd);
    assertEq(averageBalance, 23648148148148148148);
  }

  function averageDelegateBalanceBetweenDoubleSetup()
    public
    returns (
      uint32 _initialTimestamp,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp,
      uint96 _amount,
      uint96 _secondAmount
    )
  {
    _amount = 1000e18;
    _secondAmount = 500e18;
    _initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    _secondTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    _currentTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 3);

    vm.warp(_initialTimestamp);
    twabLibMock.increaseBalances(0, _amount);

    vm.warp(_secondTimestamp);
    twabLibMock.decreaseBalances(0, _secondAmount, "insufficient-balance");
  }

  function testAverageDelegateBalanceBetweenDoubleTwabBefore() public {
    (
      uint32 _initialTimestamp,
      ,
      uint32 _currentTimestamp,
      ,

    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_initialTimestamp - 100, _initialTimestamp - 50);

    assertEq(_balance, 0);
  }

  function testAverageDelegateBalanceBetwenDoubleCenteredFirst() public {
    (
      uint32 _initialTimestamp,
      ,
      uint32 _currentTimestamp,
      ,

    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_initialTimestamp - 50, _initialTimestamp + 50);

    assertEq(_balance, 500e18);
  }

  function testAverageDelegateBalanceBetwenDoubleOldestIsFirst() public {
    (
      uint32 _initialTimestamp,
      ,
      uint32 _currentTimestamp,
      ,

    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_initialTimestamp, _initialTimestamp + 50);

    assertEq(_balance, 1000e18);
  }

  function testAverageDelegateBalanceBetweenDoubleBetween() public {
    (
      uint32 _initialTimestamp,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp,
      ,

    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_initialTimestamp + 50, _secondTimestamp - 50);

    assertEq(_balance, 1000e18);
  }

  function testAverageDelegateBalanceBetweenDoubleCenteredSecond() public {
    (
      ,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp,
      ,

    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_secondTimestamp - 50, _secondTimestamp + 50);

    assertEq(_balance, 750e18);
  }

  function testAverageDelegateBalanceBetweenDoubleAfter() public {
    (
      ,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp,
      ,

    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_secondTimestamp + 50, _secondTimestamp + 51);

    assertEq(_balance, 500e18);
  }

  function testAverageDelegateBalanceTargetOldest() public {
    (
      ,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp,
      ,

    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(_secondTimestamp - 10, _secondTimestamp);

    assertEq(_balance, 1000e18);
  }

  /* ============ getBalanceAt ============ */

  function getBalanceAtSetup() public returns (uint32 _initialTimestamp, uint32 _currentTimestamp) {
    _initialTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH);
    _currentTimestamp = TwabLib.PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(_initialTimestamp);
    twabLibMock.increaseBalances(0, 1000e18);
  }

  function testDelegateBalanceAtSingleTwabBefore() public {
    (, uint32 _currentTimestamp) = getBalanceAtSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getBalanceAt(500);

    assertEq(_balance, 0);
  }

  function testDelegateBalanceAtPreInitialTimestamp() public {
    (uint32 _initialTimestamp, uint32 _currentTimestamp) = getBalanceAtSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getBalanceAt(_initialTimestamp - 1);

    assertEq(_balance, 0);
  }

  /* ============ Cardinality ============ */
  function testIncreaseCardinality() public {
    uint96 _amount = 1000e18;

    TwabLib.Account memory account = twabLibMock.getAccount();
    assertEq(account.details.cardinality, 0);

    vm.warp(TwabLib.PERIOD_OFFSET);
    (, bool isNew, bool isRecorded) = twabLibMock.increaseBalances(0, _amount);

    TwabLib.AccountDetails memory accountDetails = twabLibMock.getAccountDetails();

    // First observation creates new record
    assertTrue(isNew);
    assertTrue(isRecorded);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);

    // Second observation overwrites previous record
    vm.warp(TwabLib.PERIOD_OFFSET + (DRAW_LENGTH / 2));
    (, isNew, isRecorded) = twabLibMock.increaseBalances(0, _amount);
    accountDetails = twabLibMock.getAccountDetails();
    assertFalse(isNew);
    assertTrue(isRecorded);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount * 2);
  }

  function testIncreaseCardinalityOverflow() public {
    TwabLib.Account memory account = twabLibMock.getAccount();
    assertEq(account.details.nextObservationIndex, 0);
    assertEq(account.details.cardinality, 0);
    assertEq(account.details.balance, 0);
    assertEq(account.details.delegateBalance, 0);

    fillObservationsBuffer();

    account = twabLibMock.getAccount();
    assertEq(account.details.nextObservationIndex, 1);
    assertEq(account.details.cardinality, MAX_CARDINALITY);
    assertEq(account.details.balance, MAX_CARDINALITY + 1);
    assertEq(account.details.delegateBalance, MAX_CARDINALITY + 1);
  }

  // ================== getPreviousOrAtObservation ==================

  function testGetPreviousOrAtObservation() public {
    uint32 t0 = TwabLib.PERIOD_OFFSET + 10 seconds;
    uint32 t1 = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH;
    uint32 t2 = TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * 2);
    uint32 t3 = TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * 3);

    vm.warp(t0);
    twabLibMock.increaseBalances(1, 1);
    vm.warp(t1);
    twabLibMock.increaseBalances(1, 1);
    vm.warp(t2);
    twabLibMock.increaseBalances(1, 1);
    vm.warp(t3);
    twabLibMock.increaseBalances(1, 1);

    // Get observation at timestamp before first observation
    ObservationLib.Observation memory prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      t0 - 1 seconds
    );
    assertEq(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);
    assertGe(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Get observation at first timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t0);
    assertEq(prevOrAtObservation.timestamp, t0);

    // Get observation between first and second timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t1 - 1 seconds);
    assertEq(prevOrAtObservation.timestamp, t0);

    // Get observation at second timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t1);
    assertEq(prevOrAtObservation.timestamp, t1);

    // Get observation between second and third timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t1 + 1 seconds);
    assertEq(prevOrAtObservation.timestamp, t1);

    // Get observation between second and third timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t2 - 1 seconds);
    assertEq(prevOrAtObservation.timestamp, t1);

    // Get observation at third timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t2);
    assertEq(prevOrAtObservation.timestamp, t2);

    // Get observation between third and fourth timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t2 + 1 seconds);
    assertEq(prevOrAtObservation.timestamp, t2);

    // Get observation between third and fourth timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t3 - 1 seconds);
    assertEq(prevOrAtObservation.timestamp, t2);

    // Get observation at fourth timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t3);
    assertEq(prevOrAtObservation.timestamp, t3);

    // Get observation after fourth timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t3 + 1 seconds);
    assertEq(prevOrAtObservation.timestamp, t3);
  }

  function testGetPreviousOrAtObservation_EmptyBuffer() public {
    ObservationLib.Observation memory prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      TwabLib.PERIOD_OFFSET
    );

    assertEq(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);
  }

  function testGetPreviousOrAtObservation_FullBuffer() public {
    fillObservationsBuffer();
    ObservationLib.Observation memory prevOrAtObservation;

    // First observation is overwritten, returns zeroed value
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(TwabLib.PERIOD_OFFSET);
    assertEq(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);
    assertGe(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Get before oldest observation
    (, ObservationLib.Observation memory oldestObservation) = twabLibMock.getOldestObservation();
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      oldestObservation.timestamp - 1 seconds
    );
    assertEq(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);
    assertGe(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Get at oldest observation
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(oldestObservation.timestamp);
    assertEq(prevOrAtObservation.timestamp, oldestObservation.timestamp);
    assertGe(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Get after oldest observation
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      oldestObservation.timestamp + 1 seconds
    );
    assertEq(prevOrAtObservation.timestamp, oldestObservation.timestamp);
    assertGe(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Get observation somewhere in the middle.
    uint32 t = TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * 100);
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t);
    assertEq(prevOrAtObservation.timestamp, t);
    assertGe(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Get observation right before somewhere in the middle.
    t -= 1 seconds;
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t);
    assertEq(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * 99));
    assertGe(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Get newest observation.
    (, ObservationLib.Observation memory newestObservation) = twabLibMock.getNewestObservation();
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(newestObservation.timestamp);
    assertEq(prevOrAtObservation.timestamp, newestObservation.timestamp);
    assertGe(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Get before newest observation.
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      newestObservation.timestamp - 1 seconds
    );
    assertEq(prevOrAtObservation.timestamp, newestObservation.timestamp - TwabLib.PERIOD_LENGTH);
    assertGe(prevOrAtObservation.timestamp, TwabLib.PERIOD_OFFSET);
  }

  // ================== getNextOrNewestObservation ==================

  function testGetNextOrNewestObservation() public {
    uint32 t0 = TwabLib.PERIOD_OFFSET + 10 seconds;
    uint32 t1 = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH;
    uint32 t2 = TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * 2);

    vm.warp(t0);
    twabLibMock.increaseBalances(1, 1);
    vm.warp(t1);
    twabLibMock.increaseBalances(1, 1);
    vm.warp(t2);
    twabLibMock.increaseBalances(1, 1);

    ObservationLib.Observation memory nextOrNewestObservation;
    // Get observation given timestamp before first observation
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(t0 - 1 seconds);
    assertEq(nextOrNewestObservation.timestamp, t0);
    assertGe(nextOrNewestObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Get observation given first timestamp
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(t0);
    assertEq(nextOrNewestObservation.timestamp, t1);

    // Get observation given between first and second timestamp
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(t1 - 1 seconds);
    assertEq(nextOrNewestObservation.timestamp, t1);

    // Get observation given second timestamp
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(t1);
    assertEq(nextOrNewestObservation.timestamp, t2);

    // Get observation given between second and third timestamp
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(t1 + 1 seconds);
    assertEq(nextOrNewestObservation.timestamp, t2);

    // Get observation given third timestamp
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(t2);
    assertEq(nextOrNewestObservation.timestamp, t2);

    // Get observation given after third timestamp
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(t2 + 1 seconds);
    assertEq(nextOrNewestObservation.timestamp, t2);
  }

  function testGetNextOrNewestObservation_EmptyBuffer() public {
    ObservationLib.Observation memory nextOrNewestObservation = twabLibMock
      .getNextOrNewestObservation(TwabLib.PERIOD_OFFSET);

    assertEq(nextOrNewestObservation.timestamp, TwabLib.PERIOD_OFFSET);
  }

  function testGetNextOrNewestObservation_FullBuffer() public {
    fillObservationsBuffer();
    ObservationLib.Observation memory nextOrNewestObservation;
    (, ObservationLib.Observation memory oldestObservation) = twabLibMock.getOldestObservation();

    // First observation is overwritten, returns oldest observation
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(TwabLib.PERIOD_OFFSET);
    assertEq(nextOrNewestObservation.timestamp, oldestObservation.timestamp);
    assertGe(nextOrNewestObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Given somewhere in the middle.
    uint32 t = TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * 100);
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(t);
    assertEq(nextOrNewestObservation.timestamp, t + TwabLib.PERIOD_LENGTH);
    assertGe(nextOrNewestObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Given right before somewhere in the middle.
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(t - 1 seconds);
    assertEq(nextOrNewestObservation.timestamp, t);
    assertGe(nextOrNewestObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Given newest observation.
    (, ObservationLib.Observation memory newestObservation) = twabLibMock.getNewestObservation();
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(newestObservation.timestamp);
    assertEq(nextOrNewestObservation.timestamp, newestObservation.timestamp);
    assertGe(nextOrNewestObservation.timestamp, TwabLib.PERIOD_OFFSET);

    // Given before newest observation.
    nextOrNewestObservation = twabLibMock.getNextOrNewestObservation(
      newestObservation.timestamp - 1 seconds
    );
    assertEq(nextOrNewestObservation.timestamp, newestObservation.timestamp);
    assertGe(nextOrNewestObservation.timestamp, TwabLib.PERIOD_OFFSET);
  }

  // ================== getTimestampPeriod ==================

  function testGetTimestampPeriod() public {
    uint32[4] memory periods;
    periods[0] = twabLibMock.getTimestampPeriod(TwabLib.PERIOD_OFFSET);
    periods[1] = twabLibMock.getTimestampPeriod(TwabLib.PERIOD_OFFSET + 1 seconds);
    periods[2] = twabLibMock.getTimestampPeriod(TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH);
    periods[3] = twabLibMock.getTimestampPeriod(
      TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * 2)
    );

    assertEq(periods[0], 1);
    assertEq(periods[1], 1);
    assertEq(periods[2], 2);
    assertEq(periods[3], 3);
  }

  // ================== isTimeSafe ==================

  function testIsTimeSafe() public {
    uint32 t0 = TwabLib.PERIOD_OFFSET;
    uint32 t1 = TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2);
    uint32 t2 = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH;
    uint32 t3 = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH + 10 seconds;

    // No time is safe when there is no observations.
    assertFalse(twabLibMock.isTimeSafe(t0));
    assertFalse(twabLibMock.isTimeSafe(t0 + 1 seconds));
    assertFalse(twabLibMock.isTimeSafe(t1));
    assertFalse(twabLibMock.isTimeSafe(t1 + 1 seconds));
    assertFalse(twabLibMock.isTimeSafe(t2));
    assertFalse(twabLibMock.isTimeSafe(t2 + 1 seconds));
    assertFalse(twabLibMock.isTimeSafe(t3));
    assertFalse(twabLibMock.isTimeSafe(t3 + (TwabLib.PERIOD_LENGTH / 2)));

    // Create an observation
    vm.warp(t0);
    twabLibMock.increaseBalances(1, 1);
    assertTrue(twabLibMock.isTimeSafe(t0));
    assertTrue(twabLibMock.isTimeSafe(t0 + 1 seconds));
    assertTrue(twabLibMock.isTimeSafe(t1));
    assertTrue(twabLibMock.isTimeSafe(t1 + 1 seconds));
    assertTrue(twabLibMock.isTimeSafe(t2));
    assertTrue(twabLibMock.isTimeSafe(t2 + 1 seconds));
    assertTrue(twabLibMock.isTimeSafe(t3));
    assertTrue(twabLibMock.isTimeSafe(t3 + (TwabLib.PERIOD_LENGTH / 2)));

    // Overwrite observation
    vm.warp(TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2));
    twabLibMock.increaseBalances(1, 1);
    assertFalse(twabLibMock.isTimeSafe(t0));
    assertFalse(twabLibMock.isTimeSafe(t0 + 1 seconds));
    assertTrue(twabLibMock.isTimeSafe(t1));
    assertTrue(twabLibMock.isTimeSafe(t1 + 1 seconds));
    assertTrue(twabLibMock.isTimeSafe(t2));
    assertTrue(twabLibMock.isTimeSafe(t2 + 1 seconds));
    assertTrue(twabLibMock.isTimeSafe(t3));
    assertTrue(twabLibMock.isTimeSafe(t3 + (TwabLib.PERIOD_LENGTH / 2)));

    // Create second observation
    vm.warp(TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH + 10 seconds);
    twabLibMock.increaseBalances(1, 1);
    assertFalse(twabLibMock.isTimeSafe(t0));
    assertFalse(twabLibMock.isTimeSafe(t0 + 1 seconds));
    assertTrue(twabLibMock.isTimeSafe(t1));
    assertTrue(twabLibMock.isTimeSafe(t1 + 1 seconds));
    assertFalse(twabLibMock.isTimeSafe(t2));
    assertFalse(twabLibMock.isTimeSafe(t2 + 1 seconds));
    assertTrue(twabLibMock.isTimeSafe(t3));
    assertTrue(twabLibMock.isTimeSafe(t3 + (TwabLib.PERIOD_LENGTH / 2)));
  }

  // ================== helpers  ==================

  /**
   * @dev Fills the observations buffer with MAX_CARDINALITY + 1 observations. Each observation is 1 period length apart and increases balances by 1.
   */
  function fillObservationsBuffer() internal {
    uint32 t = TwabLib.PERIOD_OFFSET;
    for (uint256 i = 0; i <= MAX_CARDINALITY; i++) {
      vm.warp(t);
      twabLibMock.increaseBalances(1, 1);
      t += TwabLib.PERIOD_LENGTH;
    }
  }
}
