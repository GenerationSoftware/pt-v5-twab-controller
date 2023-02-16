// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { TwabLib, Account, AccountDetails } from "../../src/libraries/TwabLib.sol";
import { ObservationLib } from "../../src/libraries/ObservationLib.sol";

contract TwabLibMock {
  uint16 public constant MAX_CARDINALITY = 365;
  using TwabLib for ObservationLib.Observation[MAX_CARDINALITY];
  Account public account;

  function increaseBalance(
    uint112 _amount
  ) external returns (AccountDetails memory) {
    TwabLib.increaseBalance(account, _amount);
    return account.details;
  }

  function decreaseBalance(
    uint112 _amount,
    string memory _revertMessage
  ) external returns (AccountDetails memory) {
    TwabLib.decreaseBalance(account, _amount, _revertMessage);
    return account.details;
  }

  function increaseDelegateBalance(
    uint112 _amount,
    uint32 _currentTime
  )
    external
    returns (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    )
  {
    (twab, isNew) = TwabLib.increaseDelegateBalance(account, _amount, _currentTime);
    accountDetails = account.details;
  }

  function decreaseDelegateBalance(
    uint112 _amount,
    string memory _revertMessage,
    uint32 _currentTime
  )
    external
    returns (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    )
  {
    (twab, isNew) = TwabLib.decreaseDelegateBalance(
      account,
      _amount,
      _revertMessage,
      _currentTime
    );

    accountDetails = account.details;
  }

  function getAverageBalanceBetween(
    uint32 _startTime,
    uint32 _endTime,
    uint32 _currentTime
  ) external returns (uint256) {
    return
      TwabLib.getAverageBalanceBetween(
        account.twabs,
        account.details,
        _startTime,
        _endTime,
        _currentTime
      );
  }

  function oldestTwab() external returns (uint16 index, ObservationLib.Observation memory twab) {
    (index, twab) = TwabLib.oldestTwab(account.twabs, account.details);
  }

  function newestTwab() external returns (uint16 index, ObservationLib.Observation memory twab) {
    (index, twab) = TwabLib.newestTwab(account.twabs, account.details);
  }

  function getBalanceAt(
    uint32 _targetTime,
    uint32 _currentTime
  ) external returns (uint256 balance) {
    balance = TwabLib.getBalanceAt(account.twabs, account.details, _targetTime, _currentTime);
  }

  function push(
    AccountDetails memory _accountDetails
  ) external returns (AccountDetails memory _account) {
    _account = TwabLib.push(_accountDetails);
  }
}
