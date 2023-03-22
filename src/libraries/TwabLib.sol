// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "ring-buffer-lib/RingBufferLib.sol";

import "./ExtendedSafeCastLib.sol";
import "./OverflowSafeComparatorLib.sol";
import { ObservationLib, MAX_CARDINALITY } from "./ObservationLib.sol";

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
   * @notice Struct ring buffer parameters for single user Account.
   * @param balance           Current token balance for an Account
   * @param delegateBalance   Current delegate balance for an Account (active balance for chance)
   * @param nextTwabIndex     Next uninitialized or updatable ring buffer checkpoint storage slot
   * @param cardinality       Current total "initialized" ring buffer checkpoints for single user Account.
   *                          Used to set initial boundary conditions for an efficient binary search.
   */
  struct AccountDetails {
    uint112 balance;
    uint112 delegateBalance;
    uint16 nextTwabIndex;
    uint16 cardinality;
  }

  /**
   * @notice Account details and historical twabs.
   * @param details The account details
   * @param twabs The history of twabs for this account
   */
  struct Account {
    AccountDetails details;
    ObservationLib.Observation[MAX_CARDINALITY] twabs;
  }

  /**
   * @notice Increases an account's delegate balance and records a new twab.
   * @param _account          The account whose delegateBalance will be increased
   * @param _amount           The amount to increase the balance by
   * @param _delegateAmount   The amount to increase the delegateBalance by
   * @return accountDetails Updated AccountDetails struct
   * @return twab           The user's latest TWAB
   * @return isNewTwab      Whether TWAB is new or calling twice in the same block
   */
  function increaseBalances(
    Account storage _account,
    uint112 _amount,
    uint112 _delegateAmount
  )
    internal
    returns (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNewTwab
    )
  {
    accountDetails = _account.details;

    if (_delegateAmount != uint112(0)) {
      (accountDetails, twab, isNewTwab) = _nextTwab(_account.twabs, accountDetails);
    }

    accountDetails.balance += _amount;
    accountDetails.delegateBalance += _delegateAmount;
  }

  /**
   * @notice Calculates the next TWAB checkpoint for an account with a decreasing delegateBalance.
   * @dev    With Account struct and amount decreasing calculates the next TWAB observable checkpoint.
   * @param _account        Account whose delegateBalance will be decreased
   * @param _amount         Amount to decrease the delegateBalance by
   * @param _delegateAmount The amount to increase the delegateBalance by
   * @param _revertMessage  Revert message for insufficient delegateBalance
   * @return accountDetails Updated AccountDetails struct
   * @return twab           TWAB observation (with decreasing average)
   * @return isNewTwab      Whether TWAB is new or calling twice in the same block
   */
  function decreaseBalances(
    Account storage _account,
    uint112 _amount,
    uint112 _delegateAmount,
    string memory _revertMessage
  )
    internal
    returns (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNewTwab
    )
  {
    accountDetails = _account.details;

    require(accountDetails.balance >= _amount, _revertMessage);
    require(accountDetails.delegateBalance >= _delegateAmount, _revertMessage);

    if (_delegateAmount != uint112(0)) {
      (accountDetails, twab, isNewTwab) = _nextTwab(_account.twabs, accountDetails);
    }

    unchecked {
      accountDetails.balance -= _amount;
      accountDetails.delegateBalance -= _delegateAmount;
    }
  }

  /**
   * @notice Calculates the average balance held by a user for a given time frame.
   * @dev Finds the average balance between start and end timestamp epochs.
   *      Validates the supplied end time is within the range of elapsed time i.e. less then timestamp of now.
   * @param _twabs          Individual user Observation recorded checkpoints passed as storage pointer
   * @param _accountDetails User AccountDetails struct loaded in memory
   * @param _startTime      Start of timestamp range as an epoch
   * @param _endTime        End of timestamp range as an epoch
   * @return uint256 Average balance of user held between epoch timestamps start and end
   */
  function getAverageBalanceBetween(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    uint32 _startTime,
    uint32 _endTime
  ) internal view returns (uint256) {
    uint32 _currentTime = uint32(block.timestamp);
    _endTime = _endTime > _currentTime ? _currentTime : _endTime;

    (uint16 oldestTwabIndex, ObservationLib.Observation memory oldTwab) = oldestTwab(
      _twabs,
      _accountDetails
    );
    (uint16 newestTwabIndex, ObservationLib.Observation memory newTwab) = newestTwab(
      _twabs,
      _accountDetails
    );

    ObservationLib.Observation memory startTwab = _calculateTwab(
      _twabs,
      _accountDetails,
      newTwab,
      oldTwab,
      newestTwabIndex,
      oldestTwabIndex,
      _startTime,
      _currentTime
    );

    ObservationLib.Observation memory endTwab = _calculateTwab(
      _twabs,
      _accountDetails,
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
   * @param _twabs The twabs array to insert into
   * @param _accountDetails The current accountDetails
   * @return index The index of the oldest TWAB in the twabs array
   * @return twab The oldest TWAB
   */
  function oldestTwab(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails
  ) internal view returns (uint16 index, ObservationLib.Observation memory twab) {
    index = _accountDetails.nextTwabIndex;
    twab = _twabs[index];

    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (twab.timestamp == 0) {
      index = 0;
      twab = _twabs[0];
    }
  }

  /**
   * @notice Retrieves the newest TWAB
   * @param _twabs The twabs array to insert into
   * @param _accountDetails The current accountDetails
   * @return index The index of the newest TWAB in the twabs array
   * @return twab The newest TWAB
   */
  function newestTwab(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails
  ) internal view returns (uint16 index, ObservationLib.Observation memory twab) {
    index = uint16(RingBufferLib.newestIndex(_accountDetails.nextTwabIndex, MAX_CARDINALITY));
    twab = _twabs[index];
  }

  /**
   * @notice Retrieves amount at `_targetTime` timestamp
   * @param _twabs Individual user Observation recorded checkpoints passed as storage pointer
   * @param _accountDetails User AccountDetails struct loaded in memory
   * @param _targetTime Timestamp at which the reserved TWAB should be for
   * @return uint256    TWAB amount at `_targetTime`.
   */
  function getBalanceAt(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    uint32 _targetTime
  ) internal view returns (uint256) {
    uint32 _currentTime = uint32(block.timestamp);
    _targetTime = _targetTime > _currentTime ? _currentTime : _targetTime;

    uint16 newestTwabIndex;
    ObservationLib.Observation memory afterOrAt;
    ObservationLib.Observation memory beforeOrAt;

    (newestTwabIndex, beforeOrAt) = newestTwab(_twabs, _accountDetails);

    // If `_targetTime` is chronologically after the newest TWAB, we can simply return the current balance
    if (beforeOrAt.timestamp.lte(_targetTime, _currentTime)) {
      return _accountDetails.delegateBalance;
    }

    uint16 oldestTwabIndex;

    // Now, set before to the oldest TWAB
    (oldestTwabIndex, beforeOrAt) = oldestTwab(_twabs, _accountDetails);

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
      _accountDetails.cardinality,
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
   *         The balance is linearly interpolated: amount differences / timestamp differences
   *         using the simple (after.amount - before.amount / end.timestamp - start.timestamp) formula.
   * @dev Binary search in _calculateTwab fails when searching out of bounds. Thus, before
   *      searching we exclude target timestamps out of range of newest/oldest TWAB(s).
   *      IF a search is before or after the range we "extrapolate" a Observation from the expected state.
   * @param _twabs            Individual user Observation recorded checkpoints passed as storage pointer
   * @param _accountDetails   User AccountDetails struct loaded in memory
   * @param _newestTwab       Newest TWAB in history (end of ring buffer)
   * @param _oldestTwab       Olderst TWAB in history (end of ring buffer)
   * @param _newestTwabIndex  Pointer in ring buffer to newest TWAB
   * @param _oldestTwabIndex  Pointer in ring buffer to oldest TWAB
   * @param _targetTimestamp  Epoch timestamp to calculate for time (T) in the TWAB
   * @param _time             Block.timestamp
   * @return twabs Updated twabs struct
   */
  function _calculateTwab(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    ObservationLib.Observation memory _newestTwab,
    ObservationLib.Observation memory _oldestTwab,
    uint16 _newestTwabIndex,
    uint16 _oldestTwabIndex,
    uint32 _targetTimestamp,
    uint32 _time
  ) private view returns (ObservationLib.Observation memory) {
    // If `_targetTimestamp` is chronologically after the newest TWAB, we extrapolate a new one
    if (_newestTwab.timestamp.lt(_targetTimestamp, _time)) {
      return _computeNextTwab(_newestTwab, _accountDetails.delegateBalance, _targetTimestamp);
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
        _twabs,
        _newestTwabIndex,
        _oldestTwabIndex,
        _targetTimestamp,
        _accountDetails.cardinality,
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
   * @param _twabs The twabs array to insert into
   * @param _accountDetails The current accountDetails
   * @return accountDetails The new account details
   * @return twab The newest twab (may or may not be brand-new)
   * @return isNewTwab Whether the newest twab was created by this call
   */
  function _nextTwab(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails
  )
    private
    returns (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNewTwab
    )
  {
    uint32 _currentTime = uint32(block.timestamp);

    (, ObservationLib.Observation memory _newestTwab) = newestTwab(_twabs, _accountDetails);

    // if we're in the same block, return
    if (_newestTwab.timestamp == _currentTime) {
      return (_accountDetails, _newestTwab, false);
    }

    ObservationLib.Observation memory secondNewestTwab = _twabs[
      RingBufferLib.prevIndex(
        RingBufferLib.newestIndex(_accountDetails.nextTwabIndex, MAX_CARDINALITY),
        MAX_CARDINALITY
      )
    ];

    ObservationLib.Observation memory _newTwab = _computeNextTwab(
      _newestTwab,
      _accountDetails.delegateBalance,
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
      _twabs[_accountDetails.nextTwabIndex] = _newTwab;
      _accountDetails.nextTwabIndex = uint16(
        RingBufferLib.nextIndex(_accountDetails.nextTwabIndex, MAX_CARDINALITY)
      );

      // Prevent the Account specific cardinality from exceeding the MAX_CARDINALITY.
      // The ring buffer length is limited by MAX_CARDINALITY. IF the account.cardinality
      // exceeds the max cardinality, new observations would be incorrectly set or the
      // observation would be out of "bounds" of the ring buffer. Once reached the
      // Account.cardinality will continue to be equal to max cardinality.
      if (_accountDetails.cardinality < MAX_CARDINALITY) {
        _accountDetails.cardinality += 1;
      }
    } else {
      _twabs[RingBufferLib.newestIndex(_accountDetails.nextTwabIndex, MAX_CARDINALITY)] = _newTwab;
    }

    return (_accountDetails, _newTwab, true);
  }
}
