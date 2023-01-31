// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

import { TwabController } from "../src/TwabController.sol";
import { TwabLib } from "../src/libraries/TwabLib.sol";
import { ObservationLib } from "../src/libraries/ObservationLib.sol";
import { BaseSetup } from "./utils/BaseSetup.sol";

contract TwabControllerTest is BaseSetup {
  TwabController public twabController;
  address public mockVault = address(0x1234);
  ERC20 public token;

  event NewUserTwab(
    address indexed vault,
    address indexed delegate,
    ObservationLib.Observation newTwab
  );

  event Delegated(address indexed vault, address indexed delegator, address indexed delegate);

  event NewTotalSupplyTwab(address indexed vault, ObservationLib.Observation newTotalSupplyTwab);

  function setUp() public override {
    super.setUp();

    twabController = new TwabController();
    token = new ERC20("Test", "TST");
  }

  function testMint() external {
    deal({ token: address(token), to: alice, give: 100 });

    vm.startPrank(alice);

    vm.expectEmit(true, true, true, true);
    emit Delegated(mockVault, alice, alice);
    vm.expectEmit(true, true, false, true);
    emit NewUserTwab(
      mockVault,
      alice,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );
    vm.expectEmit(true, false, false, true);
    emit NewTotalSupplyTwab(
      mockVault,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );

    twabController.delegate(mockVault, alice, alice);
    twabController.mint(mockVault, alice, 100);

    TwabLib.AccountDetails memory account = twabController.getAccountDetails(mockVault, alice);
    assertEq(account.balance, 100);

    // utils.mineBlocks(10);
    account = twabController.getAccountDetails(mockVault, alice);
    assertEq(account.balance, 100);

    vm.stopPrank();
  }

  function testBurn() external {
    deal({ token: address(token), to: alice, give: 100 });

    vm.startPrank(alice);
    twabController.delegate(mockVault, alice, alice);
    twabController.mint(mockVault, alice, 100);
    twabController.burn(mockVault, alice, 100);
    TwabLib.AccountDetails memory account = twabController.getAccountDetails(mockVault, alice);
    assertEq(account.balance, 0);

    vm.stopPrank();
  }
}
