// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import { TwabLib } from "../../src/libraries/TwabLib.sol";
import { ObservationLib } from "../../src/libraries/ObservationLib.sol";

contract TwabLibMock {
  uint16 public constant MAX_CARDINALITY = 9600;
  uint32 PERIOD_LENGTH = 1 days;
  uint32 PERIOD_OFFSET = 10 days;
  using TwabLib for ObservationLib.Observation[MAX_CARDINALITY];
  TwabLib.Account public account;

  function increaseBalances(
    uint96 _amount,
    uint96 _delegateAmount
  )
    external
    returns (ObservationLib.Observation memory, bool, bool, TwabLib.AccountDetails memory)
  {
    (
      ObservationLib.Observation memory observation,
      bool isNewObservation,
      bool isObservationRecorded,
      TwabLib.AccountDetails memory accountDetails
    ) = TwabLib.increaseBalances(PERIOD_LENGTH, PERIOD_OFFSET, account, _amount, _delegateAmount);

    return (observation, isNewObservation, isObservationRecorded, accountDetails);
  }

  function decreaseBalances(
    uint96 _amount,
    uint96 _delegateAmount,
    string memory _revertMessage
  )
    external
    returns (ObservationLib.Observation memory, bool, bool, TwabLib.AccountDetails memory)
  {
    (
      ObservationLib.Observation memory observation,
      bool isNewObservation,
      bool isObservationRecorded,
      TwabLib.AccountDetails memory accountDetails
    ) = TwabLib.decreaseBalances(
        PERIOD_LENGTH,
        PERIOD_OFFSET,
        account,
        _amount,
        _delegateAmount,
        _revertMessage
      );

    return (observation, isNewObservation, isObservationRecorded, accountDetails);
  }

  function getTwabBetween(uint32 _startTime, uint32 _endTime) external view returns (uint256) {
    uint256 averageBalance = TwabLib.getTwabBetween(
      PERIOD_LENGTH,
      PERIOD_OFFSET,
      account.observations,
      account.details,
      _startTime,
      _endTime
    );
    return averageBalance;
  }

  function getPreviousOrAtObservation(
    uint32 _targetTime
  ) external view returns (ObservationLib.Observation memory) {
    ObservationLib.Observation memory prevOrAtObservation = TwabLib.getPreviousOrAtObservation(
      PERIOD_OFFSET,
      account.observations,
      account.details,
      _targetTime
    );
    return prevOrAtObservation;
  }

  function getOldestObservation()
    external
    view
    returns (uint16, ObservationLib.Observation memory)
  {
    (uint16 index, ObservationLib.Observation memory observation) = TwabLib.getOldestObservation(
      account.observations,
      account.details
    );
    return (index, observation);
  }

  function getNewestObservation()
    external
    view
    returns (uint16, ObservationLib.Observation memory)
  {
    (uint16 index, ObservationLib.Observation memory observation) = TwabLib.getNewestObservation(
      account.observations,
      account.details
    );
    return (index, observation);
  }

  function getBalanceAt(uint32 _targetTime) external view returns (uint256) {
    uint256 balance = TwabLib.getBalanceAt(
      PERIOD_LENGTH,
      PERIOD_OFFSET,
      account.observations,
      account.details,
      _targetTime
    );
    return balance;
  }

  function getAccount() external view returns (TwabLib.Account memory) {
    return account;
  }

  function getAccountDetails() external view returns (TwabLib.AccountDetails memory) {
    return account.details;
  }

  function getTimestampPeriod(uint32 _timestamp) external view returns (uint32) {
    uint32 timestamp = TwabLib.getTimestampPeriod(PERIOD_LENGTH, PERIOD_OFFSET, _timestamp);
    return timestamp;
  }

  function getPeriodStartTime(uint32 _period) external view returns (uint32) {
    uint32 start = TwabLib.getPeriodStartTime(PERIOD_LENGTH, PERIOD_OFFSET, _period);
    return start;
  }

  function getPeriodEndTime(uint32 _period) external view returns (uint32) {
    uint32 end = TwabLib.getPeriodEndTime(PERIOD_LENGTH, PERIOD_OFFSET, _period);
    return end;
  }

  function currentOverwritePeriodStartedAt(
    uint32 _PERIOD_LENGTH,
    uint32 _PERIOD_OFFSET
  ) external view returns (uint32) {
    uint32 start = TwabLib.currentOverwritePeriodStartedAt(_PERIOD_LENGTH, _PERIOD_OFFSET);
    return start;
  }

  function hasFinalized(uint32 _timestamp) external view returns (bool) {
    bool isSafe = TwabLib.hasFinalized(PERIOD_LENGTH, PERIOD_OFFSET, _timestamp);
    return isSafe;
  }
}
