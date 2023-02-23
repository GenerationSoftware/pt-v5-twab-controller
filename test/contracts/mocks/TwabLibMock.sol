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
  )
    external
    returns (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNewTwab
    )
  {
    (accountDetails, twab, isNewTwab) = TwabLib.increaseBalances(account, _amount, _delegateAmount);
    account.details = accountDetails;
  }

  function decreaseBalances(
    uint112 _amount,
    uint112 _delegateAmount,
    string memory _revertMessage
  )
    external
    returns (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNewTwab
    )
  {
    (accountDetails, twab, isNewTwab) = TwabLib.decreaseBalances(
      account,
      _amount,
      _delegateAmount,
      _revertMessage
    );
    account.details = accountDetails;
  }

  function getAverageBalanceBetween(uint32 _startTime, uint32 _endTime) external returns (uint256) {
    return TwabLib.getAverageBalanceBetween(account.twabs, account.details, _startTime, _endTime);
  }

  function oldestTwab() external returns (uint16 index, ObservationLib.Observation memory twab) {
    (index, twab) = TwabLib.oldestTwab(account.twabs, account.details);
  }

  function newestTwab() external returns (uint16 index, ObservationLib.Observation memory twab) {
    (index, twab) = TwabLib.newestTwab(account.twabs, account.details);
  }

  function getBalanceAt(uint32 _targetTime) external returns (uint256 balance) {
    balance = TwabLib.getBalanceAt(account.twabs, account.details, _targetTime);
  }

  function setAccountDetails(TwabLib.AccountDetails calldata _accountDetails) external {
    account.details = _accountDetails;
  }
}
