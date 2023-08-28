// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "ring-buffer-lib/RingBufferLib.sol";

import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import "./OverflowSafeComparatorLib.sol";
import { ObservationLib, MAX_CARDINALITY } from "./ObservationLib.sol";

/// @notice Emitted when a balance is decreased by an amount that exceeds the amount available.
/// @param balance The current balance of the account
/// @param amount The amount being decreased from the account's balance
/// @param message An additional message describing the error
error BalanceLTAmount(uint112 balance, uint112 amount, string message);

/// @notice Emitted when a delegate balance is decreased by an amount that exceeds the amount available.
/// @param delegateBalance The current delegate balance of the account
/// @param delegateAmount The amount being decreased from the account's delegate balance
/// @param message An additional message describing the error
error DelegateBalanceLTAmount(uint112 delegateBalance, uint112 delegateAmount, string message);

/// @notice Emitted when a request is made for a twab that is not yet finalized.
/// @param timestamp The requested timestamp
/// @param currentOverwritePeriodStartedAt The current overwrite period start time
error TimestampNotFinalized(uint256 timestamp, uint256 currentOverwritePeriodStartedAt);

/// @notice Emitted when a TWAB time range start is after the end.
/// @param start The start time
/// @param end The end time
error InvalidTimeRange(uint256 start, uint256 end);

/// @notice Emitted when there is insufficient history to lookup a twab time range
/// @param requestedTimestamp The timestamp requested
/// @param oldestTimestamp The oldest timestamp that can be read
error InsufficientHistory(uint48 requestedTimestamp, uint48 oldestTimestamp);

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
 * @notice There are limitations to the Observation data structure used. Ensure your token is
 *         compatible before using this library. Ensure the date ranges you're relying on are
 *         within safe boundaries.
 */
