// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { TwabLib } from "src/libraries/TwabLib.sol";
import { ObservationLib } from "src/libraries/ObservationLib.sol";

contract TwabLibMock {
  uint16 public constant MAX_CARDINALITY = 365;
  using TwabLib for ObservationLib.Observation[MAX_CARDINALITY];
  TwabLib.Account public account;

  function increaseBalances(
    uint96 _amount,
    uint96 _delegateAmount
  ) external returns (ObservationLib.Observation memory, bool, bool) {
    (
      ObservationLib.Observation memory observation,
      bool isNewObservation,
      bool isObservationRecorded
    ) = TwabLib.increaseBalances(account, _amount, _delegateAmount);

    return (observation, isNewObservation, isObservationRecorded);
  }

  function decreaseBalances(
    uint96 _amount,
    uint96 _delegateAmount,
    string memory _revertMessage
  ) external returns (ObservationLib.Observation memory, bool, bool) {
    (
      ObservationLib.Observation memory observation,
      bool isNewObservation,
      bool isObservationRecorded
    ) = TwabLib.decreaseBalances(account, _amount, _delegateAmount, _revertMessage);

    return (observation, isNewObservation, isObservationRecorded);
  }

  function getTwabBetween(uint32 _startTime, uint32 _endTime) external view returns (uint256) {
    uint256 averageBalance = TwabLib.getTwabBetween(
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
      account.observations,
      account.details,
      _targetTime
    );
    return prevOrAtObservation;
  }

  function getNextOrNewestObservation(
    uint32 _targetTime
  ) external view returns (ObservationLib.Observation memory) {
    ObservationLib.Observation memory nextOrNewestObservation = TwabLib.getNextOrNewestObservation(
      account.observations,
      account.details,
      _targetTime
    );
    return nextOrNewestObservation;
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
    uint256 balance = TwabLib.getBalanceAt(account.observations, account.details, _targetTime);
    return balance;
  }

  function getAccount() external view returns (TwabLib.Account memory) {
    return account;
  }

  function getAccountDetails() external view returns (TwabLib.AccountDetails memory) {
    return account.details;
  }

  function getTimestampPeriod(uint32 _timestamp) external pure returns (uint32) {
    uint32 timestamp = TwabLib.getTimestampPeriod(_timestamp);
    return timestamp;
  }

  function isTimeSafe(uint32 _timestamp) external view returns (bool) {
    bool isSafe = TwabLib.isTimeSafe(account.observations, account.details, _timestamp);
    return isSafe;
  }

  function isTimeRangeSafe(
    uint32 _startTimestamp,
    uint32 _endTimestamp
  ) external view returns (bool) {
    bool isSafe = TwabLib.isTimeRangeSafe(
      account.observations,
      account.details,
      _startTimestamp,
      _endTimestamp
    );
    return isSafe;
  }
}
