// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "./ExtendedSafeCastLib.sol";
import "./OverflowSafeComparatorLib.sol";
import "./RingBufferLib.sol";
import "./ObservationLib.sol";

/**
 * @notice Account balances and historical twabs.
 * @param balance           Current token balance for an Account
 * @param delegateBalance   Current delegate balance for an Account (active balance for chance)
 * @param nextTwabIndex     Next uninitialized or updatable ring buffer checkpoint storage slot
 * @param cardinality       Current total "initialized" ring buffer checkpoints for single user Account.
 *                          Used to set initial boundary conditions for an efficient binary search.
 * @param details The account details
 * @param twabs The history of twabs for this account
 */
struct Account {
  uint112 balance;
  uint112 delegateBalance;
  uint16 nextTwabIndex;
  uint16 cardinality;
  ObservationLib.Observation[365] twabs;
}

/**
 * @title  PoolTogether V5 TwabLib (Library)
 * @author PoolTogether Inc Team
 * @dev    Time-Weighted Average Balance Library for ERC20 tokens.
 * @notice This TwabLib adds on-chain historical lookups to a user(s) time-weighted average balance.
 *         Each user is mapped to an Account struct containing the TWAB history (ring buffer) and
 *         ring buffer parameters. Every token.transfer() creates a new TWAB checkpoint. The new
 *         TWAB checkpoint is stored in the circular ring buffer, as either a new checkpoint or
 *         rewriting a previous checkpoint with new parameters. One checkpoint per day is stored.
 *         The TwabLib guarantees minimum 1 year of search history.
 */
