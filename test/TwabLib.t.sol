// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { BaseSetup } from "test/utils/BaseSetup.sol";
import { TwabLib } from "src/libraries/TwabLib.sol";
import { TwabLibMock } from "test/contracts/mocks/TwabLibMock.sol";
import { ObservationLib } from "src/libraries/ObservationLib.sol";

contract TwabLibTest is BaseSetup {
  TwabLibMock public twabLibMock;
  uint16 public MAX_CARDINALITY = 365;

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

    twabLibMock = new TwabLibMock();
  }

  /* ============ increaseBalances ============ */

  function testIncreaseBalanceHappyPath() public {
    uint112 _amount = 1000e18;
    uint32 _initialTimestamp = uint32(100);
    uint32 _currentTimestamp = uint32(200);
    vm.warp(_currentTimestamp);

    (
      TwabLib.AccountDetails memory _accountDetails,
      ObservationLib.Observation memory _twab,
      bool _isNewTwab
    ) = twabLibMock.increaseBalances(_amount, 0);

    assertEq(_accountDetails.balance, _amount);
    assertEq(_accountDetails.delegateBalance, 0);
    assertEq(_accountDetails.nextTwabIndex, 0);
    assertEq(_accountDetails.cardinality, 0);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 0);
    assertFalse(_isNewTwab);

    // No TWAB has been recorded so balance is 0
    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), 0);
    assertEq(twabLibMock.getBalanceAt(_currentTimestamp), 0);
  }

  function testIncreaseDelegateBalanceHappyPath() public {
    uint112 _amount = 1000e18;
    uint32 _initialTimestamp = uint32(100);
    uint32 _currentTimestamp = uint32(200);
    vm.warp(_currentTimestamp);

    (
      TwabLib.AccountDetails memory _accountDetails,
      ObservationLib.Observation memory _twab,
      bool _isNewTwab
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, _amount);
    assertEq(_accountDetails.nextTwabIndex, 1);
    assertEq(_accountDetails.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 200);
    assertTrue(_isNewTwab);

    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), 0);
    assertEq(twabLibMock.getBalanceAt(_currentTimestamp), _amount);
  }

  function testIncreaseDelegateBalanceSameBlock() public {
    uint112 _amount = 1000e18;
    uint112 _totalAmount = _amount * 2;

    uint32 _currentTimestamp = uint32(100);
    vm.warp(_currentTimestamp);

    // Increase delegateBalance twice
    twabLibMock.increaseBalances(0, _amount);

    (
      TwabLib.AccountDetails memory _accountDetails,
      ObservationLib.Observation memory _twab,
      bool _isNewTwab
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, _totalAmount);
    assertEq(_accountDetails.nextTwabIndex, 1);
    assertEq(_accountDetails.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 100);
    assertFalse(_isNewTwab);

    assertEq(twabLibMock.getBalanceAt(_currentTimestamp), _totalAmount);
  }

  function testIncreaseDelegateBalanceMultipleRecords() public {
    uint112 _amount = 1000e18;
    uint112 _totalAmount = _amount * 2;

    uint32 _initialTimestamp = uint32(100);
    uint32 _secondTimestamp = uint32(200);

    vm.warp(_initialTimestamp);
    (
      TwabLib.AccountDetails memory _accountDetails,
      ObservationLib.Observation memory _twab,
      bool _isNewTwab
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, _amount);
    assertEq(_accountDetails.nextTwabIndex, 1);
    assertEq(_accountDetails.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 100);
    assertTrue(_isNewTwab);

    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), _amount);

    vm.warp(_secondTimestamp);

    (_accountDetails, _twab, _isNewTwab) = twabLibMock.increaseBalances(0, _amount);

    // Check balance
    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, _totalAmount);
    assertEq(_accountDetails.nextTwabIndex, 2);
    assertEq(_accountDetails.cardinality, 2);
    assertEq(_twab.amount, _computeTwab(0, _amount, 100));
    assertEq(_twab.timestamp, 200);
    assertTrue(_isNewTwab);

    assertEq(twabLibMock.getBalanceAt(_secondTimestamp), _totalAmount);
  }

  /* ============ decreaseBalances ============ */

  function testDecreaseBalanceHappyPath() public {
    uint112 _amount = 1000e18;

    (
      TwabLib.AccountDetails memory _accountDetails,
      ObservationLib.Observation memory _twab,
      bool _isNewTwab
    ) = twabLibMock.increaseBalances(_amount, 0);

    (_accountDetails, _twab, _isNewTwab) = twabLibMock.decreaseBalances(
      _amount,
      0,
      "Revert message"
    );

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, 0);
    assertEq(_accountDetails.nextTwabIndex, 0);
    assertEq(_accountDetails.cardinality, 0);
  }

  function testDecreaseDelegateBalanceHappyPath() public {
    uint112 _amount = 1000e18;

    uint32 _initialTimestamp = uint32(100);
    uint32 _secondTimestamp = uint32(200);

    vm.warp(_initialTimestamp);
    (
      TwabLib.AccountDetails memory _accountDetails,
      ObservationLib.Observation memory _twab,
      bool _isNewTwab
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, _amount);
    assertEq(_accountDetails.nextTwabIndex, 1);
    assertEq(_accountDetails.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 100);
    assertTrue(_isNewTwab);

    vm.warp(_secondTimestamp);
    (_accountDetails, _twab, _isNewTwab) = twabLibMock.decreaseBalances(
      0,
      _amount,
      "Revert message"
    );

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, 0);
    assertEq(_accountDetails.nextTwabIndex, 2);
    assertEq(_accountDetails.cardinality, 2);
    assertEq(_twab.amount, _computeTwab(0, _amount, 100));
    assertEq(_twab.timestamp, 200);
    assertTrue(_isNewTwab);

    assertEq(twabLibMock.getBalanceAt(_initialTimestamp), _amount);
    assertEq(twabLibMock.getBalanceAt(_secondTimestamp), 0);
  }

  function testDecreaseDelegateBalanceRevert() public {
    uint112 _amount = 1000e18;

    uint32 _initialTimestamp = uint32(100);
    uint32 _secondTimestamp = uint32(200);

    vm.warp(_initialTimestamp);
    (
      TwabLib.AccountDetails memory _accountDetails,
      ObservationLib.Observation memory _twab,
      bool _isNewTwab
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, _amount);
    assertEq(_accountDetails.nextTwabIndex, 1);
    assertEq(_accountDetails.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, 100);
    assertTrue(_isNewTwab);

    vm.warp(_secondTimestamp);

    // Decrease more than current balance available
    vm.expectRevert(bytes("Revert message"));
    (_accountDetails, _twab, _isNewTwab) = twabLibMock.decreaseBalances(
      _amount + 1,
      0,
      "Revert message"
    );

    // Decrease more than current delegateBalance available
    vm.expectRevert(bytes("Revert message"));
    (_accountDetails, _twab, _isNewTwab) = twabLibMock.decreaseBalances(
      0,
      _amount + 1,
      "Revert message"
    );
  }

  function testDecreaseDelegateBalanceMultipleRecords() public {
    uint112 _amount = 1000e18;
    uint112 _halfAmount = _amount / 2;

    uint32 _initialTimestamp = uint32(100);
    uint32 _secondTimestamp = uint32(200);
    uint32 _thirdTimestamp = uint32(300);

    vm.warp(_initialTimestamp);

    (
      TwabLib.AccountDetails memory _accountDetails,
      ObservationLib.Observation memory _twab,
      bool _isNewTwab
    ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, _amount);
    assertEq(_accountDetails.nextTwabIndex, 1);
    assertEq(_accountDetails.cardinality, 1);
    assertEq(_twab.amount, 0);
    assertEq(_twab.timestamp, _initialTimestamp);
    assertTrue(_isNewTwab);

    vm.warp(_secondTimestamp);
    (_accountDetails, _twab, _isNewTwab) = twabLibMock.decreaseBalances(
      0,
      _halfAmount,
      "Revert message"
    );

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, _halfAmount);
    assertEq(_accountDetails.nextTwabIndex, 2);
    assertEq(_accountDetails.cardinality, 2);
    assertEq(_twab.amount, _computeTwab(0, _amount, 100));
    assertEq(_twab.timestamp, _secondTimestamp);
    assertTrue(_isNewTwab);

    vm.warp(_thirdTimestamp);
    (_accountDetails, _twab, _isNewTwab) = twabLibMock.decreaseBalances(
      0,
      _halfAmount,
      "Revert message"
    );

    assertEq(_accountDetails.balance, 0);
    assertEq(_accountDetails.delegateBalance, 0);
    assertEq(_accountDetails.nextTwabIndex, 2);
    assertEq(_accountDetails.cardinality, 2);
    assertEq(_twab.amount, _computeTwab(100000e18, _halfAmount, 200));
    assertEq(_twab.timestamp, _thirdTimestamp);
    assertTrue(_isNewTwab);
  }

  /* ============ oldestTwab, newestTwab ============ */

  function testOldestAndNewestTwab() public {
    uint112 _amount = 1000e18;

    uint32 _initialTimestamp = uint32(100);
    uint32 _secondTimestamp = uint32(200);
    uint32 _thirdTimestamp = uint32(300);

    (uint16 _oldestIndex, ObservationLib.Observation memory _oldestTwab) = twabLibMock.oldestTwab();

    (uint16 _newestIndex, ObservationLib.Observation memory _newestTwab) = twabLibMock.newestTwab();

    assertEq(_oldestIndex, 0);
    assertEq(_oldestTwab.amount, 0);
    assertEq(_oldestTwab.timestamp, 0);

    // Newest TWAB is the last index on an empty TWAB array
    assertEq(_newestIndex, MAX_CARDINALITY - 1);
    assertEq(_newestTwab.amount, 0);
    assertEq(_newestTwab.timestamp, 0);

    vm.warp(_initialTimestamp);
    twabLibMock.increaseBalances(0, _amount);

    vm.warp(_secondTimestamp);
    twabLibMock.increaseBalances(0, _amount);

    vm.warp(_thirdTimestamp);
    twabLibMock.decreaseBalances(0, _amount, "Revert message");

    (_oldestIndex, _oldestTwab) = twabLibMock.oldestTwab();
    (_newestIndex, _newestTwab) = twabLibMock.newestTwab();

    assertEq(_oldestIndex, 0);
    assertEq(_oldestTwab.amount, 0);
    assertEq(_oldestTwab.timestamp, _initialTimestamp);
    assertEq(_newestIndex, 1);
    assertEq(_newestTwab.amount, _computeTwab(100000e18, _amount * 2, 200));
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
    twabLibMock.increaseBalances(0, 1000e18);
  }

  function testgetAverageBalanceBetweenSingleBefore() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
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
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
      _initialTimestamp - 100,
      _initialTimestamp
    );

    assertEq(_balance, 0);
  }

  function testgetAverageBalanceBetweenSingleFuture() public {
    (uint32 _initialTimestamp, ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_initialTimestamp);
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
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
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
      _initialTimestamp - 50,
      _initialTimestamp + 50
    );

    assertEq(_balance, 500e18);
  }

  function testgetAverageBalanceBetweenSingleAfter() public {
    (
      uint32 _initialTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenSingleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
      _initialTimestamp + 50,
      _initialTimestamp + 51
    );

    assertEq(_balance, 1000e18);
  }

  function testGetAverageBalanceBetween_LargeOverwrite() external {
    uint32 drawStart = 4 days;
    uint32 drawEnd = 5 days;
    uint112 amount = 1e18;
    uint112 largeAmount = 1000000e18;

    vm.warp(uint32(drawStart - 2 days));
    twabLibMock.increaseBalances(amount, amount);
    vm.warp(uint32(drawStart - 2 days + 12 hours));
    twabLibMock.decreaseBalances(amount, amount, "Revert");
    vm.warp(uint32(drawStart - 1 seconds));
    twabLibMock.increaseBalances(largeAmount, largeAmount);
    vm.warp(uint32(drawStart + 1 seconds));
    twabLibMock.decreaseBalances(largeAmount, largeAmount, "Revert");
    vm.warp(uint32(drawEnd + 1 days - 1 seconds));
    twabLibMock.increaseBalances(largeAmount, largeAmount);

    uint256 averageBalance = twabLibMock.getAverageBalanceBetween(drawStart, drawEnd);
    assertEq(averageBalance, 11574074074074074074);
  }

  function averageDelegateBalanceBetweenDoubleSetup()
    public
    returns (uint32 _initialTimestamp, uint32 _secondTimestamp, uint32 _currentTimestamp)
  {
    _initialTimestamp = uint32(1000);
    _secondTimestamp = uint32(2000);
    _currentTimestamp = uint32(3000);

    vm.warp(_initialTimestamp);
    twabLibMock.increaseBalances(0, 1000e18);

    vm.warp(_secondTimestamp);
    twabLibMock.decreaseBalances(0, 500e18, "insufficient-balance");
  }

  function testAverageDelegateBalanceBetweenDoubleTwabBefore() public {
    (
      uint32 _initialTimestamp,
      ,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
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
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
      _initialTimestamp - 50,
      _initialTimestamp + 50
    );

    assertEq(_balance, 500e18);
  }

  function testAverageDelegateBalanceBetwenDoubleOldestIsFirst() public {
    (
      uint32 _initialTimestamp,
      ,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
      _initialTimestamp,
      _initialTimestamp + 50
    );

    assertEq(_balance, 1000e18);
  }

  function testAverageDelegateBalanceBetweenDoubleBetween() public {
    (
      uint32 _initialTimestamp,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
      _initialTimestamp + 50,
      _secondTimestamp - 50
    );

    assertEq(_balance, 1000e18);
  }

  function testAverageDelegateBalanceBettwenDoubleCenteredSecond() public {
    (
      ,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
      _secondTimestamp - 50,
      _secondTimestamp + 50
    );

    assertEq(_balance, 750e18);
  }

  function testAverageDelegateBalanceBetweenDoubleAfter() public {
    (
      ,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
      _secondTimestamp + 50,
      _secondTimestamp + 51
    );

    assertEq(_balance, 500e18);
  }

  function testAverageDelegateBalanceTargetOldest() public {
    (
      ,
      uint32 _secondTimestamp,
      uint32 _currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    vm.warp(_currentTimestamp);
    uint256 _balance = twabLibMock.getAverageBalanceBetween(
      _secondTimestamp - 10,
      _secondTimestamp
    );

    assertEq(_balance, 1000e18);
  }

  /* ============ getBalanceAt ============ */

  function getBalanceAtSetup() public returns (uint32 _initialTimestamp, uint32 _currentTimestamp) {
    _initialTimestamp = 1000;
    _currentTimestamp = 2000;

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

  function testProblematicQuery() public {
    uint112 _amount = 1000e18;

    vm.warp(1630713395);
    twabLibMock.increaseBalances(0, _amount);

    vm.warp(1630713396);
    twabLibMock.decreaseBalances(0, _amount, "Revert message");

    vm.warp(1675702148);
    uint256 _balance = twabLibMock.getBalanceAt(1630713395);

    assertEq(_balance, _amount);
  }

  /* ============ Cardinality ============ */
  function testIncreaseCardinality() public {
    twabLibMock.setAccountDetails(
      TwabLib.AccountDetails({ balance: 0, delegateBalance: 0, nextTwabIndex: 2, cardinality: 10 })
    );

    uint112 _amount = 1000e18;
    (TwabLib.AccountDetails memory accountDetails, , ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(accountDetails.nextTwabIndex, 3);
    assertEq(accountDetails.cardinality, 11);
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
  }

  function testIncreaseCardinalityOverflow() public {
    twabLibMock.setAccountDetails(
      TwabLib.AccountDetails({
        balance: 0,
        delegateBalance: 0,
        nextTwabIndex: 2,
        cardinality: 2 ** 16 - 1
      })
    );

    uint112 _amount = 1000e18;
    (TwabLib.AccountDetails memory accountDetails, , ) = twabLibMock.increaseBalances(0, _amount);

    assertEq(accountDetails.nextTwabIndex, 3);
    assertEq(accountDetails.cardinality, 2 ** 16 - 1);
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, _amount);
  }
}
