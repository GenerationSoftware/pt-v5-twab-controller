// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { TwabLib, BalanceLTAmount, DelegateBalanceLTAmount, TimestampNotFinalized, InsufficientHistory, InvalidTimeRange } from "../src/libraries/TwabLib.sol";
import { ObservationLib, MAX_CARDINALITY } from "../src/libraries/ObservationLib.sol";

import { BaseTest } from "./utils/BaseTest.sol";
import { TwabLibMock } from "./mocks/TwabLibMock.sol";

contract TwabLibTest is BaseTest {
  TwabLibMock public twabLibMock;
  uint32 public DRAW_LENGTH = 1 days;
  uint32 public LARGE_DRAW_LENGTH = 7 days;
  uint32 public VERY_LARGE_DRAW_LENGTH = 399 days;
  uint32 public constant PERIOD_OFFSET = 10 days;
  uint32 public constant PERIOD_LENGTH = 1 days;

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
    vm.warp(PERIOD_OFFSET);
  }

  /* ============ increaseBalances ============ */

  function testIncreaseBalance_endOfTimerange() public {
    uint256 timestamp = twabLibMock.lastObservationAt();
    vm.warp(timestamp);
    twabLibMock.increaseBalances(1000e18, 1000e18);
    vm.warp(uint256(type(uint48).max));
    assertEq(twabLibMock.getBalanceAt(timestamp), 1000e18);
  }

  function testDecreaseBalance_endOfTimerange() public {
    vm.warp(PERIOD_OFFSET);
    twabLibMock.increaseBalances(1000e18, 1000e18);
    uint256 timestamp = twabLibMock.lastObservationAt();
    vm.warp(timestamp);
    twabLibMock.decreaseBalances(100e18, 100e18, "revert message");
    vm.warp(uint256(type(uint48).max));
    assertEq(twabLibMock.getBalanceAt(timestamp), 900e18);
  }

  function testIncreaseBalanceHappyPath() public {
    uint96 _amount = 1000e18;
    uint32 _initialTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _currentTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    vm.warp(_currentTimestamp);

    (
      ObservationLib.Observation memory _observation,
      bool _isNew,
      bool _isRecorded,
      TwabLib.AccountDetails memory accountDetails
    ) = twabLibMock.increaseBalances(_amount, 0);

    assertEq(accountDetails.balance, _amount);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.nextObservationIndex, 0);
    assertEq(accountDetails.cardinality, 0);
    assertEq(_observation.cumulativeBalance, 0);
    assertEq(_observation.balance, 0);
    assertEq(_observation.timestamp, 0);
    assertFalse(_isNew);
    assertFalse(_isRecorded);

    vm.warp(_currentTimestamp + PERIOD_LENGTH);

    // No Observation has been recorded since delegate balance hasn't changed so balance is 0
    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), 0);
    assertEq(twabLibMock.getBalanceAt(_currentTimestamp), 0);
  }

  function testIncreaseDelegateBalanceHappyPath() public {
    uint96 _amount = 1000e18;
    uint32 _currentTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    vm.warp(_currentTimestamp);

    (
      ObservationLib.Observation memory _observation,
      bool _isNew,
      bool _isRecorded,
      TwabLib.AccountDetails memory accountDetails
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation.cumulativeBalance, 0);
    assertEq(_observation.timestamp, _currentTimestamp - PERIOD_OFFSET);
    assertTrue(_isNew);
    assertTrue(_isRecorded);

    vm.warp(_currentTimestamp + PERIOD_LENGTH);

    assertEq(twabLibMock.getBalanceAt(_currentTimestamp), _amount); // now is safe!
  }

  function testIncreaseDelegateBalanceSameBlock() public {
    uint96 _amount = 1000e18;
    uint96 _totalAmount = _amount * 2;

    uint32 _currentTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    vm.warp(_currentTimestamp);

    // Increase delegateBalance twice
    twabLibMock.increaseBalances(0, _amount);

    (
      ObservationLib.Observation memory _observation,
      bool _isNew,
      bool _isRecorded,
      TwabLib.AccountDetails memory accountDetails
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _totalAmount);
    assertEq(accountDetails.nextObservationIndex, 1, "next observation index");
    assertEq(accountDetails.cardinality, 1, "cardinality");
    assertEq(_observation.cumulativeBalance, 0);
    assertTrue(_isRecorded);
    assertEq(_observation.timestamp, _currentTimestamp - PERIOD_OFFSET);
    assertFalse(_isNew);

    vm.warp(_currentTimestamp + PERIOD_LENGTH);
    assertEq(twabLibMock.getBalanceAt(_currentTimestamp), _totalAmount);
  }

  function testIncreaseDelegateBalanceMultipleRecords() public {
    uint96 _amount = 1000e18;
    uint96 _totalAmount = _amount * 2;

    uint32 _initialTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(_initialTimestamp);
    (
      ObservationLib.Observation memory _observation1,
      bool _isNew,
      bool _isRecorded,
      TwabLib.AccountDetails memory accountDetails
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation1.cumulativeBalance, 0);
    assertEq(_observation1.timestamp, _initialTimestamp - PERIOD_OFFSET);
    assertTrue(_isNew);

    vm.warp(_initialTimestamp + PERIOD_LENGTH);
    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), _amount, "increased amount");

    vm.warp(_secondTimestamp);

    ObservationLib.Observation memory _observation2;
    (_observation2, _isNew, _isRecorded, accountDetails) = twabLibMock.increaseBalances(0, _amount);

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
    assertEq(_observation2.timestamp, _secondTimestamp - PERIOD_OFFSET);
    assertTrue(_isNew);

    vm.warp(_secondTimestamp + PERIOD_LENGTH);
    assertEq(twabLibMock.getBalanceAt(_secondTimestamp), _totalAmount);
  }

  function testFlashIncreaseDecrease() public {
    vm.warp(PERIOD_OFFSET);
    twabLibMock.flashBalance(1000e18, 1000e18);
    twabLibMock.flashBalance(1000e18, 1000e18);
    TwabLib.AccountDetails memory details = twabLibMock.getAccountDetails();
    assertEq(details.balance, 0);
    assertEq(details.delegateBalance, 0);
    assertEq(details.cardinality, 1);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(twabLibMock.getTwabBetween(PERIOD_OFFSET, PERIOD_OFFSET + PERIOD_LENGTH), 0);
  }

  /* ============ decreaseBalances ============ */

  function testDecreaseBalanceHappyPath() public {
    uint96 _amount = 1000e18;

    (ObservationLib.Observation memory _observation, bool _isNew, bool _isRecorded, ) = twabLibMock
      .increaseBalances(_amount, 0);

    TwabLib.AccountDetails memory accountDetails;

    (_observation, _isNew, _isRecorded, accountDetails) = twabLibMock.decreaseBalances(
      _amount,
      0,
      "Revert message"
    );

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.nextObservationIndex, 0);
    assertEq(accountDetails.cardinality, 0);
  }

  function testDecreaseDelegateBalanceHappyPath() public {
    uint96 _amount = 1000e18;

    uint32 _initialTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(_initialTimestamp);
    (
      ObservationLib.Observation memory _observation,
      bool _isNew,
      bool _isRecorded,
      TwabLib.AccountDetails memory accountDetails
    ) = twabLibMock.increaseBalances(0, _amount);

    // assertEq(accountDetails.balance, 0);
    // assertEq(accountDetails.delegateBalance, _amount);
    // assertEq(accountDetails.nextObservationIndex, 1);
    // assertEq(accountDetails.cardinality, 1);
    // assertEq(_observation.cumulativeBalance, 0);
    // assertEq(_observation.timestamp, _initialTimestamp);
    // assertTrue(_isNew);

    vm.warp(_secondTimestamp);
    (_observation, _isNew, _isRecorded, accountDetails) = twabLibMock.decreaseBalances(
      0,
      _amount,
      "Revert message"
    );

    assertEq(accountDetails.balance, 0, "balance is zero");
    assertEq(accountDetails.delegateBalance, 0, "delegate balance is zero");
    assertEq(accountDetails.nextObservationIndex, 2, "observations exist");
    assertEq(accountDetails.cardinality, 2, "num obs correct");
    assertEq(
      _observation.cumulativeBalance,
      _computeCumulativeBalance(0, _amount, DRAW_LENGTH),
      "cumulative balance remains the same"
    );
    assertEq(
      _observation.timestamp,
      _secondTimestamp - PERIOD_OFFSET,
      "observation timestamp is correct"
    );
    assertTrue(_isNew, "was a new observation");

    assertEq(
      twabLibMock.getBalanceAt(_initialTimestamp),
      _amount,
      "balance at initial timestamp is correct"
    );

    vm.warp(_secondTimestamp + PERIOD_LENGTH);

    assertEq(twabLibMock.getBalanceAt(_secondTimestamp), 0, "balance is now updated");
  }

  function testDecreaseDelegateBalanceRevert() public {
    uint96 _amount = 1000e18;

    uint32 _initialTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(_initialTimestamp);
    (
      ObservationLib.Observation memory _observation,
      bool _isNew,
      bool _isRecorded,
      TwabLib.AccountDetails memory accountDetails
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation.cumulativeBalance, 0);
    assertEq(_observation.timestamp, _initialTimestamp - PERIOD_OFFSET);
    assertTrue(_isNew);

    vm.warp(_secondTimestamp);

    // Decrease more than current balance available
    vm.expectRevert(
      abi.encodeWithSelector(BalanceLTAmount.selector, 0, _amount + 1, "Revert message")
    );
    (_observation, _isNew, _isRecorded, accountDetails) = twabLibMock.decreaseBalances(
      _amount + 1,
      0,
      "Revert message"
    );

    // Decrease more than current delegateBalance available
    vm.expectRevert(
      abi.encodeWithSelector(
        DelegateBalanceLTAmount.selector,
        _amount,
        _amount + 1,
        "Revert message"
      )
    );
    (_observation, _isNew, _isRecorded, accountDetails) = twabLibMock.decreaseBalances(
      0,
      _amount + 1,
      "Revert message"
    );
  }

  function testDecreaseDelegateBalanceMultipleRecords() public {
    uint96 _amount = 1000e18;
    uint96 _halfAmount = _amount / 2;

    uint32 _initialTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    uint32 _thirdTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 3);

    vm.warp(_initialTimestamp);
    (
      ObservationLib.Observation memory _observation,
      bool _isNew,
      bool _isRecorded,
      TwabLib.AccountDetails memory accountDetails
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(_observation.cumulativeBalance, 0);
    assertEq(_observation.timestamp, _initialTimestamp - PERIOD_OFFSET);
    assertTrue(_isNew);

    vm.warp(_secondTimestamp);
    ObservationLib.Observation memory _observation2;
    (_observation2, _isNew, _isRecorded, accountDetails) = twabLibMock.decreaseBalances(
      0,
      _halfAmount,
      "Revert message"
    );

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _halfAmount);
    assertEq(accountDetails.nextObservationIndex, 2);
    assertEq(accountDetails.cardinality, 2);
    assertEq(_observation2.cumulativeBalance, _computeCumulativeBalance(0, _amount, DRAW_LENGTH));
    assertEq(_observation2.timestamp, _secondTimestamp - PERIOD_OFFSET);
    assertTrue(_isNew);

    vm.warp(_thirdTimestamp);
    (_observation, _isNew, _isRecorded, accountDetails) = twabLibMock.decreaseBalances(
      0,
      _halfAmount,
      "Revert message"
    );

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.nextObservationIndex, 3);
    assertEq(accountDetails.cardinality, 3);
    assertEq(
      _observation.cumulativeBalance,
      _computeCumulativeBalance(_observation2.cumulativeBalance, _halfAmount, DRAW_LENGTH)
    );
    assertEq(_observation.timestamp, _thirdTimestamp - PERIOD_OFFSET);
    assertTrue(_isNew);
  }

  /* ============ oldestObservation, newestObservation ============ */

  function testOldestAndNewestTwab() public {
    uint96 _amount = 1000e18;

    uint32 _initialTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    uint32 _secondTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    uint32 _thirdTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 3);

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
    assertEq(_oldestObservation.timestamp, _initialTimestamp - PERIOD_OFFSET);
    assertEq(_newestIndex, 2);
    assertEq(
      _newestObservation.cumulativeBalance,
      _computeCumulativeBalance(
        _secondNewestObservation.cumulativeBalance,
        _amount * 2,
        _newestObservation.timestamp - _secondNewestObservation.timestamp
      )
    );
    assertEq(_newestObservation.timestamp, _thirdTimestamp - PERIOD_OFFSET);
  }

  /* ============ getTwabBetween ============ */

  function averageDelegateBalanceBetweenSingleSetup()
    public
    returns (uint32 initialTimestamp, uint32 currentTimestamp, uint96 amount)
  {
    amount = 1000e18;
    initialTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    currentTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(initialTimestamp);
    twabLibMock.increaseBalances(0, amount);
  }

  function testGetTwabBetween_InvalidTimeRange() public {
    vm.warp(PERIOD_OFFSET);
    vm.expectRevert(abi.encodeWithSelector(InvalidTimeRange.selector, 1000, 100));
    twabLibMock.getTwabBetween(1000, 100);
  }

  function testGetTwabBetween_startAfterTimerange() public {
    vm.warp(2 * uint256(type(uint32).max));
    uint256 startTime = PERIOD_OFFSET + uint256(type(uint32).max) + 1;
    assertEq(twabLibMock.getTwabBetween(startTime, startTime + PERIOD_LENGTH), 0);
  }

  function testGetTwabBetween_endAfterTimerange() public {
    vm.warp(2 * uint256(type(uint32).max));
    uint256 startTime = PERIOD_OFFSET + uint256(type(uint32).max);
    assertEq(twabLibMock.getTwabBetween(startTime, startTime + PERIOD_LENGTH), 0);
  }

  function testGetTwabBetween_start_and_end_same_time() public {
    vm.warp(PERIOD_OFFSET);
    twabLibMock.increaseBalances(0, 1000e18);
    assertEq(twabLibMock.getTwabBetween(PERIOD_OFFSET, PERIOD_OFFSET), 1000e18);
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
    (uint32 secondPeriodTimestamp, , uint96 amount) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(secondPeriodTimestamp + PERIOD_LENGTH);
    uint256 _balance = twabLibMock.getTwabBetween(
      secondPeriodTimestamp - 50,
      secondPeriodTimestamp + 50
    );

    // half = zero, other half = amount
    assertEq(_balance, amount / 2);
  }

  function testGetTwabBetweenSingleCentered() public {
    (
      uint32 secondPeriodTimestamp,
      uint32 thirdPeriodTimestamp,

    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(thirdPeriodTimestamp);
    uint256 _balance = twabLibMock.getTwabBetween(
      secondPeriodTimestamp - 50,
      secondPeriodTimestamp + 50
    );

    assertEq(_balance, 500e18);
  }

  function testGetTwabBetweenSingleAfter() public {
    (
      uint32 secondPeriodStartTime,
      uint32 thirdPeriodStartTime,

    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(thirdPeriodStartTime);
    uint256 _balance = twabLibMock.getTwabBetween(
      secondPeriodStartTime + 50,
      secondPeriodStartTime + 51
    );

    assertEq(_balance, 1000e18);
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
    _initialTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    _secondTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);
    _currentTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 3);

    vm.warp(_initialTimestamp);
    twabLibMock.increaseBalances(0, _amount);

    vm.warp(_secondTimestamp);
    twabLibMock.decreaseBalances(0, _secondAmount, "insufficient-balance");
  }

  function testGetTwabBetween_empty() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH * 2);
    assertEq(twabLibMock.getTwabBetween(time, time + 50), 0);
  }

  function testGetTwabBetween_one_before() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(time);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH * 2);
    assertEq(twabLibMock.getTwabBetween(time - 100, time - 50), 0);
  }

  function testGetTwabBetween_one_onAndAfter() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(time);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH * 2);
    assertEq(twabLibMock.getTwabBetween(time, time + 50), 1000e18);
  }

  function testGetTwabBetween_one_afterAndAfter() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(time);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH * 2);
    assertEq(twabLibMock.getTwabBetween(time + 50, time + 100), 1000e18);
  }

  function testGetTwabBetween_two_before() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(time);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH * 2);
    assertEq(twabLibMock.getTwabBetween(time - 100, time - 50), 0);
  }

  function testGetTwabBetween_two_onAndBeforeSecond() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(time);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH * 2);
    assertEq(twabLibMock.getTwabBetween(time, time + PERIOD_LENGTH - 1), 1000e18);
  }

  function testGetTwabBetween_two_onAndOn() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(time);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH * 2);
    assertEq(twabLibMock.getTwabBetween(time, time + PERIOD_LENGTH), 1000e18);
  }

  function testGetTwabBetween_two_onAndAfter() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(time);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH * 2);
    assertEq(twabLibMock.getTwabBetween(time, time + PERIOD_LENGTH * 2), 1500e18);
  }

  function testGetTwabBetween_two_beforeSecondAndAfter() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(time);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH * 2);
    assertEq(
      twabLibMock.getTwabBetween(
        time + PERIOD_LENGTH / 2,
        time + PERIOD_LENGTH + PERIOD_LENGTH / 2
      ),
      1500e18
    );
  }

  function testGetTwabBetween_two_onSecondAndAfter() public {
    uint32 time = PERIOD_OFFSET + PERIOD_LENGTH;
    vm.warp(time);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1000e18);
    vm.warp(time + PERIOD_LENGTH * 2);
    assertEq(twabLibMock.getTwabBetween(time + PERIOD_LENGTH, time + PERIOD_LENGTH * 2), 2000e18);
  }

  function testGetBalanceAt_empty_beforeOffset() public {
    assertEq(twabLibMock.getBalanceAt(0), 0);
  }

  function testGetBalanceAt_empty_atOffset() public {
    assertEq(twabLibMock.getBalanceAt(PERIOD_OFFSET), 0);
  }

  function testGetBalanceAt_empty_afterOffset() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(twabLibMock.getBalanceAt(PERIOD_OFFSET + 2), 0);
  }

  function testGetBalanceAt_one_before() public {
    vm.warp(PERIOD_OFFSET);
    twabLibMock.increaseBalances(0, 1e18);
    assertEq(twabLibMock.getBalanceAt(0), 0);
  }

  function testGetBalanceAt_one_at() public {
    vm.warp(PERIOD_OFFSET);
    twabLibMock.increaseBalances(0, 1e18);
    assertEq(twabLibMock.getBalanceAt(PERIOD_OFFSET), 1e18);
  }

  function testGetBalanceAt_two_before() public {
    vm.warp(PERIOD_OFFSET);
    twabLibMock.increaseBalances(0, 1e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1e18);
    assertEq(twabLibMock.getBalanceAt(0), 0);
  }

  function testGetBalanceAt_two_atFirst() public {
    vm.warp(PERIOD_OFFSET);
    twabLibMock.increaseBalances(0, 1e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1e18);
    assertEq(twabLibMock.getBalanceAt(PERIOD_OFFSET), 1e18);
  }

  function testGetBalanceAt_two_between() public {
    vm.warp(PERIOD_OFFSET);
    twabLibMock.increaseBalances(0, 1e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1e18);
    assertEq(twabLibMock.getBalanceAt(PERIOD_OFFSET + PERIOD_LENGTH / 2), 1e18);
  }

  function testGetBalanceAt_two_atSecond() public {
    vm.warp(PERIOD_OFFSET);
    twabLibMock.increaseBalances(0, 1e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    twabLibMock.increaseBalances(0, 1e18);
    assertEq(twabLibMock.getBalanceAt(PERIOD_OFFSET + PERIOD_LENGTH), 2e18);
  }

  function testGetBalanceAt_endOfTimerange() public {
    twabLibMock.increaseBalances(0, 1e18);
    vm.warp(type(uint48).max);
    assertEq(twabLibMock.getBalanceAt(twabLibMock.lastObservationAt()), 1e18);
  }

  function testGetBalanceAt_outOfTimerange() public {
    twabLibMock.increaseBalances(0, 1e18);
    vm.warp(type(uint48).max);
    assertEq(twabLibMock.getBalanceAt(PERIOD_OFFSET + uint256(type(uint32).max) + 1), 0);
  }

  function testGetBalanceAt_InsufficientHistory() public {
    fillObservationsBuffer();
    vm.expectRevert(abi.encodeWithSelector(InsufficientHistory.selector, 0, PERIOD_LENGTH));
    twabLibMock.getBalanceAt(PERIOD_OFFSET);
  }

  /* ============ getBalanceAt ============ */

  function getBalanceAtSetup() public returns (uint32 _initialTimestamp, uint32 _currentTimestamp) {
    _initialTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH);
    _currentTimestamp = PERIOD_OFFSET + uint32(DRAW_LENGTH * 2);

    vm.warp(_initialTimestamp);
    twabLibMock.increaseBalances(0, 1000e18);
  }

  function testCurrentOverwritePeriodStartedAt_atStart() public {
    assertEq(
      twabLibMock.currentOverwritePeriodStartedAt(PERIOD_LENGTH, PERIOD_OFFSET),
      PERIOD_OFFSET
    );
  }

  function testCurrentOverwritePeriodStartedAt_halfwayThroughFirst() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH / 2);
    assertEq(
      twabLibMock.currentOverwritePeriodStartedAt(PERIOD_LENGTH, PERIOD_OFFSET),
      PERIOD_OFFSET
    );
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

  function testGetBalanceAt_withinCurrentPeriodInvalid() public {
    // Half way through a period.
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));

    vm.expectRevert(
      abi.encodeWithSelector(TimestampNotFinalized.selector, PERIOD_OFFSET + 10, PERIOD_OFFSET)
    );
    twabLibMock.getBalanceAt(PERIOD_OFFSET + 10);
  }

  function testGetTwab_MaxBalance() public {
    uint96 amount = type(uint96).max;
    vm.warp(PERIOD_OFFSET);
    twabLibMock.increaseBalances(amount, amount);
    vm.warp(PERIOD_OFFSET + VERY_LARGE_DRAW_LENGTH);

    // Get balance for first draw
    uint256 _balance = twabLibMock.getTwabBetween(PERIOD_OFFSET, PERIOD_OFFSET + DRAW_LENGTH);
    assertEq(_balance, amount);

    // Get balance for first large draw
    _balance = twabLibMock.getTwabBetween(PERIOD_OFFSET, PERIOD_OFFSET + LARGE_DRAW_LENGTH);
    assertEq(_balance, amount);

    vm.warp(PERIOD_OFFSET + VERY_LARGE_DRAW_LENGTH + PERIOD_LENGTH);

    // Get balance for very large draw
    // Resulting temporary Observation for the end of the time range is as close to the limits of the cumulativeBalance portion of the Observation data structure as we can get.
    _balance = twabLibMock.getTwabBetween(PERIOD_OFFSET, PERIOD_OFFSET + VERY_LARGE_DRAW_LENGTH);
    assertEq(_balance, amount);
  }

  /* ============ Cardinality ============ */
  function testIncreaseCardinality() public {
    uint96 _amount = 1000e18;

    TwabLib.Account memory account = twabLibMock.getAccount();
    assertEq(account.details.cardinality, 0);

    vm.warp(PERIOD_OFFSET + 1 seconds);
    (, bool isNew, bool isRecorded, TwabLib.AccountDetails memory accountDetails) = twabLibMock
      .increaseBalances(0, _amount);

    // First observation creates new record
    assertTrue(isNew);
    assertTrue(isRecorded);
    assertEq(accountDetails.nextObservationIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);

    // Second observation overwrites previous record
    vm.warp(PERIOD_OFFSET + (DRAW_LENGTH / 2));
    (, isNew, isRecorded, accountDetails) = twabLibMock.increaseBalances(0, _amount);
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

  function testGetPreviousOrAtObservation_single_before() public {
    uint32 t0 = PERIOD_OFFSET;
    twabLibMock.increaseBalances(0, 1e18);
    assertEq(twabLibMock.getPreviousOrAtObservation(t0 - 1).timestamp, 0);
  }

  function testGetPreviousOrAtObservation_single_at() public {
    uint32 t0 = PERIOD_OFFSET;
    twabLibMock.increaseBalances(0, 1e18);
    ObservationLib.Observation memory obs = twabLibMock.getPreviousOrAtObservation(t0);
    assertEq(obs.timestamp, 0);
  }

  function testGetPreviousOrAtObservation_single_after() public {
    uint32 t0 = PERIOD_OFFSET;
    twabLibMock.increaseBalances(0, 1e18);
    ObservationLib.Observation memory obs = twabLibMock.getPreviousOrAtObservation(t0 + 1);
    assertEq(obs.timestamp, 0);
  }

  function testGetPreviousOrAtObservation_after_lastTime() public {
    twabLibMock.increaseBalances(0, 1e18);
    vm.warp(PERIOD_OFFSET + uint256(type(uint32).max) + 1);
    ObservationLib.Observation memory obs = twabLibMock.getPreviousOrAtObservation(block.timestamp);
    assertEq(obs.balance, 0);
    assertEq(obs.cumulativeBalance, 0);
    assertEq(obs.timestamp, type(uint32).max);
  }

  function testGetPreviousOrAtObservation_complex() public {
    uint32 t0 = PERIOD_OFFSET;
    uint32 t1 = PERIOD_OFFSET + PERIOD_LENGTH;
    uint32 t2 = PERIOD_OFFSET + (PERIOD_LENGTH * 2);
    uint32 t3 = PERIOD_OFFSET + (PERIOD_LENGTH * 3);
    ObservationLib.Observation memory prevOrAtObservation;

    vm.warp(t0);
    twabLibMock.increaseBalances(1, 1);

    // Get observation at timestamp before first observation
    assertEq(twabLibMock.getPreviousOrAtObservation(t0 - 1 seconds).timestamp, 0);

    // Get observation at first timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t0);
    assertEq(prevOrAtObservation.timestamp, 0);

    // Get observation after first timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t0 + 1 seconds);
    assertEq(prevOrAtObservation.timestamp, 0);

    vm.warp(t1);
    twabLibMock.increaseBalances(1, 1);
    vm.warp(t2);
    twabLibMock.increaseBalances(1, 1);
    vm.warp(t3);
    twabLibMock.increaseBalances(1, 1);

    // Get observation at timestamp before first observation
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t0 - 1 seconds);
    assertEq(prevOrAtObservation.timestamp, 0, "before first period");

    // Get observation at first timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t0);
    assertEq(prevOrAtObservation.timestamp, 0, "start of first period");

    // Get observation between first and second timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t1 - 1 seconds);
    assertEq(prevOrAtObservation.timestamp, 0, "end of first period");

    // Get observation at second timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t1);
    assertEq(prevOrAtObservation.timestamp, PERIOD_LENGTH);

    // Get observation between second and third timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t1 + 1 seconds);
    assertEq(prevOrAtObservation.timestamp, PERIOD_LENGTH);

    // Get observation between second and third timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t2 - 1 seconds);
    assertEq(prevOrAtObservation.timestamp, PERIOD_LENGTH);

    // Get observation at third timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t2);
    assertEq(prevOrAtObservation.timestamp, PERIOD_LENGTH * 2);

    // Get observation between third and fourth timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t2 + 1 seconds);
    assertEq(prevOrAtObservation.timestamp, PERIOD_LENGTH * 2);

    // Get observation between third and fourth timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t3 - 1 seconds);
    assertEq(prevOrAtObservation.timestamp, PERIOD_LENGTH * 2);

    // Get observation at fourth timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t3);
    assertEq(prevOrAtObservation.timestamp, PERIOD_LENGTH * 3);

    // Get observation after fourth timestamp
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t3 + 1 seconds);
    assertEq(prevOrAtObservation.timestamp, PERIOD_LENGTH * 3);
  }

  function testGetPreviousOrAtObservation_EmptyBuffer() public {
    ObservationLib.Observation memory prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      PERIOD_OFFSET
    );

    assertEq(prevOrAtObservation.timestamp, 0);
  }

  function testGetPreviousOrAtObservation_FullBuffer() public {
    fillObservationsBuffer();
    ObservationLib.Observation memory prevOrAtObservation;

    // First observation is overwritten, reverts
    vm.expectRevert(abi.encodeWithSelector(InsufficientHistory.selector, 0, PERIOD_LENGTH));
    twabLibMock.getPreviousOrAtObservation(PERIOD_OFFSET);

    // Get before oldest observation
    (, ObservationLib.Observation memory oldestObservation) = twabLibMock.getOldestObservation();

    // Get at oldest observation
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      oldestObservation.timestamp + PERIOD_OFFSET
    );
    assertEq(prevOrAtObservation.timestamp, oldestObservation.timestamp);
    assertGe(prevOrAtObservation.timestamp, 0);

    // Get after oldest observation
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      oldestObservation.timestamp + 1 seconds + PERIOD_OFFSET
    );
    assertEq(prevOrAtObservation.timestamp, oldestObservation.timestamp);
    assertGe(prevOrAtObservation.timestamp, 0);

    // Get observation somewhere in the middle.
    uint32 t = PERIOD_OFFSET + (PERIOD_LENGTH * 100);
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t);
    assertEq(prevOrAtObservation.timestamp, t - PERIOD_OFFSET);
    assertGe(prevOrAtObservation.timestamp, 0);

    // Get observation right before somewhere in the middle.
    t -= 1 seconds;
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(t);
    assertEq(prevOrAtObservation.timestamp, (PERIOD_LENGTH * 99));
    assertGe(prevOrAtObservation.timestamp, 0);

    // Get newest observation.
    (, ObservationLib.Observation memory newestObservation) = twabLibMock.getNewestObservation();
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      newestObservation.timestamp + PERIOD_OFFSET
    );
    assertEq(prevOrAtObservation.timestamp, newestObservation.timestamp);
    assertGe(prevOrAtObservation.timestamp, 0);

    // Get before newest observation.
    prevOrAtObservation = twabLibMock.getPreviousOrAtObservation(
      newestObservation.timestamp - 1 seconds + PERIOD_OFFSET
    );
    assertEq(prevOrAtObservation.timestamp, newestObservation.timestamp - PERIOD_LENGTH);
    assertGe(prevOrAtObservation.timestamp, 0);
  }

  // ================== getNextOrNewestObservation ==================

  // ================== getTimestampPeriod ==================

  function testGetTimestampPeriod_before() public {
    assertEq(twabLibMock.getTimestampPeriod(PERIOD_OFFSET - 1), 0);
  }

  function testGetTimestampPeriod_first() public {
    assertEq(twabLibMock.getTimestampPeriod(PERIOD_OFFSET), 0);
    assertEq(twabLibMock.getTimestampPeriod(PERIOD_OFFSET + 1 seconds), 0);
  }

  function testGetTimestampPeriod_second() public {
    assertEq(twabLibMock.getTimestampPeriod(PERIOD_OFFSET + PERIOD_LENGTH), 1);
  }

  function testGetPeriodStartTime_before() public {
    assertEq(twabLibMock.getPeriodStartTime(0), PERIOD_OFFSET);
  }

  function testGetPeriodStartTime_normal() public {
    assertEq(twabLibMock.getPeriodStartTime(1), PERIOD_OFFSET + PERIOD_LENGTH);
  }

  function testGetPeriodStartTime_two() public {
    assertEq(twabLibMock.getPeriodStartTime(2), PERIOD_OFFSET + PERIOD_LENGTH * 2);
  }

  function testGetPeriodEndTime_zero() public {
    assertEq(twabLibMock.getPeriodEndTime(0), PERIOD_OFFSET + PERIOD_LENGTH);
  }

  // ================== hasFinalized ==================

  function testHasFinalized_withinOverwritePeriod() public {
    vm.warp(PERIOD_OFFSET);
    assertFalse(twabLibMock.hasFinalized(PERIOD_OFFSET + 1));
  }

  function testHasFinalized_endOfOverwritePeriod() public {
    vm.warp(PERIOD_OFFSET);
    assertFalse(twabLibMock.hasFinalized(PERIOD_OFFSET + PERIOD_LENGTH - 1));
  }

  function testHasFinalized_afterOverwritePeriod() public {
    vm.warp(PERIOD_OFFSET);
    assertFalse(twabLibMock.hasFinalized(PERIOD_OFFSET + PERIOD_LENGTH));
  }

  function testHasFinalized_beforeOverwritePeriod() public {
    vm.warp(PERIOD_OFFSET);
    assertTrue(twabLibMock.hasFinalized(PERIOD_OFFSET - 1));
  }

  function testHasFinalized_startOfOverwritePeriod() public {
    vm.warp(PERIOD_OFFSET);
    assertTrue(twabLibMock.hasFinalized(PERIOD_OFFSET));
  }

  // ================== helpers  ==================

  /**
   * @dev Fills the observations buffer with MAX_CARDINALITY + 1 observations. Each observation is 1 period length apart and increases balances by 1.
   */
  function fillObservationsBuffer() internal {
    uint32 t = PERIOD_OFFSET;
    for (uint256 i = 0; i <= MAX_CARDINALITY; i++) {
      vm.warp(t);
      twabLibMock.increaseBalances(1, 1);
      t += PERIOD_LENGTH;
    }
  }
}
