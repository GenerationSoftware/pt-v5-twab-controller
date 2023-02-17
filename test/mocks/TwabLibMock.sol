// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { TwabLib, Account } from "../../src/libraries/TwabLib.sol";
import { ObservationLib } from "../../src/libraries/ObservationLib.sol";

contract TwabLibMock {
  uint16 public constant MAX_CARDINALITY = 365;
  using TwabLib for ObservationLib.Observation[MAX_CARDINALITY];

  // function increaseBalances(
  //   Account memory _account,
  //   uint112 _amount,
  //   uint112 _delegateAmount
  // ) external returns (
  //   ObservationLib.Observation memory twab,
  //   bool isNewTwab
  // ) {
  //   (
  //     twab,
  //     isNewTwab
  //   ) = TwabLib.increaseBalances(
  //     _account,
  //     _amount,
  //     _delegateAmount
  //   );
  // }

  // function decreaseBalances(
  //   uint112 _amount,
  //   uint112 _delegateAmount,
  //   string memory _revertMessage
  // ) external returns (
  //   Account memory account,
  //   ObservationLib.Observation memory twab,
  //   bool isNewTwab
  // ) {
  //   (
  //     account,
  //     twab,
  //     isNewTwab
  //   ) = TwabLib.decreaseBalances(
  //     account,
  //     _amount,
  //     _delegateAmount,
  //     _revertMessage
  //   );
  // }

  // function getAverageBalanceBetween(
  //   uint32 _startTime,
  //   uint32 _endTime,
  //   uint32 _currentTime
  // ) external returns (uint256) {
  //   return
  //     TwabLib.getAverageBalanceBetween(
  //       account.twabs,
  //       account.details,
  //       _startTime,
  //       _endTime,
  //       _currentTime
  //     );
  // }

  // function oldestTwab() external returns (uint16 index, ObservationLib.Observation memory twab) {
  //   (index, twab) = TwabLib.oldestTwab(account.twabs, account.details);
  // }

  // function newestTwab() external returns (uint16 index, ObservationLib.Observation memory twab) {
  //   (index, twab) = TwabLib.newestTwab(account.twabs, account.details);
  // }

  // function getBalanceAt(
  //   uint32 _targetTime,
  //   uint32 _currentTime
  // ) external returns (uint256 balance) {
  //   balance = TwabLib.getBalanceAt(account.twabs, account.details, _targetTime, _currentTime);
  // }

  // function push(
  //   Account memory _account
  // ) external returns (Account memory) {
  //   return TwabLib.push(_account);
  // }
}
