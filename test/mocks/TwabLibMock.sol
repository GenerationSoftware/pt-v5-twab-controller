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
  ) external returns (AccountDetails memory accountDetails) {
    accountDetails = TwabLib.increaseBalance(account, _amount);
    account.details = accountDetails;
  }

  function decreaseBalance(
    uint112 _amount,
    string memory _revertMessage
  ) external returns (AccountDetails memory accountDetails) {
    accountDetails = TwabLib.decreaseBalance(account, _amount, _revertMessage);
    account.details = accountDetails;
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
    (accountDetails, twab, isNew) = TwabLib.increaseDelegateBalance(account, _amount, _currentTime);
    account.details = accountDetails;
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
    (accountDetails, twab, isNew) = TwabLib.decreaseDelegateBalance(
      account,
      _amount,
      _revertMessage,
      _currentTime
    );
    account.details = accountDetails;
  }

  function getAverageDelegateBalanceBetween(
    uint32 _startTime,
    uint32 _endTime,
    uint32 _currentTime
  ) external returns (uint256) {
    return
      TwabLib.getAverageDelegateBalanceBetween(
        account.twabs,
        account.details,
        _startTime,
        _endTime,
        _currentTime
      );
  }

  function oldestTwab() external returns (uint16 index, ObservationLib.Observation memory twab) {
    return TwabLib.oldestTwab(account.twabs, account.details);
  }

  function newestTwab() external returns (uint16 index, ObservationLib.Observation memory twab) {
    return TwabLib.newestTwab(account.twabs, account.details);
  }

  function getDelegateBalanceAt(
    uint32 _targetTime,
    uint32 _currentTime
  ) external returns (uint256) {
    return TwabLib.getDelegateBalanceAt(account.twabs, account.details, _targetTime, _currentTime);
  }

  function push(
    AccountDetails memory _accountDetails
  ) external pure returns (AccountDetails memory) {
    return TwabLib.push(_accountDetails);
  }
}
