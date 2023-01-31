// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { TwabLib } from "../../src/libraries/TwabLib.sol";
import { ObservationLib } from "../../src/libraries/ObservationLib.sol";

contract TwabLibMock {
  uint16 public constant MAX_CARDINALITY = 365;
  TwabLib.Account public account;
  ObservationLib.Observation[MAX_CARDINALITY] public _twabs;

  function increaseBalance(
    uint112 _amount,
    uint32 _currentTime
  )
    external
    returns (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    )
  {
    return TwabLib.increaseBalance(account, _amount, _currentTime);
  }

  function decreaseBalance(
    uint112 _amount,
    string memory _revertMessage,
    uint32 _currentTime
  )
    external
    returns (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    )
  {
    return TwabLib.decreaseBalance(account, _amount, _revertMessage, _currentTime);
  }

  function getAverageBalanceBetween(
    TwabLib.AccountDetails memory _accountDetails,
    uint32 _startTime,
    uint32 _endTime,
    uint32 _currentTime
  ) external view returns (uint256) {
    return
      TwabLib.getAverageBalanceBetween(_twabs, _accountDetails, _startTime, _endTime, _currentTime);
  }

  function oldestTwab(
    TwabLib.AccountDetails memory _accountDetails
  ) external view returns (uint16 index, ObservationLib.Observation memory twab) {
    return TwabLib.oldestTwab(_twabs, _accountDetails);
  }

  function newestTwab(
    TwabLib.AccountDetails memory _accountDetails
  ) external view returns (uint16 index, ObservationLib.Observation memory twab) {
    return TwabLib.newestTwab(_twabs, _accountDetails);
  }

  function getBalanceAt(
    TwabLib.AccountDetails memory _accountDetails,
    uint32 _targetTime,
    uint32 _currentTime
  ) external view returns (uint256) {
    return TwabLib.getBalanceAt(_twabs, _accountDetails, _targetTime, _currentTime);
  }
}
