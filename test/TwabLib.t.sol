// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { BaseSetup } from "./utils/BaseSetup.sol";
import { TwabLib, Account } from "../src/libraries/TwabLib.sol";
import { ObservationLib } from "../src/libraries/ObservationLib.sol";

contract TwabLibTest is BaseSetup {
  uint16 public MAX_CARDINALITY = 365;
  Account public account;

  function _computeTwab(
    uint256 _currentTwabAmount,
    uint256 _currentDelegateBalance,
    uint256 _currentTwabTimestamp
  ) internal view returns (uint256) {
    return
      _currentTwabAmount + (_currentDelegateBalance * (block.timestamp - _currentTwabTimestamp));
  }

  function setUp() public override {
    super.setUp();
  }

  /* ============ increaseBalances ============ */

  function testIncreaseBalanceHappyPath() public {
    uint112 _amount = 100;
    uint32 _initialTimestamp = uint32(100);
    uint32 _currentTimestamp = uint32(200);
    vm.warp(_currentTimestamp);

    (ObservationLib.Observation memory _twab, bool _isNewTwab) = TwabLib.increaseBalances(
      account,
      _amount,
      0
    );

    assertEq(account.balance, _amount);
    assertEq(account.delegateBalance, 0);
    assertEq(account.nextTwabIndex, 0);
    assertEq(account.cardinality, 0);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 0);
    assertFalse(_isNewTwab);

    // No TWAB has been recorded so balance is 0
    assertEq(TwabLib.getBalanceAt(account, _initialTimestamp), 0);
    assertEq(TwabLib.getBalanceAt(account, _currentTimestamp), 0);
  }

  function testIncreaseDelegateBalanceHappyPath() public {
    uint112 _amount = 100;
    uint32 _initialTimestamp = uint32(100);
    uint32 _currentTimestamp = uint32(200);
    vm.warp(_currentTimestamp);

    (ObservationLib.Observation memory _twab, bool _isNewTwab) = TwabLib.increaseBalances(
      account,
      0,
      _amount
    );

    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, _amount);
    assertEq(account.nextTwabIndex, 1);
    assertEq(account.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 200);
    assertTrue(_isNewTwab);

    assertEq(TwabLib.getBalanceAt(account, _initialTimestamp), 0);
    assertEq(TwabLib.getBalanceAt(account, _currentTimestamp), _amount);
  }

  function testIncreaseDelegateBalanceSameBlock() public {
    uint112 _amount = 100;
    uint112 _totalAmount = 200;

    uint32 _currentTimestamp = uint32(100);
    vm.warp(_currentTimestamp);

    // Increase delegateBalance twice
    TwabLib.increaseBalances(account, 0, _amount);

    (ObservationLib.Observation memory _twab, bool _isNewTwab) = TwabLib.increaseBalances(
      account,
      0,
      _amount
    );

    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, _totalAmount);
    assertEq(account.nextTwabIndex, 1);
    assertEq(account.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 100);
    assertFalse(_isNewTwab);

    assertEq(TwabLib.getBalanceAt(account, _currentTimestamp), _totalAmount);
  }

  function testIncreaseDelegateBalanceMultipleRecords() public {
    uint112 _amount = 100;
    uint112 _totalAmount = 200;

    uint32 _initialTimestamp = uint32(100);
    uint32 _secondTimestamp = uint32(200);

    vm.warp(_initialTimestamp);
    (ObservationLib.Observation memory _twab, bool _isNewTwab) = TwabLib.increaseBalances(
      account,
      0,
      _amount
    );

    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, _amount);
    assertEq(account.nextTwabIndex, 1);
    assertEq(account.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 100);
    assertTrue(_isNewTwab);

    assertEq(TwabLib.getBalanceAt(account, _initialTimestamp), _amount);

    vm.warp(_secondTimestamp);

    (_twab, _isNewTwab) = TwabLib.increaseBalances(account, 0, _amount);

    // Check balance
    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, _totalAmount);
    assertEq(account.nextTwabIndex, 2);
    assertEq(account.cardinality, 2);
    assertEq(_twab.amount, _computeTwab(0, 100, 100));
    assertEq(_twab.timestamp, 200);
    assertTrue(_isNewTwab);

    assertEq(TwabLib.getBalanceAt(account, _secondTimestamp), _totalAmount);
  }

  /* ============ decreaseBalances ============ */

  function testDecreaseBalanceHappyPath() public {
    uint112 _amount = 100;

    TwabLib.increaseBalances(account, _amount, 0);

    TwabLib.decreaseBalances(account, _amount, 0, "Revert message");

    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, 0);
    assertEq(account.nextTwabIndex, 0);
    assertEq(account.cardinality, 0);
  }

  function testDecreaseDelegateBalanceHappyPath() public {
    uint112 _amount = 100;

    uint32 _initialTimestamp = uint32(100);
    uint32 _secondTimestamp = uint32(200);

    vm.warp(_initialTimestamp);
    (ObservationLib.Observation memory _twab, bool _isNewTwab) = TwabLib.increaseBalances(
      account,
      0,
      _amount
    );

    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, _amount);
    assertEq(account.nextTwabIndex, 1);
    assertEq(account.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 100);
    assertTrue(_isNewTwab);

    vm.warp(_secondTimestamp);
    (_twab, _isNewTwab) = TwabLib.decreaseBalances(account, 0, _amount, "Revert message");

    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, 0);
    assertEq(account.nextTwabIndex, 2);
    assertEq(account.cardinality, 2);
    assertEq(_twab.amount, _computeTwab(0, 100, 100));
    assertEq(_twab.timestamp, 200);
    assertTrue(_isNewTwab);

    assertEq(TwabLib.getBalanceAt(account, _initialTimestamp), _amount);
    assertEq(TwabLib.getBalanceAt(account, _secondTimestamp), 0);
  }

  function testDecreaseDelegateBalanceMultipleRecords() public {
    uint112 _amount = 100;
    uint112 _halfAmount = 50;

    uint32 _initialTimestamp = uint32(100);
    uint32 _secondTimestamp = uint32(200);
    uint32 _thirdTimestamp = uint32(300);

    vm.warp(_initialTimestamp);
    (ObservationLib.Observation memory _twab, bool _isNewTwab) = TwabLib.increaseBalances(
      account,
      0,
      _amount
    );

    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, _amount);
    assertEq(account.nextTwabIndex, 1);
    assertEq(account.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, _initialTimestamp);
    assertTrue(_isNewTwab);

    vm.warp(_secondTimestamp);
    (_twab, _isNewTwab) = TwabLib.decreaseBalances(account, 0, _halfAmount, "Revert message");

    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, _halfAmount);
    assertEq(account.nextTwabIndex, 2);
    assertEq(account.cardinality, 2);
    assertEq(_twab.amount, _computeTwab(0, 100, 100));
    assertEq(_twab.timestamp, _secondTimestamp);
    assertTrue(_isNewTwab);

    vm.warp(_thirdTimestamp);
    (_twab, _isNewTwab) = TwabLib.decreaseBalances(account, 0, _halfAmount, "Revert message");

    assertEq(account.balance, 0);
    assertEq(account.delegateBalance, 0);
    assertEq(account.nextTwabIndex, 2);
    assertEq(account.cardinality, 2);
    assertEq(_twab.amount, _computeTwab(10000, 50, 200));
    assertEq(_twab.timestamp, _thirdTimestamp);
    assertTrue(_isNewTwab);
  }

  /* ============ oldestTwab, newestTwab ============ */

  function testOldestAndNewestTwab() public {
    uint112 _amount = 100;

    uint32 _initialTimestamp = uint32(100);
    uint32 _secondTimestamp = uint32(200);
    uint32 _thirdTimestamp = uint32(300);

    (uint16 _oldestIndex, ObservationLib.Observation memory _oldestTwab) = TwabLib.oldestTwab(
      account
    );
    (uint16 _newestIndex, ObservationLib.Observation memory _newestTwab) = TwabLib.newestTwab(
      account
    );

    assertEq(_oldestIndex, 0);
    assertEq(_oldestTwab.amount, 0);
    assertEq(_oldestTwab.timestamp, 0);

    // Newest TWAB is the last index on an empty TWAB array
    assertEq(_newestIndex, MAX_CARDINALITY - 1);
    assertEq(_newestTwab.amount, 0);
    assertEq(_newestTwab.timestamp, 0);

    vm.warp(_initialTimestamp);
    TwabLib.increaseBalances(account, 0, _amount);

    vm.warp(_secondTimestamp);
    TwabLib.increaseBalances(account, 0, _amount);

    vm.warp(_thirdTimestamp);
    TwabLib.decreaseBalances(account, 0, _amount, "Revert message");

    (_oldestIndex, _oldestTwab) = TwabLib.oldestTwab(account);
    (_newestIndex, _newestTwab) = TwabLib.newestTwab(account);

    assertEq(_oldestIndex, 0);
    assertEq(_oldestTwab.amount, 0);
    assertEq(_oldestTwab.timestamp, _initialTimestamp);
    assertEq(_newestIndex, 1);
    assertEq(_newestTwab.amount, _computeTwab(10000, 200, 200));
    assertEq(_newestTwab.timestamp, _thirdTimestamp);
  }

  /* ============ getAverageBalanceBetween ============ */

  function averageDelegateBalanceBetweenSingleSetup()
    public
    returns (uint32 initialTimestamp, uint32 currentTimestamp)
  {
    initialTimestamp = 1000;
    currentTimestamp = 2000;

    vm.warp(initialTimestamp);
    TwabLib.increaseBalances(account, 0, 1000);
  }

  function testgetAverageBalanceBetweenSingleBefore() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _initialTimestamp - 100,
      _initialTimestamp - 50
    );

    assertEq(_balance, 0);
  }

  function testgetAverageBalanceBetweenSingleBeforeIncluding() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _initialTimestamp - 100,
      _initialTimestamp
    );

    assertEq(_balance, 0);
  }

  function testgetAverageBalanceBetweenSingleFuture() public {
    (uint32 _initialTimestamp, ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_initialTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _initialTimestamp - 50,
      _initialTimestamp + 50
    );

    assertEq(_balance, 0);
  }

  function testgetAverageBalanceBetweenSingleCentered() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _initialTimestamp - 50,
      _initialTimestamp + 50
    );

    assertEq(_balance, 500);
  }

  function testgetAverageBalanceBetweenSingleAfter() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _initialTimestamp + 50,
      _initialTimestamp + 51
    );

    assertEq(_balance, 1000);
  }

  function averageDelegateBalanceBetweenDoubleSetup()
    public
    returns (uint32 _initialTimestamp, uint32 _secondTimestamp, uint32 _currentTimestamp)
  {
    _initialTimestamp = uint32(1000);
    _secondTimestamp = uint32(2000);
    _currentTimestamp = uint32(3000);

    vm.warp(_initialTimestamp);
    TwabLib.increaseBalances(account, 0, 1000);

    vm.warp(_secondTimestamp);
    TwabLib.decreaseBalances(account, 0, 500, "insufficient-balance");
  }

  function testAverageDelegateBalanceBetweenDoubleTwabBefore() public {
    (
      uint32 _initialTimestamp,
      ,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _initialTimestamp - 100,
      _initialTimestamp - 50
    );

    assertEq(_balance, 0);
  }

  function testAverageDelegateBalanceBetwenDoubleCenteredFirst() public {
    (
      uint32 _initialTimestamp,
      ,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _initialTimestamp - 50,
      _initialTimestamp + 50
    );

    assertEq(_balance, 500);
  }

  function testAverageDelegateBalanceBetwenDoubleOldestIsFirst() public {
    (
      uint32 _initialTimestamp,
      ,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _initialTimestamp,
      _initialTimestamp + 50
    );

    assertEq(_balance, 1000);
  }

  function testAverageDelegateBalanceBetweenDoubleBetween() public {
    (
      uint32 _initialTimestamp,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _initialTimestamp + 50,
      _secondTimestamp - 50
    );

    assertEq(_balance, 1000);
  }

  function testAverageDelegateBalanceBettwenDoubleCenteredSecond() public {
    (
      ,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _secondTimestamp - 50,
      _secondTimestamp + 50
    );

    assertEq(_balance, 750);
  }

  function testAverageDelegateBalanceBetweenDoubleAfter() public {
    (
      ,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getAverageBalanceBetween(
      account,
      _secondTimestamp + 50,
      _secondTimestamp + 51
    );

    assertEq(_balance, 500);
  }

  /* ============ getBalanceAt ============ */

  function getBalanceAtSetup() public returns (uint32 _initialTimestamp, uint32 _currentTimestamp) {
    _initialTimestamp = 1000;
    _currentTimestamp = 2000;

    vm.warp(_initialTimestamp);
    TwabLib.increaseBalances(account, 0, 1000);
  }

  function testDelegateBalanceAtSingleTwabBefore() public {
    (, uint32 _currentTimestamp) = getBalanceAtSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getBalanceAt(account, 500);

    assertEq(_balance, 0);
  }

  // TODO: same test than above?
  function testDelegateBalanceAtSingleTwabAtOrAfter() public {
    (, uint32 _currentTimestamp) = getBalanceAtSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = TwabLib.getBalanceAt(account, 500);

    assertEq(_balance, 0);
  }

  function testProblematicQuery() public {
    uint112 _amount = 100;

    vm.warp(1630713395);
    TwabLib.increaseBalances(account, 0, _amount);

    vm.warp(1630713396);
    TwabLib.decreaseBalances(account, 0, _amount, "Revert message");

    vm.warp(1675702148);
    uint256 _balance = TwabLib.getBalanceAt(account, 1630713395);
    assertEq(_balance, 100);
  }

  /* ============ Cardinality ============ */
  Account public mockedAccount;

  function testIncreaseCardinality() public {
    mockedAccount.nextTwabIndex = 2;
    mockedAccount.cardinality = 10;

    TwabLib.increaseBalances(mockedAccount, 0, 100);

    assertEq(mockedAccount.nextTwabIndex, 3);
    assertEq(mockedAccount.cardinality, 11);
    assertEq(mockedAccount.balance, 0);
    assertEq(mockedAccount.delegateBalance, 100);
  }

  function testIncreaseCardinalityOverflow() public {
    mockedAccount.nextTwabIndex = 2;
    mockedAccount.cardinality = 2 ** 16 - 1;

    TwabLib.increaseBalances(mockedAccount, 0, 100);

    assertEq(mockedAccount.nextTwabIndex, 3);
    assertEq(mockedAccount.cardinality, 2 ** 16 - 1);
    assertEq(mockedAccount.balance, 0);
    assertEq(mockedAccount.delegateBalance, 100);
  }
}
