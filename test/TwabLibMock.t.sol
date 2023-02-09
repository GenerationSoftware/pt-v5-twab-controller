// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { BaseSetup } from "./utils/BaseSetup.sol";
import { TwabLibMock } from "./mocks/TwabLibMock.sol";
import { TwabLib, Account, AccountDetails } from "../src/libraries/TwabLib.sol";
import { ObservationLib } from "../src/libraries/ObservationLib.sol";

contract TwabLibMockTest is BaseSetup {
  TwabLibMock public twabLibMock;
  uint16 MAX_CARDINALITY = 365;

  function setUp() public override {
    super.setUp();

    twabLibMock = new TwabLibMock();
  }

  function testIncreaseDelegateBalanceHappyPath() public {
    uint32 initialTimestamp = uint32(100);
    uint32 currentTimestamp = uint32(200);

    // Increase balance
    (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    ) = twabLibMock.increaseDelegateBalance(100e18, initialTimestamp);

    // Check balance
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 100e18);
    assertEq(accountDetails.nextTwabIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(twab.amount, 0);
    assertEq(twab.timestamp, 100);
    assertTrue(isNew);

    uint256 balance = twabLibMock.getDelegateBalanceAt(initialTimestamp, currentTimestamp);
    assertEq(balance, 100e18);

    balance = twabLibMock.getDelegateBalanceAt(currentTimestamp, currentTimestamp);
    assertEq(balance, 100e18);
  }

  function testIncreaseDelegateBalanceSameBlock() public {
    uint32 initialTimestamp = uint32(100);

    // Increase balance 2x
    twabLibMock.increaseDelegateBalance(100e18, initialTimestamp);
    (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    ) = twabLibMock.increaseDelegateBalance(100e18, initialTimestamp);

    // Check balance
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 200e18);
    assertEq(accountDetails.nextTwabIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(twab.amount, 0);
    assertEq(twab.timestamp, 100);
    assertFalse(isNew);
  }

  function testIncreaseDelegateBalanceMultipleRecords() public {
    uint32 initialTimestamp = uint32(100);
    uint32 secondTimestamp = uint32(200);

    // Increase balance
    (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    ) = twabLibMock.increaseDelegateBalance(100e18, initialTimestamp);

    // Check balance
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 100e18);
    assertEq(accountDetails.nextTwabIndex, 1);
    assertEq(accountDetails.cardinality, 1);
    assertEq(twab.amount, 0);
    assertEq(twab.timestamp, 100);
    assertTrue(isNew);

    // Increase balance
    (accountDetails, twab, isNew) = twabLibMock.increaseDelegateBalance(100e18, secondTimestamp);

    // Check balance
    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 200e18);
    assertEq(accountDetails.nextTwabIndex, 2);
    assertEq(accountDetails.cardinality, 2);
    assertEq(twab.amount, 10000e18);
    assertEq(twab.timestamp, 200);
    assertTrue(isNew);
  }

  function testOldestAndNewestTwab() public {
    uint32 initialTimestamp = uint32(100);
    uint32 secondTimestamp = uint32(200);
    uint32 thirdTimestamp = uint32(300);

    // Read TWABs
    (uint16 oldestIndex, ObservationLib.Observation memory oldestTwab) = twabLibMock.oldestTwab();
    (uint16 newestIndex, ObservationLib.Observation memory newestTwab) = twabLibMock.newestTwab();

    assertEq(oldestIndex, 0);
    assertEq(oldestTwab.amount, 0);
    assertEq(oldestTwab.timestamp, 0);
    // Newest TWAB is the last index on an empty TWAB array
    assertEq(newestIndex, MAX_CARDINALITY - 1);
    assertEq(newestTwab.amount, 0);
    assertEq(newestTwab.timestamp, 0);

    // Update TWABs
    twabLibMock.increaseDelegateBalance(100e18, initialTimestamp);
    twabLibMock.increaseDelegateBalance(100e18, secondTimestamp);
    twabLibMock.decreaseDelegateBalance(100e18, "revert-message", thirdTimestamp);

    (oldestIndex, oldestTwab) = twabLibMock.oldestTwab();
    (newestIndex, newestTwab) = twabLibMock.newestTwab();
    assertEq(oldestIndex, 0);
    assertEq(oldestTwab.amount, 0);
    assertEq(oldestTwab.timestamp, initialTimestamp);
    assertEq(newestIndex, 2);
    assertEq(newestTwab.amount, 30000e18);
    assertEq(newestTwab.timestamp, thirdTimestamp);
  }

  // getAverageDelegateBalanceBetween

  function averageDelegateBalanceBetweenSingleSetup()
    public
    returns (uint32 initialTimestamp, uint32 currentTimestamp)
  {
    initialTimestamp = uint32(1000);
    currentTimestamp = uint32(2000);

    twabLibMock.increaseDelegateBalance(1000e18, initialTimestamp);
  }

  function testGetAverageDelegateBalanceBetweenSingleBefore() public {
    (uint32 initialTimestamp, uint32 currentTimestamp) = averageDelegateBalanceBetweenSingleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      initialTimestamp - 100,
      initialTimestamp - 50,
      currentTimestamp
    );
    assertEq(balance, 0);
  }

  function testGetAverageDelegateBalanceBetweenSingleBeforeIncluding() public {
    (uint32 initialTimestamp, uint32 currentTimestamp) = averageDelegateBalanceBetweenSingleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      initialTimestamp - 100,
      initialTimestamp,
      currentTimestamp
    );
    assertEq(balance, 0);
  }

  function testGetAverageDelegateBalanceBetweenSingleFuture() public {
    (uint32 initialTimestamp, uint32 currentTimestamp) = averageDelegateBalanceBetweenSingleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      initialTimestamp - 50,
      initialTimestamp + 50,
      initialTimestamp
    );
    assertEq(balance, 0);
  }

  function testGetAverageDelegateBalanceBetweenSingleCentered() public {
    (uint32 initialTimestamp, uint32 currentTimestamp) = averageDelegateBalanceBetweenSingleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      initialTimestamp - 50,
      initialTimestamp + 50,
      currentTimestamp
    );
    assertEq(balance, 500e18);
  }

  function testGetAverageDelegateBalanceBetweenSingleAfter() public {
    (uint32 initialTimestamp, uint32 currentTimestamp) = averageDelegateBalanceBetweenSingleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      initialTimestamp + 50,
      initialTimestamp + 51,
      currentTimestamp
    );
    assertEq(balance, 1000e18);
  }

  function averageDelegateBalanceBetweenDoubleSetup()
    public
    returns (uint32 initialTimestamp, uint32 secondTimestamp, uint32 currentTimestamp)
  {
    initialTimestamp = uint32(1000);
    secondTimestamp = uint32(2000);
    currentTimestamp = uint32(3000);

    twabLibMock.increaseDelegateBalance(1000e18, initialTimestamp);
    twabLibMock.decreaseDelegateBalance(500e18, "insufficient-balance", secondTimestamp);
  }

  function testAverageDelegateBalanceBetweenDoubleTwabBefore() public {
    (
      uint32 initialTimestamp,
      uint32 secondTimestamp,
      uint32 currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      initialTimestamp - 100,
      initialTimestamp - 50,
      currentTimestamp
    );
    assertEq(balance, 0);
  }

  function testAverageDelegateBalanceBetwenDoubleCenteredFirst() public {
    (
      uint32 initialTimestamp,
      uint32 secondTimestamp,
      uint32 currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      initialTimestamp - 50,
      initialTimestamp + 50,
      currentTimestamp
    );
    assertEq(balance, 500e18);
  }

  function testAverageDelegateBalanceBetweenDoubleBetween() public {
    (
      uint32 initialTimestamp,
      uint32 secondTimestamp,
      uint32 currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      initialTimestamp + 50,
      initialTimestamp + 55,
      currentTimestamp
    );
    assertEq(balance, 1000e18);
  }

  function testAverageDelegateBalanceBettwenDoubleCenteredSecond() public {
    (
      uint32 initialTimestamp,
      uint32 secondTimestamp,
      uint32 currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      secondTimestamp - 50,
      secondTimestamp + 50,
      currentTimestamp
    );
    assertEq(balance, 750e18);
  }

  function testAverageDelegateBalanceBetweenDoubleAfter() public {
    (
      uint32 initialTimestamp,
      uint32 secondTimestamp,
      uint32 currentTimestamp
    ) = averageDelegateBalanceBetweenDoubleSetup();

    uint256 balance = twabLibMock.getAverageDelegateBalanceBetween(
      secondTimestamp + 50,
      secondTimestamp + 51,
      currentTimestamp
    );
    assertEq(balance, 500e18);
  }

  // getDelegateBalanceAt

  function getDelegateBalanceAtSetup()
    public
    returns (uint32 initialTimestamp, uint32 currentTimestamp)
  {
    initialTimestamp = uint32(1000);
    currentTimestamp = uint32(2000);

    twabLibMock.increaseDelegateBalance(1000e18, initialTimestamp);
  }

  function testDelegateBalanceAtSingleTwabBefore() public {
    (uint32 initialTimestamp, uint32 currentTimestamp) = getDelegateBalanceAtSetup();
    uint256 balance = twabLibMock.getDelegateBalanceAt(500, currentTimestamp);
    assertEq(balance, 0);
  }

  function testDelegateBalanceAtSingleTwabAtOrAfter() public {
    (uint32 initialTimestamp, uint32 currentTimestamp) = getDelegateBalanceAtSetup();

    uint256 balance = twabLibMock.getDelegateBalanceAt(500, currentTimestamp);
    assertEq(balance, 0);
  }

  function testProblematicQuery() public {
    twabLibMock.increaseDelegateBalance(100e18, 1630713395);
    twabLibMock.decreaseDelegateBalance(100e18, "revert-message", 1630713396);

    uint256 balance = twabLibMock.getDelegateBalanceAt(1630713395, 1675702148);
    assertEq(balance, 100e18);
  }

  // Push
  function testIncreaseCardinality() public {
    AccountDetails memory result = twabLibMock.push(
      AccountDetails({ balance: 0, delegateBalance: 0, nextTwabIndex: 2, cardinality: 10 })
    );
    assertEq(result.nextTwabIndex, 3);
    assertEq(result.cardinality, 11);
    assertEq(result.balance, 0);
    assertEq(result.delegateBalance, 0);
  }

  function testIncreaseCardinalityOverflow() public {
    AccountDetails memory result = twabLibMock.push(
      AccountDetails({ balance: 0, delegateBalance: 0, nextTwabIndex: 2, cardinality: 2 ** 16 - 1 })
    );
    assertEq(result.nextTwabIndex, 3);
    assertEq(result.cardinality, 2 ** 16 - 1);
    assertEq(result.balance, 0);
    assertEq(result.delegateBalance, 0);
  }
}