library TwabLib {
  using OverflowSafeComparatorLib for uint32;
  using ExtendedSafeCastLib for uint256;

  /**
   * @notice Sets max ring buffer length in the Account.twabs Observation list.
   *         As users transfer/mint/burn tickets new Observation checkpoints are recorded.
   *         The current `MAX_CARDINALITY` guarantees a one year minimum, of accurate historical lookups.
   * @dev The user Account.Account.cardinality parameter can NOT exceed the max cardinality variable.
   *      Preventing "corrupted" ring buffer lookup pointers and new observation checkpoints.
   */
  uint16 public constant MAX_CARDINALITY = 365; // 1 year

  /**
   * @notice Increases an account's delegate balance and records a new twab.
   * @param _account          The account whose delegateBalance will be increased
   * @param _amount           The amount to increase the balance by
   * @param _delegateAmount   The amount to increase the delegateBalance by
   * @return twab             The user's latest TWAB
   * @return isNewTwab            Whether the TWAB is new
   */
  function increaseBalances(
    Account storage _account,
    uint112 _amount,
    uint112 _delegateAmount
  ) internal returns (ObservationLib.Observation memory twab, bool isNewTwab) {
    if (_delegateAmount != uint112(0)) {
      (twab, isNewTwab) = _nextTwab(_account);
    }

    _account.balance += _amount;
    _account.delegateBalance += _delegateAmount;
  }

  /**
   * @notice Calculates the next TWAB checkpoint for an account with a decreasing delegateBalance.
   * @dev    With Account struct and amount decreasing calculates the next TWAB observable checkpoint.
   * @param _account        Account whose delegateBalance will be decreased
   * @param _amount         Amount to decrease the delegateBalance by
   * @param _delegateAmount   The amount to increase the delegateBalance by
   * @param _revertMessage  Revert message for insufficient delegateBalance
   * @return twab           TWAB observation (with decreasing average)
   * @return isNewTwab          Whether TWAB is new or calling twice in the same block
   */
  function decreaseBalances(
    Account storage _account,
    uint112 _amount,
    uint112 _delegateAmount,
    string memory _revertMessage
  ) internal returns (ObservationLib.Observation memory twab, bool isNewTwab) {
    require(_account.balance >= _amount, _revertMessage);
    require(_account.delegateBalance >= _delegateAmount, _revertMessage);

    if (_delegateAmount != uint112(0)) {
      (twab, isNewTwab) = _nextTwab(_account);
    }

    unchecked {
      _account.balance -= _amount;
      _account.delegateBalance -= _delegateAmount;
    }
  }

  /**
   * @notice Calculates the average balance held by a user for a given time frame.
   * @dev    Finds the average balance between start and end timestamp epochs.
   *             Validates the supplied end time is within the range of elapsed time i.e. less then timestamp of now.
   * @param _account User Account struct loaded in memory
   * @param _startTime      Start of timestamp range as an epoch
   * @param _endTime        End of timestamp range as an epoch
   * @return uint256        Average balance of user held between epoch timestamps start and end
   */
  function getAverageBalanceBetween(
    Account memory _account,
    uint32 _startTime,
    uint32 _endTime
  ) internal view returns (uint256) {
    uint32 _currentTime = uint32(block.timestamp);
    _endTime = _endTime > _currentTime ? _currentTime : _endTime;

    (uint16 oldestTwabIndex, ObservationLib.Observation memory oldTwab) = oldestTwab(_account);
    (uint16 newestTwabIndex, ObservationLib.Observation memory newTwab) = newestTwab(_account);

    ObservationLib.Observation memory startTwab = _calculateTwab(
      _account,
      newTwab,
      oldTwab,
      newestTwabIndex,
      oldestTwabIndex,
      _startTime,
      _currentTime
    );

    ObservationLib.Observation memory endTwab = _calculateTwab(
      _account,
      newTwab,
      oldTwab,
      newestTwabIndex,
      oldestTwabIndex,
      _endTime,
      _currentTime
    );

    // Difference in amount / time
    return
      (endTwab.amount - startTwab.amount) /
      OverflowSafeComparatorLib.checkedSub(endTwab.timestamp, startTwab.timestamp, _currentTime);
  }

  /**
   * @notice Retrieves the oldest TWAB
   * @param _account Account
   * @return index The index of the oldest TWAB in the twabs array
   * @return twab The oldest TWAB
   */
  function oldestTwab(
    Account memory _account
  ) internal pure returns (uint16 index, ObservationLib.Observation memory twab) {
    index = _account.nextTwabIndex;
    twab = _account.twabs[index];

    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (twab.timestamp == 0) {
      index = 0;
      twab = _account.twabs[0];
    }
  }

  /**
   * @notice Retrieves the newest TWAB
   * @param _account  Account
   * @return index The index of the newest TWAB in the twabs array
   * @return twab The newest TWAB
   */
  function newestTwab(
    Account memory _account
  ) internal pure returns (uint16 index, ObservationLib.Observation memory twab) {
    index = uint16(RingBufferLib.newestIndex(_account.nextTwabIndex, MAX_CARDINALITY));
    twab = _account.twabs[index];
  }

  /**
   * @notice Retrieves amount at `_targetTime` timestamp
   * @param _account Account
   * @param _targetTime Timestamp at which the reserved TWAB should be for
   * @return uint256    TWAB amount at `_targetTime`.
   */
  function getBalanceAt(
    Account memory _account,
    uint32 _targetTime
  ) internal view returns (uint256) {
    uint32 _currentTime = uint32(block.timestamp);
    _targetTime = _targetTime > _currentTime ? _currentTime : _targetTime;

    uint16 newestTwabIndex;
    ObservationLib.Observation memory afterOrAt;
    ObservationLib.Observation memory beforeOrAt;
    ObservationLib.Observation[MAX_CARDINALITY] memory _twabs = _account.twabs;

    (newestTwabIndex, beforeOrAt) = newestTwab(_account);

    // If `_targetTime` is chronologically after the newest TWAB, we can simply return the current balance
    if (beforeOrAt.timestamp.lte(_targetTime, _currentTime)) {
      return _account.delegateBalance;
    }

    uint16 oldestTwabIndex;

    // Now, set before to the oldest TWAB
    (oldestTwabIndex, beforeOrAt) = oldestTwab(_account);

    // If `_targetTime` is chronologically before the oldest TWAB, we can early return
    if (_targetTime.lt(beforeOrAt.timestamp, _currentTime)) {
      return 0;
    }

    // Otherwise, we perform the `binarySearch`
    (beforeOrAt, afterOrAt) = ObservationLib.binarySearch(
      _twabs,
      newestTwabIndex,
      oldestTwabIndex,
      _targetTime,
      _account.cardinality,
      _currentTime
    );

    // Sum the difference in amounts and divide by the difference in timestamps.
    // The time-weighted average balance uses time measured between two epoch timestamps as
    // a constaint on the measurement when calculating the time weighted average balance.
    return
      (afterOrAt.amount - beforeOrAt.amount) /
      OverflowSafeComparatorLib.checkedSub(afterOrAt.timestamp, beforeOrAt.timestamp, _currentTime);
  }

  /**
   * @notice Calculates a user TWAB for a target timestamp using the historical TWAB records.
   *             The balance is linearly interpolated: amount differences / timestamp differences
   *             using the simple (after.amount - before.amount / end.timestamp - start.timestamp) formula.
   * /** @dev    Binary search in _calculateTwab fails when searching out of bounds. Thus, before
   *             searching we exclude target timestamps out of range of newest/oldest TWAB(s).
   *             IF a search is before or after the range we "extrapolate" a Observation from the expected state.
   * @param _account   User Account struct loaded in memory
   * @param _newestTwab       Newest TWAB in history (end of ring buffer)
   * @param _oldestTwab       Olderst TWAB in history (end of ring buffer)
   * @param _newestTwabIndex  Pointer in ring buffer to newest TWAB
   * @param _oldestTwabIndex  Pointer in ring buffer to oldest TWAB
   * @param _targetTimestamp  Epoch timestamp to calculate for time (T) in the TWAB
   * @param _time             Block.timestamp
   * @return account   Updated Account struct
   */
  function _calculateTwab(
    Account memory _account,
    ObservationLib.Observation memory _newestTwab,
    ObservationLib.Observation memory _oldestTwab,
    uint16 _newestTwabIndex,
    uint16 _oldestTwabIndex,
    uint32 _targetTimestamp,
    uint32 _time
  ) private pure returns (ObservationLib.Observation memory) {
    // If `_targetTimestamp` is chronologically after the newest TWAB, we extrapolate a new one
    if (_newestTwab.timestamp.lt(_targetTimestamp, _time)) {
      return _computeNextTwab(_newestTwab, _account.delegateBalance, _targetTimestamp);
    }

    if (_newestTwab.timestamp == _targetTimestamp) {
      return _newestTwab;
    }

    if (_oldestTwab.timestamp == _targetTimestamp) {
      return _oldestTwab;
    }

    // If `_targetTimestamp` is chronologically before the oldest TWAB, we create a zero twab
    if (_targetTimestamp.lt(_oldestTwab.timestamp, _time)) {
      return ObservationLib.Observation({ amount: 0, timestamp: _targetTimestamp });
    }

    // Otherwise, both timestamps must be surrounded by twabs.
    (
      ObservationLib.Observation memory beforeOrAtStart,
      ObservationLib.Observation memory afterOrAtStart
    ) = ObservationLib.binarySearch(
        _account.twabs,
        _newestTwabIndex,
        _oldestTwabIndex,
        _targetTimestamp,
        _account.cardinality,
        _time
      );

    // NOTE: Is this a safe cast?
    uint112 heldBalance = uint112(
      (afterOrAtStart.amount - beforeOrAtStart.amount) /
        OverflowSafeComparatorLib.checkedSub(
          afterOrAtStart.timestamp,
          beforeOrAtStart.timestamp,
          _time
        )
    );

    return _computeNextTwab(beforeOrAtStart, heldBalance, _targetTimestamp);
  }

  /**
   * @notice Calculates the next TWAB using the newestTwab and updated balance.
   * @dev    Storage of the TWAB obersation is managed by the calling function and not _computeNextTwab.
   * @param _currentTwab    Newest Observation in the Account.twabs list
   * @param _currentDelegateBalance User delegateBalance at time of most recent (newest) checkpoint write
   * @param _time           Current block.timestamp
   * @return Observation    The TWAB Observation
   */
  function _computeNextTwab(
    ObservationLib.Observation memory _currentTwab,
    uint112 _currentDelegateBalance,
    uint32 _time
  ) private pure returns (ObservationLib.Observation memory) {
    // New twab amount = last twab amount (or zero) + (current amount * elapsed seconds)
    return
      ObservationLib.Observation({
        amount: _currentTwab.amount +
          _currentDelegateBalance *
          (_time.checkedSub(_currentTwab.timestamp, _time)),
        timestamp: _time
      });
  }

  /**
   * @notice Sets a new TWAB Observation at the next available index and returns the new account.
   * @dev Note that if `_currentTime` is before the last observation timestamp, it appears as an overflow.
   * @param _account The current account
   * @return twab The newest twab (may or may not be brand-new)
   * @return isNewTwab Whether the newest twab was created by this call
   */
  function _nextTwab(
    Account storage _account
  ) private returns (ObservationLib.Observation memory twab, bool isNewTwab) {
    uint32 _currentTime = uint32(block.timestamp);

    (, ObservationLib.Observation memory _newestTwab) = newestTwab(_account);

    // if we're in the same block, return
    if (_newestTwab.timestamp == _currentTime) {
      return (_newestTwab, false);
    }

    ObservationLib.Observation memory secondNewestTwab = _account.twabs[
      RingBufferLib.prevIndex(
        RingBufferLib.newestIndex(_account.nextTwabIndex, MAX_CARDINALITY),
        MAX_CARDINALITY
      )
    ];

    ObservationLib.Observation memory _newTwab = _computeNextTwab(
      _newestTwab,
      _account.delegateBalance,
      _currentTime
    );

    /**
     * TODO
     * secondNewestTwab.timestamp will always return 0 if it has not be overwritten yet.
     * So it means that this condition will return true for the second time the twab is updated
     * even if less than 24 hours elapsed between the first recording.
     */
    if (
      secondNewestTwab.timestamp == 0 ||
      (OverflowSafeComparatorLib.checkedSub(
        _newestTwab.timestamp,
        secondNewestTwab.timestamp,
        _currentTime
      ) >= 1 days)
    ) {
      _account.twabs[_account.nextTwabIndex] = _newTwab;
      _account.nextTwabIndex = uint16(
        RingBufferLib.nextIndex(_account.nextTwabIndex, MAX_CARDINALITY)
      );

      // Prevent the Account specific cardinality from exceeding the MAX_CARDINALITY.
      // The ring buffer length is limited by MAX_CARDINALITY. IF the account.cardinality
      // exceeds the max cardinality, new observations would be incorrectly set or the
      // observation would be out of "bounds" of the ring buffer. Once reached the
      // Account.cardinality will continue to be equal to max cardinality.
      if (_account.cardinality < MAX_CARDINALITY) {
        _account.cardinality += 1;
      }
    } else {
      _account.twabs[RingBufferLib.newestIndex(_account.nextTwabIndex, MAX_CARDINALITY)] = _newTwab;
    }

    return (_newTwab, true);
  }
}
