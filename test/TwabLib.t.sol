// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { BaseSetup } from "./utils/BaseSetup.sol";
import { TwabLibMock } from "./mocks/TwabLibMock.sol";
import { TwabLib } from "../src/libraries/TwabLib.sol";
import { ObservationLib } from "../src/libraries/ObservationLib.sol";

contract FooTest is BaseSetup {
  TwabLibMock public twabLibMock;

  function setUp() public override {
    super.setUp();

    twabLibMock = new TwabLibMock();
  }

  function testIncreaseBalance() public {
    // Increase balance
    (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    ) = twabLibMock.increaseBalance(uint112(100), uint32(block.timestamp));

    // Check balance
    assertEq(accountDetails.balance, 100);
  }
}
