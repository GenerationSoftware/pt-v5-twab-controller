// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { TwabLib } from "src/libraries/TwabLib.sol";
import { ObservationLib } from "src/libraries/ObservationLib.sol";

contract TwabLibMock {
  uint16 public constant MAX_CARDINALITY = 365;
  using TwabLib for ObservationLib.Observation[MAX_CARDINALITY];
  TwabLib.Account public account;

  function increaseBalances(
    uint112 _amount,
    uint112 _delegateAmount
  ) external returns (TwabLib.AccountDetails memory, ObservationLib.Observation memory, bool) {
    (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNewTwab
    ) = TwabLib.increaseBalances(account, _amount, _delegateAmount);
    account.details = accountDetails;
    return (accountDetails, twab, isNewTwab);
  }

  function decreaseBalances(
    uint112 _amount,
    uint112 _delegateAmount,
    string memory _revertMessage
  ) external returns (TwabLib.AccountDetails memory, ObservationLib.Observation memory, bool) {
    (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNewTwab
    ) = TwabLib.decreaseBalances(account, _amount, _delegateAmount, _revertMessage);
    account.details = accountDetails;
    return (accountDetails, twab, isNewTwab);
  }

  function getAverageBalanceBetween(
    uint32 _startTime,
    uint32 _endTime
  ) external view returns (uint256) {
    uint256 averageBalance = TwabLib.getAverageBalanceBetween(
      account.twabs,
      account.details,
      _startTime,
      _endTime
    );
    return averageBalance;
  }

  function oldestTwab() external view returns (uint16, ObservationLib.Observation memory) {
    (uint16 index, ObservationLib.Observation memory twab) = TwabLib.oldestTwab(
      account.twabs,
      account.details
    );
    return (index, twab);
  }

  function newestTwab() external view returns (uint16, ObservationLib.Observation memory) {
    (uint16 index, ObservationLib.Observation memory twab) = TwabLib.newestTwab(
      account.twabs,
      account.details
    );
    return (index, twab);
  }

  function getBalanceAt(uint32 _targetTime) external view returns (uint256) {
    uint256 balance = TwabLib.getBalanceAt(account.twabs, account.details, _targetTime);
    return balance;
  }

  function setAccountDetails(TwabLib.AccountDetails calldata _accountDetails) external {
    account.details = _accountDetails;
  }
}
