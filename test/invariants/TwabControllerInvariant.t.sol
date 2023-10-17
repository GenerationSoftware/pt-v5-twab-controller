// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { TwabLib } from "../../src/libraries/TwabLib.sol";
import { TwabController } from "../../src/TwabController.sol";
import { ObservationLib, MAX_CARDINALITY } from "../../src/libraries/ObservationLib.sol";

import { BaseTest } from "../utils/BaseTest.sol";
import { TwabControllerHandler } from "./handlers/TwabControllerHandler.sol";

contract TwabControllerInvariant is BaseTest {
  TwabController public twabController;
  TwabControllerHandler public handler;
  uint32 public constant PERIOD_OFFSET = 10 days;
  uint32 public constant PERIOD_LENGTH = 1 days;

  function setUp() public override {
    super.setUp();

    // Ensure the time in our test environment is >= the defined period offset.
    vm.warp(PERIOD_OFFSET);

    twabController = new TwabController(PERIOD_LENGTH, PERIOD_OFFSET);
    handler = new TwabControllerHandler(twabController);

    // Restrict handler methods to be called
    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = TwabControllerHandler.mint.selector;
    selectors[1] = TwabControllerHandler.burn.selector;
    selectors[2] = TwabControllerHandler.transfer.selector;
    selectors[3] = TwabControllerHandler.delegate.selector;
    targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    targetContract(address(handler));
  }

  function invariant_summary() public view {
    console2.log("-- Function Calls --");
    console2.log("mint", handler.h_fnCallCount("mint"));
    console2.log("burn", handler.h_fnCallCount("burn"));
    console2.log("transfer", handler.h_fnCallCount("transfer"));
    console2.log("delegate", handler.h_fnCallCount("delegate"));
    console2.log("--");
    console2.log("time", block.timestamp);
    console2.log("handler.h_initialBlockTimestamp", handler.h_initialBlockTimestamp());
    console2.log("handler.h_blockTimestamp", handler.h_blockTimestamp());
    console2.log("handler.h_blockTimestampChanges", handler.h_blockTimestampChanges());
    console2.log("handler.h_totalMinted()", handler.h_totalMinted());
    console2.log("handler.h_totalBurned()", handler.h_totalBurned());
    console2.log("diff", handler.h_totalMinted() - handler.h_totalBurned());
  }

  // The sum of user balances always equals the total supply.
  // The sum of user balances always equals total minted - total burned.
  function invariant_totalSupplyMatchesUserBalances() public {
    uint256 totalUsersSupply = handler.sumUserBalancesAcrossVaults();
    uint256 totalTotalSupply = handler.sumTotalSupplyAcrossVaults();

    assertEq(totalUsersSupply, handler.h_totalMinted() - handler.h_totalBurned());

    assertEq(totalUsersSupply, totalTotalSupply);
  }

  // Each timestamp of an observation should be safe for both TotalSupply and Actors.
  // The newest timestamp in the observation ring buffer should always be a safe timestamp.
  // Timestamps that line up with periods ending should always be safe timestamps.
  // This test is slow because it iterates over all vaults, all users and all observations.
  function invariant_safeTimestamps_SLOW() public {
    (bool isVaultsSafe, bool isActorsSafe) = handler.reduceTimestampChecks();
    assertTrue(isVaultsSafe);
    assertTrue(isActorsSafe);
  }

  // The sum of User TWABs across the whole time range is less than or equal to the total supply TWAB.
  function invariant_totalSupplyTwabGreaterThanUserTwabs() public {
    (uint256 totalSupplyTwabSum, uint256 userTwabSum) = handler.reduceFullRangeTwabs();

    // NOTE: This is not an exact check because the total supply TWAB may be slightly higher than the sum of user TWABs due to rounding.
    assertLe(userTwabSum, totalSupplyTwabSum);
    assertApproxEqAbs(userTwabSum, totalSupplyTwabSum, 100);
  }
}