library TwabLib {
  using OverflowSafeComparatorLib for uint32;

  /**
   * @notice Struct ring buffer parameters for single user Account.
   * @param balance Current token balance for an Account
   * @param delegateBalance Current delegate balance for an Account (active balance for chance)
   * @param nextObservationIndex Next uninitialized or updatable ring buffer checkpoint storage slot
   * @param cardinality Current total "initialized" ring buffer checkpoints for single user Account.
   *                    Used to set initial boundary conditions for an efficient binary search.
   */
  struct AccountDetails {
    uint112 balance;
    uint112 delegateBalance;
    uint16 nextObservationIndex;
    uint16 cardinality;
  }

  /**
   * @notice Account details and historical twabs.
   * @dev The size of observations is MAX_CARDINALITY from the ObservationLib.
   * @param details The account details
   * @param observations The history of observations for this account
   */
  struct Account {
    AccountDetails details;
    ObservationLib.Observation[9600] observations;
  }

  /**
   * @notice Increase a user's balance and delegate balance by a given amount.
   * @dev This function mutates the provided account.
   * @param PERIOD_LENGTH The length of an overwrite period
   * @param PERIOD_OFFSET The offset of the first period
   * @param _account The account to update
   * @param _amount The amount to increase the balance by
   * @param _delegateAmount The amount to increase the delegate balance by
   * @return observation The new/updated observation
   * @return isNew Whether or not the observation is new or overwrote a previous one
   * @return isObservationRecorded Whether or not the observation was recorded to storage
   */
  function increaseBalances(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    Account storage _account,
    uint112 _amount,
    uint112 _delegateAmount
  )
    internal
    returns (ObservationLib.Observation memory observation, bool isNew, bool isObservationRecorded, AccountDetails memory accountDetails)
  {
    accountDetails = _account.details;
    isObservationRecorded = _delegateAmount != uint112(0);

    // Only record a new Observation if the users delegateBalance has changed.
    if (isObservationRecorded) {
      (observation, isNew, accountDetails) = _recordObservation(PERIOD_LENGTH, PERIOD_OFFSET, accountDetails, _account);
    }

    accountDetails.balance += _amount;
    accountDetails.delegateBalance += _delegateAmount;

    _account.details = accountDetails;
  }

  /**
   * @notice Decrease a user's balance and delegate balance by a given amount.
   * @dev This function mutates the provided account.
   * @param PERIOD_LENGTH The length of an overwrite period
   * @param PERIOD_OFFSET The offset of the first period
   * @param _account The account to update
   * @param _amount The amount to decrease the balance by
   * @param _delegateAmount The amount to decrease the delegate balance by
   * @param _revertMessage The revert message to use if the balance is insufficient
   * @return observation The new/updated observation
   * @return isNew Whether or not the observation is new or overwrote a previous one
   * @return isObservationRecorded Whether or not the observation was recorded to storage
   */
  function decreaseBalances(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    Account storage _account,
    uint112 _amount,
    uint112 _delegateAmount,
    string memory _revertMessage
  )
    internal
    returns (ObservationLib.Observation memory observation, bool isNew, bool isObservationRecorded, AccountDetails memory accountDetails)
  {
    accountDetails = _account.details;

    if (accountDetails.balance < _amount) {
      revert BalanceLTAmount(accountDetails.balance, _amount, _revertMessage);
    }
    if (accountDetails.delegateBalance < _delegateAmount) {
      revert DelegateBalanceLTAmount(
        accountDetails.delegateBalance,
        _delegateAmount,
        _revertMessage
      );
    }

    isObservationRecorded = _delegateAmount != uint112(0);

    // Only record a new Observation if the users delegateBalance has changed.
    if (isObservationRecorded) {
      (observation, isNew, accountDetails) = _recordObservation(PERIOD_LENGTH, PERIOD_OFFSET, accountDetails, _account);
    }

    unchecked {
      accountDetails.balance -= _amount;
      accountDetails.delegateBalance -= _delegateAmount;
    }

    _account.details = accountDetails;
  }

  /**
   * @notice Looks up the oldest observation in the circular buffer.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @return index The index of the oldest observation
   * @return observation The oldest observation in the circular buffer
   */
  function getOldestObservation(
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails
  ) internal view returns (uint16 index, ObservationLib.Observation memory observation) {
    // If the circular buffer has not been fully populated, we go to the beginning of the buffer at index 0.
    if (_accountDetails.cardinality < MAX_CARDINALITY) {
      index = 0;
      observation = _observations[0];
    } else {
      index = _accountDetails.nextObservationIndex;
      observation = _observations[index];
    }
  }

  /**
   * @notice Looks up the newest observation in the circular buffer.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @return index The index of the newest observation
   * @return observation The newest observation in the circular buffer
   */
  function getNewestObservation(
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails
  ) internal view returns (uint16 index, ObservationLib.Observation memory observation) {
    index = uint16(
      RingBufferLib.newestIndex(_accountDetails.nextObservationIndex, MAX_CARDINALITY)
    );
    observation = _observations[index];
  }

  /**
   * @notice Looks up a users balance at a specific time in the past. The time must be before the current overwrite period.
   * @dev Ensure timestamps are safe using requireFinalized
   * @param PERIOD_LENGTH The length of an overwrite period
   * @param PERIOD_OFFSET The offset of the first period
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _targetTime The time to look up the balance at
   * @return balance The balance at the target time
   */
  function getBalanceAt(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint48 _targetTime
  ) internal requireFinalized(PERIOD_LENGTH, PERIOD_OFFSET, _targetTime) view returns (uint256) {
    (ObservationLib.Observation memory prevOrAtObservation, uint16 index, bool isBeforeHistory) = _getPreviousOrAtObservation(
      PERIOD_OFFSET,
      _observations,
      _accountDetails,
      _targetTime
    );
    if (isBeforeHistory) {
      return 0;
    } else {
      return _getBalanceOf(_observations, _accountDetails, prevOrAtObservation, index);
    }
  }

  /**
   * @notice Looks up a users TWAB for a time range. The time must be before the current overwrite period.
   * @dev If the timestamps in the range are not exact matches of observations, the balance is extrapolated using the previous observation.
   * @param PERIOD_LENGTH The length of an overwrite period
   * @param PERIOD_OFFSET The offset of the first period
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _startTime The start of the time range
   * @param _endTime The end of the time range
   * @return twab The TWAB for the time range
   */
  function getTwabBetween(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint48 _startTime,
    uint48 _endTime
  ) internal view requireFinalized(PERIOD_LENGTH, PERIOD_OFFSET, _endTime) returns (uint256) {
    if (_startTime > _endTime) {
      revert InvalidTimeRange(_startTime, _endTime);
    }

    (ObservationLib.Observation memory endObservation,uint16 endIndex,) = _getPreviousOrAtObservation(
      PERIOD_OFFSET,
      _observations,
      _accountDetails,
      _endTime
    );

    if (_startTime == _endTime) {
      return _getBalanceOf(_observations, _accountDetails, endObservation, endIndex);
    }

    (ObservationLib.Observation memory startObservation,uint16 startIndex,) = _getPreviousOrAtObservation(
      PERIOD_OFFSET,
      _observations,
      _accountDetails,
      _startTime
    );

    if (startObservation.timestamp != _startTime) {
      startObservation = _calculateTemporaryObservation(_observations, _accountDetails, startObservation, startIndex, _startTime);
    }

    if (endObservation.timestamp != _endTime) {
      endObservation = _calculateTemporaryObservation(_observations, _accountDetails, endObservation, endIndex, _endTime);
    }

    // Difference in amount / time
    return
      (endObservation.cumulativeBalance - startObservation.cumulativeBalance) /
      (_endTime - _startTime);
  }

  function _getBalanceOf(
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    ObservationLib.Observation memory _observation,
    uint32 _observationIndex
  ) internal view returns (uint160) {
    uint32 nextIndex = uint32(RingBufferLib.nextIndex(_observationIndex, MAX_CARDINALITY));
    ObservationLib.Observation memory nextObservation = _observations[nextIndex];

    // if there is no next observation, then they never held a balance previously.
    if (nextObservation.timestamp == 0 || nextObservation.timestamp < _observation.timestamp) {
      return _accountDetails.delegateBalance;
    } else { // compute the balance
      // compute the balance using the twab in reverse
      return (nextObservation.cumulativeBalance - _observation.cumulativeBalance) /
        (nextObservation.timestamp - _observation.timestamp);
    }
  }

  /**
   * @notice Given an AccountDetails with updated balances, either updates the latest Observation or records a new one
   * @param PERIOD_LENGTH The overwrite period length
   * @param PERIOD_OFFSET The overwrite period offset
   * @param _accountDetails The updated account details
   * @param _account The account to update
   * @return observation The new/updated observation
   * @return isNew Whether or not the observation is new or overwrote a previous one
   * @return newAccountDetails The new account details
   */
  function _recordObservation(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    AccountDetails memory _accountDetails,
    Account storage _account
  ) internal returns (ObservationLib.Observation memory observation, bool isNew, AccountDetails memory newAccountDetails) {
    uint32 currentTime = uint32(block.timestamp);
    
    uint16 nextIndex;
    ObservationLib.Observation memory newestObservation;
    (nextIndex, newestObservation, isNew) = _getNextObservationIndex(
      PERIOD_LENGTH,
      PERIOD_OFFSET,
      _account.observations,
      _accountDetails
    );

    if (isNew) {
      // If the index is new, then we increase the next index to use
      _accountDetails.nextObservationIndex = uint16(
        RingBufferLib.nextIndex(uint256(nextIndex), MAX_CARDINALITY)
      );

      // Prevent the Account specific cardinality from exceeding the MAX_CARDINALITY.
      // The ring buffer length is limited by MAX_CARDINALITY. IF the account.cardinality
      // exceeds the max cardinality, new observations would be incorrectly set or the
      // observation would be out of "bounds" of the ring buffer. Once reached the
      // Account.cardinality will continue to be equal to max cardinality.
      _accountDetails.cardinality = _accountDetails.cardinality < MAX_CARDINALITY ? _accountDetails.cardinality + 1 : MAX_CARDINALITY;
    }

    observation = ObservationLib.Observation({
      cumulativeBalance: _extrapolateFromBalance(newestObservation, _accountDetails.delegateBalance, currentTime),
      timestamp: currentTime
    });

    // Write to storage
    _account.observations[nextIndex] = observation;
    newAccountDetails = _accountDetails;
  }

  /**
   * @notice Calculates a temporary observation for a given time using the previous observation.
   * @dev This is used to extrapolate a balance for any given time.
   * @param _observation The previous observation
   * @param _observationIndex The index of the previous observation
   * @param _time The time to extrapolate to
   * @return observation The observation
   */
  function _calculateTemporaryObservation(
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    ObservationLib.Observation memory _observation,
    uint16 _observationIndex,
    uint48 _time
  ) private view returns (ObservationLib.Observation memory) {
    uint160 balance = _getBalanceOf(_observations, _accountDetails, _observation, _observationIndex);
    return
      ObservationLib.Observation({
        cumulativeBalance: _extrapolateFromBalance(_observation, balance, _time),
        timestamp: _time
      });
  }

  /**
   * @notice Looks up the next observation index to write to in the circular buffer.
   * @dev If the current time is in the same period as the newest observation, we overwrite it.
   * @dev If the current time is in a new period, we increment the index and write a new observation.
   * @param PERIOD_LENGTH The length of an overwrite period
   * @param PERIOD_OFFSET The offset of the first period
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @return index The index of the next observation slot to overwrite
   * @return newestObservation The newest observation in the circular buffer
   * @return isNew Whether or not the observation is new
   */
  function _getNextObservationIndex(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails
  )
    private
    view
    returns (uint16 index, ObservationLib.Observation memory newestObservation, bool isNew)
  {
    uint16 newestIndex;
    (newestIndex, newestObservation) = getNewestObservation(_observations, _accountDetails);

    // if we're in the same block, return
    if (newestObservation.timestamp == block.timestamp) {
      return (newestIndex, newestObservation, false);
    }

    uint48 currentPeriod = _getTimestampPeriod(PERIOD_LENGTH, PERIOD_OFFSET, uint48(block.timestamp));

    uint48 newestObservationPeriod = _getTimestampPeriod(
      PERIOD_LENGTH,
      PERIOD_OFFSET,
      newestObservation.timestamp
    );

    // Create a new Observation if it's the first period or the current time falls within a new period
    if (_accountDetails.cardinality == 0 || currentPeriod > newestObservationPeriod) {
      return (
        _accountDetails.nextObservationIndex,
        newestObservation,
        true
      );
    }

    // Otherwise, we're overwriting the current newest Observation
    return (newestIndex, newestObservation, false);
  }

  /**
   * @notice Computes the start time of the current overwrite period
   * @param PERIOD_LENGTH The length of an overwrite period
   * @param PERIOD_OFFSET The offset of the first period
   * @return The start time of the current overwrite period
   */
  function _currentOverwritePeriodStartedAt(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET
  ) private view returns (uint48) {
    uint48 period = getTimestampPeriod(PERIOD_LENGTH, PERIOD_OFFSET, uint48(block.timestamp));
    return getPeriodStartTime(PERIOD_LENGTH, PERIOD_OFFSET, period);
  }

  /**
   * @notice Calculates the next cumulative balance using a provided Observation and timestamp.
   * @param _observation The observation to extrapolate from
   * @param _timestamp The timestamp to extrapolate to
   * @return cumulativeBalance The cumulative balance at the timestamp
   */
  function _extrapolateFromBalance(
    ObservationLib.Observation memory _observation,
    uint160 _balance,
    uint48 _timestamp
  ) private pure returns (uint160 cumulativeBalance) {
    // new cumulative balance = provided cumulative balance (or zero) + (current balance * elapsed seconds)
    return
      _observation.cumulativeBalance +
      _balance *
      (_timestamp - _observation.timestamp);
  }

  /**
   * @notice Calculates the period a timestamp falls within.
   * @dev All timestamps prior to the PERIOD_OFFSET fall within period 0.
   * @param PERIOD_LENGTH The length of an overwrite period
   * @param PERIOD_OFFSET The offset of the first period
   * @param _timestamp The timestamp to calculate the period for
   * @return period The period
   */
  function getTimestampPeriod(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    uint48 _timestamp
  ) internal pure returns (uint48 period) {
    return _getTimestampPeriod(PERIOD_LENGTH, PERIOD_OFFSET, _timestamp);
  }

  /**
   * @notice Computes the overwrite period start time given the current time
   * @param PERIOD_LENGTH The length of an overwrite period
   * @param PERIOD_OFFSET The offset of the first period
   * @return The start time for the current overwrite period.
   */
  function currentOverwritePeriodStartedAt(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET
  ) internal view returns (uint48) {
    return _currentOverwritePeriodStartedAt(PERIOD_LENGTH, PERIOD_OFFSET);
  }

  /**
   * @notice Calculates the period a timestamp falls within.
   * @dev Timestamp prior to the PERIOD_OFFSET are considered to be in period 0.
   * @param PERIOD_LENGTH The length of an overwrite period
   * @param PERIOD_OFFSET The offset of the first period
   * @param _timestamp The timestamp to calculate the period for
   * @return period The period
   */
  function _getTimestampPeriod(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    uint48 _timestamp
  ) private pure returns (uint48) {
    if (_timestamp <= PERIOD_OFFSET) {
      return 0;
    }
    return (_timestamp - PERIOD_OFFSET) / PERIOD_LENGTH;
  }

  /**
   * @notice Calculates the start timestamp for a period
   * @param PERIOD_LENGTH The period length to use to calculate the period
   * @param PERIOD_OFFSET The period offset to use to calculate the period
   * @param _period The period to check
   * @return _timestamp The timestamp at which the period starts
   */
  function getPeriodStartTime(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    uint48 _period
  ) internal pure returns (uint48) {
    return _period * PERIOD_LENGTH + PERIOD_OFFSET;
  }

  /**
   * @notice Calculates the last timestamp for a period
   * @param PERIOD_LENGTH The period length to use to calculate the period
   * @param PERIOD_OFFSET The period offset to use to calculate the period
   * @param _period The period to check
   * @return _timestamp The timestamp at which the period ends
   */
  function getPeriodEndTime(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    uint48 _period
  ) internal pure returns (uint48) {
    return (_period+1) * PERIOD_LENGTH + PERIOD_OFFSET;
  }

  /**
   * @notice Looks up the newest observation before or at a given timestamp.
   * @dev If an observation is available at the target time, it is returned. Otherwise, the newest observation before the target time is returned.
   * @param PERIOD_OFFSET The period offset to use to calculate the period
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _targetTime The timestamp to look up
   * @return prevOrAtObservation The observation
   */
  function getPreviousOrAtObservation(
    uint48 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint48 _targetTime
  ) internal view returns (ObservationLib.Observation memory prevOrAtObservation) {
    (prevOrAtObservation,,) = _getPreviousOrAtObservation(PERIOD_OFFSET, _observations, _accountDetails, _targetTime);
  }

  /**
   * @notice Looks up the newest observation before or at a given timestamp.
   * @dev If an observation is available at the target time, it is returned. Otherwise, the newest observation before the target time is returned.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _targetTime The timestamp to look up
   * @return prevOrAtObservation The observation
   */
  function _getPreviousOrAtObservation(
    uint48 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint48 _targetTime
  ) private view returns (ObservationLib.Observation memory, uint16, bool) {
    ObservationLib.Observation memory prevOrAtObservation;
    uint16 oldestTwabIndex;

    // If there are no observations, return a zeroed observation
    if (_accountDetails.cardinality == 0) {
      return (
        ObservationLib.Observation({ cumulativeBalance: 0, timestamp: PERIOD_OFFSET }),
        0,
        true
      );
    }
    
    uint32 currentTime = uint32(block.timestamp);
    uint16 oldestTwabIndex;

    (oldestTwabIndex, prevOrAtObservation) = getOldestObservation(_observations, _accountDetails);
    
    // if the requested time is older than the oldest observation
    if (_targetTime < prevOrAtObservation.timestamp) { 
      // if the user didn't have any activity prior to the oldest observation, then we know they had a zero balance
      if (_accountDetails.cardinality < MAX_CARDINALITY) {
        return (
          ObservationLib.Observation({ cumulativeBalance: 0, timestamp: _targetTime }),
          0,
          true
        );
      } else {
        // if we are missing their history, we must revert
        revert InsufficientHistory(_targetTime, prevOrAtObservation.timestamp);
      }
    }

    // We know targetTime >= oldestObservation.timestamp because of the above if statement, so we can return here.
    if (_accountDetails.cardinality == 1) {
      return (
        prevOrAtObservation,
        oldestTwabIndex,
        false
      );
    }

    uint16 newestTwabIndex;
    ObservationLib.Observation memory afterOrAtObservation;

    // Find the newest observation
    (newestTwabIndex, afterOrAtObservation) = getNewestObservation(_observations, _accountDetails);
    // if the target time is at or after the newest, return it
    if (_targetTime >= afterOrAtObservation.timestamp) {
      return (afterOrAtObservation, newestTwabIndex, false);
    }
    // if we know there is only 1 observation older than the newest
    if (_accountDetails.cardinality == 2) {
      return (prevOrAtObservation, oldestTwabIndex, false);
    }

    // Otherwise, we perform a binarySearch to find the observation before or at the timestamp
    (prevOrAtObservation, oldestTwabIndex, afterOrAtObservation, newestTwabIndex) = ObservationLib.binarySearch(
      _observations,
      newestTwabIndex,
      oldestTwabIndex,
      _targetTime,
      _accountDetails.cardinality
    );

    // If the afterOrAt is at, we can skip a temporary Observation computation by returning it here
    if (afterOrAtObservation.timestamp == _targetTime) {
      return (afterOrAtObservation, newestTwabIndex, false);
    }

    return (prevOrAtObservation, oldestTwabIndex, false);
  }

  /**
   * @notice Checks if the given timestamp is safe to perform a historic balance lookup on.
   * @dev A timestamp is safe if it is before the current overwrite period
   * @param PERIOD_LENGTH The period length to use to calculate the period
   * @param PERIOD_OFFSET The period offset to use to calculate the period
   * @param _time The timestamp to check
   * @return isSafe Whether or not the timestamp is safe
   */
  function hasFinalized(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    uint48 _time
  ) internal view returns (bool) {
    return _hasFinalized(PERIOD_LENGTH, PERIOD_OFFSET, _time);
  }

  /**
   * @notice Checks if the given timestamp is safe to perform a historic balance lookup on.
   * @dev A timestamp is safe if it is on or before the current overwrite period start time
   * @param PERIOD_LENGTH The period length to use to calculate the period
   * @param PERIOD_OFFSET The period offset to use to calculate the period
   * @param _time The timestamp to check
   * @return isSafe Whether or not the timestamp is safe
   */
  function _hasFinalized(
    uint48 PERIOD_LENGTH,
    uint48 PERIOD_OFFSET,
    uint48 _time
  ) private view returns (bool) {
    // It's safe if equal to the overwrite period start time, because the cumulative balance won't be impacted
    return _time <= _currentOverwritePeriodStartedAt(PERIOD_LENGTH, PERIOD_OFFSET);
  }

  /**
   * @notice Checks if the given timestamp is safe to perform a historic balance lookup on.
   * @param PERIOD_LENGTH The period length to use to calculate the period
   * @param PERIOD_OFFSET The period offset to use to calculate the period
   * @param _timestamp The timestamp to check
   */
  modifier requireFinalized(uint48 PERIOD_LENGTH, uint48 PERIOD_OFFSET, uint256 _timestamp) {
    // The current period can still be changed; so the start of the period marks the beginning of unsafe timestamps.
    uint48 overwritePeriodStartTime = _currentOverwritePeriodStartedAt(PERIOD_LENGTH, PERIOD_OFFSET);
    // timestamp == overwritePeriodStartTime doesn't matter, because the cumulative balance won't be impacted
    if (_timestamp > overwritePeriodStartTime) {
      revert TimestampNotFinalized(_timestamp, overwritePeriodStartTime);
    }
    _;
  }
}
