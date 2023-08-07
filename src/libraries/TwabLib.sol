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
error BalanceLTAmount(uint112 balance, uint96 amount, string message);

/// @notice Emitted when a delegate balance is decreased by an amount that exceeds the amount available.
/// @param delegateBalance The current delegate balance of the account
/// @param delegateAmount The amount being decreased from the account's delegate balance
/// @param message An additional message describing the error
error DelegateBalanceLTAmount(uint112 delegateBalance, uint96 delegateAmount, string message);

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
    ObservationLib.Observation[365] observations;
  }

  /**
   * @notice Increase a user's balance and delegate balance by a given amount.
   * @dev This function mutates the provided account.
   * @param _account The account to update
   * @param _amount The amount to increase the balance by
   * @param _delegateAmount The amount to increase the delegate balance by
   * @return observation The new/updated observation
   * @return isNew Whether or not the observation is new or overwrote a previous one
   * @return isObservationRecorded Whether or not the observation was recorded to storage
   */
  function increaseBalances(
    uint32 PERIOD_LENGTH,
    uint32 PERIOD_OFFSET,
    Account storage _account,
    uint96 _amount,
    uint96 _delegateAmount
  )
    internal
    returns (ObservationLib.Observation memory observation, bool isNew, bool isObservationRecorded)
  {
    AccountDetails memory accountDetails = _account.details;
    uint32 currentTime = uint32(block.timestamp);
    uint32 index;
    ObservationLib.Observation memory newestObservation;
    isObservationRecorded = _delegateAmount != uint96(0);

    accountDetails.balance += _amount;
    accountDetails.delegateBalance += _delegateAmount;

    // Only record a new Observation if the users delegateBalance has changed.
    if (isObservationRecorded) {
      (index, newestObservation, isNew) = _getNextObservationIndex(
        PERIOD_LENGTH,
        PERIOD_OFFSET,
        _account.observations,
        accountDetails
      );

      if (isNew) {
        // If the index is new, then we increase the next index to use
        accountDetails.nextObservationIndex = uint16(
          RingBufferLib.nextIndex(uint256(index), MAX_CARDINALITY)
        );

        // Prevent the Account specific cardinality from exceeding the MAX_CARDINALITY.
        // The ring buffer length is limited by MAX_CARDINALITY. IF the account.cardinality
        // exceeds the max cardinality, new observations would be incorrectly set or the
        // observation would be out of "bounds" of the ring buffer. Once reached the
        // Account.cardinality will continue to be equal to max cardinality.
        if (accountDetails.cardinality < MAX_CARDINALITY) {
          accountDetails.cardinality += 1;
        }
      }

      observation = ObservationLib.Observation({
        balance: SafeCast.toUint96(accountDetails.delegateBalance),
        cumulativeBalance: _extrapolateFromBalance(newestObservation, currentTime),
        timestamp: currentTime
      });

      // Write to storage
      _account.observations[index] = observation;
    }

    // Write to storage
    _account.details = accountDetails;
  }

  /**
   * @notice Decrease a user's balance and delegate balance by a given amount.
   * @dev This function mutates the provided account.
   * @param _account The account to update
   * @param _amount The amount to decrease the balance by
   * @param _delegateAmount The amount to decrease the delegate balance by
   * @param _revertMessage The revert message to use if the balance is insufficient
   * @return observation The new/updated observation
   * @return isNew Whether or not the observation is new or overwrote a previous one
   * @return isObservationRecorded Whether or not the observation was recorded to storage
   */
  function decreaseBalances(
    uint32 PERIOD_LENGTH,
    uint32 PERIOD_OFFSET,
    Account storage _account,
    uint96 _amount,
    uint96 _delegateAmount,
    string memory _revertMessage
  )
    internal
    returns (ObservationLib.Observation memory observation, bool isNew, bool isObservationRecorded)
  {
    AccountDetails memory accountDetails = _account.details;

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

    uint32 currentTime = uint32(block.timestamp);
    uint32 index;
    ObservationLib.Observation memory newestObservation;
    isObservationRecorded = _delegateAmount != uint96(0);

    unchecked {
      accountDetails.balance -= _amount;
      accountDetails.delegateBalance -= _delegateAmount;
    }

    // Only record a new Observation if the users delegateBalance has changed.
    if (isObservationRecorded) {
      (index, newestObservation, isNew) = _getNextObservationIndex(
        PERIOD_LENGTH,
        PERIOD_OFFSET,
        _account.observations,
        accountDetails
      );

      if (isNew) {
        // If the index is new, then we increase the next index to use
        accountDetails.nextObservationIndex = uint16(
          RingBufferLib.nextIndex(uint256(index), MAX_CARDINALITY)
        );

        // Prevent the Account specific cardinality from exceeding the MAX_CARDINALITY.
        // The ring buffer length is limited by MAX_CARDINALITY. IF the account.cardinality
        // exceeds the max cardinality, new observations would be incorrectly set or the
        // observation would be out of "bounds" of the ring buffer. Once reached the
        // Account.cardinality will continue to be equal to max cardinality.
        if (accountDetails.cardinality < MAX_CARDINALITY) {
          accountDetails.cardinality += 1;
        }
      }

      observation = ObservationLib.Observation({
        balance: SafeCast.toUint96(accountDetails.delegateBalance),
        cumulativeBalance: _extrapolateFromBalance(newestObservation, currentTime),
        timestamp: currentTime
      });

      // Write to storage
      _account.observations[index] = observation;
    }
    // Write to storage
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
   * @notice Looks up a users balance at a specific time in the past.
   * @dev If the time is not an exact match of an observation, the balance is extrapolated using the previous observation.
   * @dev Ensure timestamps are safe using isTimeSafe or by ensuring you're querying a multiple of the observation period intervals.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _targetTime The time to look up the balance at
   * @return balance The balance at the target time
   */
  function getBalanceAt(
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _targetTime
  ) internal view returns (uint256) {
    ObservationLib.Observation memory prevOrAtObservation = _getPreviousOrAtObservation(
      PERIOD_OFFSET,
      _observations,
      _accountDetails,
      _targetTime
    );
    return prevOrAtObservation.balance;
  }

  /**
   * @notice Looks up a users TWAB for a time range.
   * @dev If the timestamps in the range are not exact matches of observations, the balance is extrapolated using the previous observation.
   * @dev Ensure timestamps are safe using isTimeRangeSafe.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _startTime The start of the time range
   * @param _endTime The end of the time range
   * @return twab The TWAB for the time range
   */
  function getTwabBetween(
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _startTime,
    uint32 _endTime
  ) internal view returns (uint256) {
    ObservationLib.Observation memory startObservation = _getPreviousOrAtObservation(
      PERIOD_OFFSET,
      _observations,
      _accountDetails,
      _startTime
    );

    ObservationLib.Observation memory endObservation = _getPreviousOrAtObservation(
      PERIOD_OFFSET,
      _observations,
      _accountDetails,
      _endTime
    );

    if (startObservation.timestamp != _startTime) {
      startObservation = _calculateTemporaryObservation(startObservation, _startTime);
    }

    if (endObservation.timestamp != _endTime) {
      endObservation = _calculateTemporaryObservation(endObservation, _endTime);
    }

    // Difference in amount / time
    return
      (endObservation.cumulativeBalance - startObservation.cumulativeBalance) /
      (_endTime - _startTime);
  }

  /**
   * @notice Calculates a temporary observation for a given time using the previous observation.
   * @dev This is used to extrapolate a balance for any given time.
   * @param _prevObservation The previous observation
   * @param _time The time to extrapolate to
   * @return observation The observation
   */
  function _calculateTemporaryObservation(
    ObservationLib.Observation memory _prevObservation,
    uint32 _time
  ) private pure returns (ObservationLib.Observation memory) {
    return
      ObservationLib.Observation({
        balance: _prevObservation.balance,
        cumulativeBalance: _extrapolateFromBalance(_prevObservation, _time),
        timestamp: _time
      });
  }

  /**
   * @notice Looks up the next observation index to write to in the circular buffer.
   * @dev If the current time is in the same period as the newest observation, we overwrite it.
   * @dev If the current time is in a new period, we increment the index and write a new observation.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @return index The index of the next observation
   * @return newestObservation The newest observation in the circular buffer
   * @return isNew Whether or not the observation is new
   */
  function _getNextObservationIndex(
    uint32 PERIOD_LENGTH,
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails
  )
    private
    view
    returns (uint16 index, ObservationLib.Observation memory newestObservation, bool isNew)
  {
    uint32 currentTime = uint32(block.timestamp);
    uint16 newestIndex;
    (newestIndex, newestObservation) = getNewestObservation(_observations, _accountDetails);

    // if we're in the same block, return
    if (newestObservation.timestamp == currentTime) {
      return (newestIndex, newestObservation, false);
    }

    uint32 currentPeriod = _getTimestampPeriod(PERIOD_LENGTH, PERIOD_OFFSET, currentTime);
    uint32 newestObservationPeriod = _getTimestampPeriod(
      PERIOD_LENGTH,
      PERIOD_OFFSET,
      newestObservation.timestamp
    );

    // TODO: Could skip this check for period 0 if we're sure that the PERIOD_OFFSET is in the past.
    // Create a new Observation if the current time falls within a new period
    // Or if the timestamp is the initial period.
    if (currentPeriod == 0 || currentPeriod > newestObservationPeriod) {
      return (
        uint16(RingBufferLib.wrap(_accountDetails.nextObservationIndex, MAX_CARDINALITY)),
        newestObservation,
        true
      );
    }

    // Otherwise, we're overwriting the current newest Observation
    return (newestIndex, newestObservation, false);
  }

  /**
   * @notice Calculates the next cumulative balance using a provided Observation and timestamp.
   * @param _observation The observation to extrapolate from
   * @param _timestamp The timestamp to extrapolate to
   * @return cumulativeBalance The cumulative balance at the timestamp
   */
  function _extrapolateFromBalance(
    ObservationLib.Observation memory _observation,
    uint32 _timestamp
  ) private pure returns (uint128 cumulativeBalance) {
    // new cumulative balance = provided cumulative balance (or zero) + (current balance * elapsed seconds)
    return
      _observation.cumulativeBalance +
      uint128(_observation.balance) *
      (_timestamp.checkedSub(_observation.timestamp, _timestamp));
  }

  /**
   * @notice Calculates the period a timestamp falls within.
   * @dev All timestamps prior to the PERIOD_OFFSET fall within period 0.
   * @param PERIOD_LENGTH The period length to use to calculate the period
   * @param PERIOD_OFFSET The period offset to use to calculate the period
   * @param _timestamp The timestamp to calculate the period for
   * @return period The period
   */
  function getTimestampPeriod(
    uint32 PERIOD_LENGTH,
    uint32 PERIOD_OFFSET,
    uint32 _timestamp
  ) internal pure returns (uint32 period) {
    return _getTimestampPeriod(PERIOD_LENGTH, PERIOD_OFFSET, _timestamp);
  }

  /**
   * @notice Calculates the period a timestamp falls within.
   * @dev All timestamps prior to the PERIOD_OFFSET fall within period 0. PERIOD_OFFSET + 1 seconds is the start of period 1.
   * @dev All timestamps landing on multiples of PERIOD_LENGTH are the ends of periods.
   * @param PERIOD_LENGTH The period length to use to calculate the period
   * @param PERIOD_OFFSET The period offset to use to calculate the period
   * @param _timestamp The timestamp to calculate the period for
   * @return period The period
   */
  function _getTimestampPeriod(
    uint32 PERIOD_LENGTH,
    uint32 PERIOD_OFFSET,
    uint32 _timestamp
  ) private pure returns (uint32 period) {
    if (_timestamp <= PERIOD_OFFSET) {
      return 0;
    }
    // Shrink by 1 to ensure periods end on a multiple of PERIOD_LENGTH.
    // Increase by 1 to start periods at # 1.
    return ((_timestamp - PERIOD_OFFSET - 1) / PERIOD_LENGTH) + 1;
  }

  /**
   * @notice Looks up the newest observation before or at a given timestamp.
   * @dev If an observation is available at the target time, it is returned. Otherwise, the newest observation before the target time is returned.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _targetTime The timestamp to look up
   * @return prevOrAtObservation The observation
   */
  function getPreviousOrAtObservation(
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _targetTime
  ) internal view returns (ObservationLib.Observation memory prevOrAtObservation) {
    return _getPreviousOrAtObservation(PERIOD_OFFSET, _observations, _accountDetails, _targetTime);
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
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _targetTime
  ) private view returns (ObservationLib.Observation memory prevOrAtObservation) {
    uint32 currentTime = uint32(block.timestamp);

    uint16 oldestTwabIndex;
    uint16 newestTwabIndex;

    // If there are no observations, return a zeroed observation
    if (_accountDetails.cardinality == 0) {
      return
        ObservationLib.Observation({ cumulativeBalance: 0, balance: 0, timestamp: PERIOD_OFFSET });
    }

    // Find the newest observation and check if the target time is AFTER it
    (newestTwabIndex, prevOrAtObservation) = getNewestObservation(_observations, _accountDetails);
    if (_targetTime >= prevOrAtObservation.timestamp) {
      return prevOrAtObservation;
    }

    // If there is only 1 actual observation, either return that observation or a zeroed observation
    if (_accountDetails.cardinality == 1) {
      if (_targetTime >= prevOrAtObservation.timestamp) {
        return prevOrAtObservation;
      } else {
        return
          ObservationLib.Observation({
            cumulativeBalance: 0,
            balance: 0,
            timestamp: PERIOD_OFFSET
          });
      }
    }

    // Find the oldest Observation and check if the target time is BEFORE it
    (oldestTwabIndex, prevOrAtObservation) = getOldestObservation(_observations, _accountDetails);
    if (_targetTime < prevOrAtObservation.timestamp) {
      return
        ObservationLib.Observation({ cumulativeBalance: 0, balance: 0, timestamp: PERIOD_OFFSET });
    }

    ObservationLib.Observation memory afterOrAtObservation;
    // Otherwise, we perform a binarySearch to find the observation before or at the timestamp
    (prevOrAtObservation, afterOrAtObservation) = ObservationLib.binarySearch(
      _observations,
      newestTwabIndex,
      oldestTwabIndex,
      _targetTime,
      _accountDetails.cardinality,
      currentTime
    );

    // If the afterOrAt is at, we can skip a temporary Observation computation by returning it here
    if (afterOrAtObservation.timestamp == _targetTime) {
      return afterOrAtObservation;
    }

    return prevOrAtObservation;
  }

  /**
   * @notice Looks up the next observation after a given timestamp.
   * @dev If the requested time is at or after the newest observation, then the newest is returned.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _targetTime The timestamp to look up
   * @return nextOrNewestObservation The observation
   */
  function getNextOrNewestObservation(
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _targetTime
  ) internal view returns (ObservationLib.Observation memory nextOrNewestObservation) {
    return _getNextOrNewestObservation(PERIOD_OFFSET, _observations, _accountDetails, _targetTime);
  }

  /**
   * @notice Looks up the next observation after a given timestamp.
   * @dev If the requested time is at or after the newest observation, then the newest is returned.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _targetTime The timestamp to look up
   * @return nextOrNewestObservation The observation
   */
  function _getNextOrNewestObservation(
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _targetTime
  ) private view returns (ObservationLib.Observation memory nextOrNewestObservation) {
    uint32 currentTime = uint32(block.timestamp);

    uint16 oldestTwabIndex;

    // If there are no observations, return a zeroed observation
    if (_accountDetails.cardinality == 0) {
      return
        ObservationLib.Observation({ cumulativeBalance: 0, balance: 0, timestamp: PERIOD_OFFSET });
    }

    // Find the oldest Observation and check if the target time is BEFORE it
    (oldestTwabIndex, nextOrNewestObservation) = getOldestObservation(
      _observations,
      _accountDetails
    );
    if (_targetTime < nextOrNewestObservation.timestamp) {
      return nextOrNewestObservation;
    }

    // If there is only 1 observation and the time is at or after (checked above), return a zeroed observation
    if (_accountDetails.cardinality == 1) {
      return
        ObservationLib.Observation({ cumulativeBalance: 0, balance: 0, timestamp: PERIOD_OFFSET });
    }

    // Find the newest observation and check if the target time is AFTER it
    (
      uint16 newestTwabIndex,
      ObservationLib.Observation memory newestObservation
    ) = getNewestObservation(_observations, _accountDetails);
    if (_targetTime >= newestObservation.timestamp) {
      return newestObservation;
    }

    ObservationLib.Observation memory beforeOrAt;
    // Otherwise, we perform a binarySearch to find the observation before or at the timestamp
    (beforeOrAt, nextOrNewestObservation) = ObservationLib.binarySearch(
      _observations,
      newestTwabIndex,
      oldestTwabIndex,
      _targetTime + 1 seconds, // Increase by 1 second to ensure we get the next observation
      _accountDetails.cardinality,
      currentTime
    );

    if (beforeOrAt.timestamp > _targetTime) {
      return beforeOrAt;
    }

    return nextOrNewestObservation;
  }

  /**
   * @notice Looks up the previous and next observations for a given timestamp.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _targetTime The timestamp to look up
   * @return prevOrAtObservation The observation before or at the timestamp
   * @return nextOrNewestObservation The observation after the timestamp or the newest observation.
   */
  function _getSurroundingOrAtObservations(
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _targetTime
  )
    private
    view
    returns (
      ObservationLib.Observation memory prevOrAtObservation,
      ObservationLib.Observation memory nextOrNewestObservation
    )
  {
    prevOrAtObservation = _getPreviousOrAtObservation(
      PERIOD_OFFSET,
      _observations,
      _accountDetails,
      _targetTime
    );
    nextOrNewestObservation = _getNextOrNewestObservation(
      PERIOD_OFFSET,
      _observations,
      _accountDetails,
      _targetTime
    );
  }

  /**
   * @notice Checks if the given timestamp is safe to perform a historic balance lookup on.
   * @dev A timestamp is safe if it is between (or at) the newest observation in a period and the end of the period.
   * @dev If the time being queried is in a period that has not yet ended, the output for this function may change.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _time The timestamp to check
   * @return isSafe Whether or not the timestamp is safe
   */
  function isTimeSafe(
    uint32 PERIOD_LENGTH,
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _time
  ) internal view returns (bool) {
    return _isTimeSafe(PERIOD_LENGTH, PERIOD_OFFSET, _observations, _accountDetails, _time);
  }

  /**
   * @notice Checks if the given timestamp is safe to perform a historic balance lookup on.
   * @dev A timestamp is safe if it is between (or at) the newest observation in a period and the end of the period.
   * @dev If the time being queried is in a period that has not yet ended, the output for this function may change.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _time The timestamp to check
   * @return isSafe Whether or not the timestamp is safe
   */
  function _isTimeSafe(
    uint32 PERIOD_LENGTH,
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _time
  ) private view returns (bool) {
    // If there are no observations, it's an unsafe range
    if (_accountDetails.cardinality == 0) {
      return false;
    }
    // If there is one observation, compare it's timestamp
    uint32 period = _getTimestampPeriod(PERIOD_LENGTH, PERIOD_OFFSET, _time);

    if (_accountDetails.cardinality == 1) {
      return
        period != _getTimestampPeriod(PERIOD_LENGTH, PERIOD_OFFSET, _observations[0].timestamp)
          ? true
          : _time >= _observations[0].timestamp;
    }
    ObservationLib.Observation memory preOrAtObservation;
    ObservationLib.Observation memory nextOrNewestObservation;

    (, nextOrNewestObservation) = getNewestObservation(_observations, _accountDetails);

    if (_time >= nextOrNewestObservation.timestamp) {
      return true;
    }

    (preOrAtObservation, nextOrNewestObservation) = _getSurroundingOrAtObservations(
      PERIOD_OFFSET,
      _observations,
      _accountDetails,
      _time
    );

    uint32 preOrAtPeriod = _getTimestampPeriod(
      PERIOD_LENGTH,
      PERIOD_OFFSET,
      preOrAtObservation.timestamp
    );
    uint32 postPeriod = _getTimestampPeriod(
      PERIOD_LENGTH,
      PERIOD_OFFSET,
      nextOrNewestObservation.timestamp
    );

    // The observation after it falls in a new period
    return period >= preOrAtPeriod && period < postPeriod;
  }

  /**
   * @notice Checks if the given time range is safe to perform a historic balance lookup on.
   * @dev A timestamp is safe if it is between (or at) the newest observation in a period and the end of the period.
   * @dev If the endtime being queried is in a period that has not yet ended, the output for this function may change.
   * @param _observations The circular buffer of observations
   * @param _accountDetails The account details to query with
   * @param _startTime The start of the time range to check
   * @param _endTime The end of the time range to check
   * @return isSafe Whether or not the time range is safe
   */
  function isTimeRangeSafe(
    uint32 PERIOD_LENGTH,
    uint32 PERIOD_OFFSET,
    ObservationLib.Observation[MAX_CARDINALITY] storage _observations,
    AccountDetails memory _accountDetails,
    uint32 _startTime,
    uint32 _endTime
  ) internal view returns (bool) {
    return
      _isTimeSafe(PERIOD_LENGTH, PERIOD_OFFSET, _observations, _accountDetails, _startTime) &&
      _isTimeSafe(PERIOD_LENGTH, PERIOD_OFFSET, _observations, _accountDetails, _endTime);
  }
}
