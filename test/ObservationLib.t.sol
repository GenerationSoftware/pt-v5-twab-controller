// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ObservationLib, MAX_CARDINALITY } from "../src/libraries/ObservationLib.sol";
import { RingBufferLib } from "ring-buffer-lib/RingBufferLib.sol";
import { BaseTest } from "./utils/BaseTest.sol";
import { ObservationLibMock } from "./mocks/ObservationLibMock.sol";

contract ObservationLibTest is BaseTest {
  ObservationLibMock public observationLibMock;

  function setUp() public override {
    super.setUp();

    observationLibMock = new ObservationLibMock();
  }

  /* ============ binarySearch ============ */

  function testBinarySearch_HappyPath_beforeOrAt() public {
    uint32[] memory t = new uint32[](6);
    t[0] = 1;
    t[1] = 2;
    t[2] = 3;
    t[3] = 4;
    t[4] = 5;
    t[5] = 6;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 5;
    uint24 oldestObservationIndex = 0;
    uint16 cardinality = uint16(t.length);
    uint32 time = 100;

    // Left side
    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = observationLibMock.binarySearch(
        newestObservationIndex,
        oldestObservationIndex,
        2,
        cardinality
      );

    assertEq(beforeOrAt.timestamp, 1);
    assertEq(afterOrAt.timestamp, 2);

    // Right side
    (beforeOrAt, beforeOrAtIndex, afterOrAt, afterOrAtIndex) = observationLibMock.binarySearch(
      newestObservationIndex,
      oldestObservationIndex,
      5,
      cardinality
    );

    assertEq(beforeOrAt.timestamp, 5);
    assertEq(afterOrAt.timestamp, 6);
  }

  function testBinarySearch_HappyPath_afterOrAt() public {
    uint32[] memory t = new uint32[](6);
    t[0] = 1;
    t[1] = 2;
    t[2] = 3;
    t[3] = 4;
    t[4] = 5;
    t[5] = 6;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 5;
    uint24 oldestObservationIndex = 0;
    uint32 target = 4;
    uint16 cardinality = uint16(t.length);

    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = observationLibMock.binarySearch(
        newestObservationIndex,
        oldestObservationIndex,
        target,
        cardinality
      );

    assertEq(beforeOrAt.timestamp, target - 1);
    assertEq(afterOrAt.timestamp, target);
  }

  // Outside of range
  function testFailBinarySearch_OneItem_TargetBefore() public {
    uint32[] memory t = new uint32[](1);
    t[0] = 10;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 0;
    uint24 oldestObservationIndex = 0;
    uint32 target = 5;
    uint16 cardinality = uint16(t.length);

    observationLibMock.binarySearch(
      newestObservationIndex,
      oldestObservationIndex,
      target,
      cardinality
    );
  }

  function testBinarySearch_OneItem_TargetExact() public {
    uint32[] memory t = new uint32[](1);
    t[0] = 10;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 0;
    uint24 oldestObservationIndex = 0;
    uint32 target = 10;
    uint16 cardinality = uint16(t.length);

    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = observationLibMock.binarySearch(
        newestObservationIndex,
        oldestObservationIndex,
        target,
        cardinality
      );

    assertEq(beforeOrAt.timestamp, 10);
    assertEq(afterOrAt.timestamp, 10);
  }

  // Outside of range
  function testFailBinarySearch_OneItem_TargetAfter() public {
    uint32[] memory t = new uint32[](1);
    t[0] = 10;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 0;
    uint24 oldestObservationIndex = 0;
    uint32 target = 15;
    uint16 cardinality = uint16(t.length);

    observationLibMock.binarySearch(
      newestObservationIndex,
      oldestObservationIndex,
      target,
      cardinality
    );
  }

  function testBinarySearch_TwoItems_TargetStart() public {
    uint32[] memory t = new uint32[](2);
    t[0] = 10;
    t[1] = 20;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 1;
    uint24 oldestObservationIndex = 0;
    uint32 target = 10;
    uint16 cardinality = uint16(t.length);

    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = observationLibMock.binarySearch(
        newestObservationIndex,
        oldestObservationIndex,
        target,
        cardinality
      );

    assertEq(beforeOrAt.timestamp, 10);
    assertEq(afterOrAt.timestamp, 20);
  }

  function testBinarySearch_TwoItems_TargetBetween() public {
    uint32[] memory t = new uint32[](2);
    t[0] = 10;
    t[1] = 20;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 1;
    uint24 oldestObservationIndex = 0;
    uint32 target = 15;
    uint16 cardinality = uint16(t.length);

    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = observationLibMock.binarySearch(
        newestObservationIndex,
        oldestObservationIndex,
        target,
        cardinality
      );

    assertEq(beforeOrAt.timestamp, 10);
    assertEq(afterOrAt.timestamp, 20);
  }

  function testBinarySearch_TwoItems_TargetEnd() public {
    uint32[] memory t = new uint32[](2);
    t[0] = 10;
    t[1] = 20;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 1;
    uint24 oldestObservationIndex = 0;
    uint32 target = 20;
    uint16 cardinality = uint16(t.length);

    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = observationLibMock.binarySearch(
        newestObservationIndex,
        oldestObservationIndex,
        target,
        cardinality
      );

    assertEq(beforeOrAt.timestamp, 10);
    assertEq(afterOrAt.timestamp, 20);
  }

  function testBinarySearch_ThreeItems_TargetStart() public {
    uint32[] memory t = new uint32[](3);
    t[0] = 10;
    t[1] = 20;
    t[2] = 30;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 2;
    uint24 oldestObservationIndex = 0;
    uint32 target = 10;
    uint16 cardinality = uint16(t.length);

    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = observationLibMock.binarySearch(
        newestObservationIndex,
        oldestObservationIndex,
        target,
        cardinality
      );

    assertEq(beforeOrAt.timestamp, 10);
    assertEq(afterOrAt.timestamp, 20);
  }

  function testBinarySearch_ThreeItems_TargetBetween() public {
    uint32[] memory t = new uint32[](3);
    t[0] = 10;
    t[1] = 20;
    t[2] = 30;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 2;
    uint24 oldestObservationIndex = 0;
    uint32 target = 20;
    uint16 cardinality = uint16(t.length);

    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = observationLibMock.binarySearch(
        newestObservationIndex,
        oldestObservationIndex,
        target,
        cardinality
      );

    assertEq(beforeOrAt.timestamp, 20);
    assertEq(afterOrAt.timestamp, 30);
  }

  function testBinarySearch_ThreeItems_TargetEnd() public {
    uint32[] memory t = new uint32[](3);
    t[0] = 10;
    t[1] = 20;
    t[2] = 30;
    observationLibMock.populateObservations(t);
    uint24 newestObservationIndex = 2;
    uint24 oldestObservationIndex = 0;
    uint32 target = 30;
    uint16 cardinality = uint16(t.length);

    (
      ObservationLib.Observation memory beforeOrAt,
      uint16 beforeOrAtIndex,
      ObservationLib.Observation memory afterOrAt,
      uint16 afterOrAtIndex
    ) = observationLibMock.binarySearch(
        newestObservationIndex,
        oldestObservationIndex,
        target,
        cardinality
      );

    assertEq(beforeOrAt.timestamp, 20);
    assertEq(afterOrAt.timestamp, 30);
  }
}
