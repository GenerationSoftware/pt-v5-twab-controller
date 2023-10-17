// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { RingBufferLib } from "ring-buffer-lib/RingBufferLib.sol";

import { TwabLib } from "../../src/libraries/TwabLib.sol";
import { ObservationLib, MAX_CARDINALITY } from "../../src/libraries/ObservationLib.sol";

contract ObservationLibMock {
  ObservationLib.Observation[MAX_CARDINALITY] observations;

  /**
   * Fills a ring buffer with observations
   * @param _timestamps the timestamps to create
   */
  function populateObservations(uint32[] memory _timestamps) public {
    for (uint i; i < _timestamps.length; i++) {
      observations[RingBufferLib.wrap(i, MAX_CARDINALITY)] = ObservationLib.Observation({
        timestamp: _timestamps[i],
        balance: 0,
        cumulativeBalance: 0
      });
    }
  }

  /**
   * Populates an index in the observarions Ring Buffer
   * @param index the index to update
   * @param observation the data to store
   */
  function updateObservation(
    uint256 index,
    ObservationLib.Observation memory observation
  ) external {
    observations[index] = observation;
  }

  /**
   * @notice Fetches Observations `beforeOrAt` and `afterOrAt` a `_target`, eg: where [`beforeOrAt`, `afterOrAt`] is satisfied.
   * The result may be the same Observation, or adjacent Observations.
   * @param _newestObservationIndex Index of the newest Observation. Right side of the circular buffer.
   * @param _oldestObservationIndex Index of the oldest Observation. Left side of the circular buffer.
   * @param _target Timestamp at which we are searching the Observation.
   * @param _cardinality Cardinality of the circular buffer we are searching through.
   * @return Observation recorded before, or at, the target.
   * @return Observation recorded at, or after, the target.
   */
  function binarySearch(
    uint24 _newestObservationIndex,
    uint24 _oldestObservationIndex,
    uint32 _target,
    uint16 _cardinality
  )
    external
    view
    returns (ObservationLib.Observation memory, uint16, ObservationLib.Observation memory, uint16)
  {
    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = ObservationLib.binarySearch(
        observations,
        _newestObservationIndex,
        _oldestObservationIndex,
        _target,
        _cardinality
      );
    return (beforeOrAt, beforeOrAtIndex, afterOrAt, afterOrAtIndex);
  }
}
