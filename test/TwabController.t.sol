// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

import { TwabController } from "../src/TwabController.sol";
import { TwabLib, Account, AccountDetails } from "../src/libraries/TwabLib.sol";
import { ObservationLib } from "../src/libraries/ObservationLib.sol";
import { BaseSetup } from "./utils/BaseSetup.sol";
import { TwabLibMock } from "./mocks/TwabLibMock.sol";

contract TwabControllerTest is BaseSetup {
  TwabController public twabController;
  address public mockVault = address(0x1234);
  ERC20 public token;
  uint16 public constant MAX_CARDINALITY = 365;

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

  function testGetAccount() external {
    Account memory account = twabController.getAccount(mockVault, alice);
    assertEq(account.details.balance, 0);
    assertEq(account.details.delegateBalance, 0);
    assertEq(account.details.cardinality, 0);
    for (uint256 i = 0; i < MAX_CARDINALITY; i++) {
      assertEq(account.twabs[i].amount, 0);
      assertEq(account.twabs[i].timestamp, 0);
    }
  }

  function testBalanceOf() external {
    assertEq(twabController.balanceOf(mockVault, alice), 0);
    vm.prank(mockVault);
    twabController.twabMint(alice, 100);
    assertEq(twabController.balanceOf(mockVault, alice), 100);
  }

  function testGetDelegateBalanceAt() external {
    assertEq(twabController.getDelegateBalanceAt(mockVault, alice, 0), 0);
    vm.prank(mockVault);
    twabController.twabMint(alice, 100);
    vm.warp(1 days);
    assertEq(twabController.getDelegateBalanceAt(mockVault, alice, 1), 100);
    vm.prank(mockVault);
    twabController.twabMint(alice, 100);
    assertEq(twabController.getDelegateBalanceAt(mockVault, alice, 1 days), 200);
    vm.prank(mockVault);
    twabController.twabTransfer(alice, bob, 100);
    assertEq(twabController.getDelegateBalanceAt(mockVault, alice, 1 days), 100);
    assertEq(twabController.getDelegateBalanceAt(mockVault, bob, 1 days), 100);
  }

  function testTotalSupply() external {
    assertEq(twabController.totalSupply(mockVault), 0);
    vm.prank(mockVault);
    twabController.twabMint(alice, 100);
    assertEq(twabController.totalSupply(mockVault), 100);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 100);

    utils.timeTravel(1 days);
    vm.prank(mockVault);
    twabController.twabMint(bob, 100);
    assertEq(twabController.totalSupply(mockVault), 200);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 200);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint64(block.timestamp) - 1), 100);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint64(block.timestamp)), 200);

    utils.timeTravel(1 days);
    vm.prank(mockVault);
    twabController.twabBurn(bob, 50);
    assertEq(twabController.totalSupply(mockVault), 150);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 150);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint64(block.timestamp) - 1), 200);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint64(block.timestamp)), 150);

    utils.timeTravel(1 days);
    vm.prank(mockVault);
    twabController.twabMint(bob, 50);
    assertEq(twabController.totalSupply(mockVault), 200);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 200);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint64(block.timestamp)), 200);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint64(block.timestamp) - 1), 150);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint64(block.timestamp) + 1 days), 200);
  }

  function testMint() external {
    deal({ token: address(token), to: alice, give: 100 });

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
    vm.prank(mockVault);
    twabController.twabMint(alice, 100);

    Account memory account = twabController.getAccount(mockVault, alice);
    assertEq(account.details.balance, 100);
    assertEq(account.details.delegateBalance, 100);
  }

  function testBurn() external {
    deal({ token: address(token), to: alice, give: 100 });

    vm.prank(mockVault);
    twabController.twabMint(alice, 100);
    vm.prank(mockVault);
    twabController.twabBurn(alice, 100);
    Account memory account = twabController.getAccount(mockVault, alice);
    assertEq(account.details.balance, 0);
    assertEq(account.details.delegateBalance, 0);
  }

  function testDelegate() external {
    vm.prank(mockVault);
    twabController.twabMint(alice, 100);
    assertEq(twabController.delegateOf(mockVault, alice), address(0));
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 100);
    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carol), 0);
    assertEq(twabController.balanceOf(mockVault, carol), 0);

    vm.prank(alice);
    twabController.delegate(mockVault, alice);
    assertEq(twabController.delegateOf(mockVault, alice), alice);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 100);
    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carol), 0);
    assertEq(twabController.balanceOf(mockVault, carol), 0);

    vm.prank(alice);
    twabController.delegate(mockVault, bob);
    assertEq(twabController.delegateOf(mockVault, alice), bob);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 100);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carol), 0);
    assertEq(twabController.balanceOf(mockVault, carol), 0);

    vm.prank(alice);
    twabController.delegate(mockVault, carol);
    assertEq(twabController.delegateOf(mockVault, alice), carol);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carol), 100);
    assertEq(twabController.balanceOf(mockVault, carol), 0);
  }

  // ---

  function testTwabSuccessive() external {
    deal({ token: address(token), to: alice, give: 10000e18 });

    uint256 t0 = 1 days;
    uint256 t1 = t0 + 1 days;
    uint256 t2 = t1 + 1 days;

    vm.warp(t0);
    vm.prank(mockVault);
    twabController.twabMint(alice, 100e18);
    vm.warp(t1);
    vm.prank(mockVault);
    twabController.twabMint(alice, 100e18);
    vm.warp(t2);
    vm.prank(mockVault);
    twabController.twabBurn(alice, 100e18);

    Account memory account = twabController.getAccount(mockVault, alice);
    assertEq(account.details.balance, 100e18);
    assertEq(account.details.delegateBalance, 100e18);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestTwab(
      mockVault,
      alice
    );

    assertEq(twab.amount, 25920000e18);
    assertEq(twab.timestamp, t2);
    assertEq(index, 2);

    vm.stopPrank();
  }

  function testFailTwabOverwrite() external {
    deal({ token: address(token), to: alice, give: 10000e18 });

    uint256 t0 = 1 days;
    uint256 t1 = t0 + 1 days;
    uint256 t2 = t1 + 12 hours;

    vm.warp(t0);
    vm.prank(mockVault);
    twabController.twabMint(alice, 100e18);
    vm.warp(t1);
    vm.prank(mockVault);
    twabController.twabMint(alice, 100e18);
    vm.warp(t2);
    vm.prank(mockVault);
    twabController.twabBurn(alice, 100e18);

    Account memory account = twabController.getAccount(mockVault, alice);

    assertEq(account.details.balance, 100e18);
    assertEq(account.details.delegateBalance, 100e18);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestTwab(
      mockVault,
      alice
    );

    assertEq(twab.amount, 17280000e18);
    assertEq(twab.timestamp, t2);
    assertEq(index, 1);
  }
}
