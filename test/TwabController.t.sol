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
    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.cardinality, 0);

    for (uint256 i = 0; i < MAX_CARDINALITY; i++) {
      assertEq(account.twabs[i].amount, 0);
      assertEq(account.twabs[i].timestamp, 0);
    }
  }

  function testBalanceOf() external {
    assertEq(twabController.balanceOf(mockVault, alice), 0);

    vm.startPrank(mockVault);
    twabController.twabMint(alice, 100);

    assertEq(twabController.balanceOf(mockVault, alice), 100);

    vm.stopPrank();
  }

  function testGetBalanceAt() external {
    assertEq(twabController.getBalanceAt(mockVault, alice, 0), 0);

    vm.startPrank(mockVault);
    twabController.twabMint(alice, 100);

    vm.warp(1 days);
    assertEq(twabController.getBalanceAt(mockVault, alice, 1), 100);

    changePrank(mockVault);
    twabController.twabMint(alice, 100);

    assertEq(twabController.getBalanceAt(mockVault, alice, 1 days), 200);

    twabController.twabTransfer(alice, bob, 100);

    assertEq(twabController.getBalanceAt(mockVault, alice, 1 days), 100);
    assertEq(twabController.getBalanceAt(mockVault, bob, 1 days), 100);

    vm.stopPrank();
  }

  function testGetAverageBetween() external {
    uint32 initialTimestamp = 1000;
    uint32 currentTimestamp = 2000;

    vm.warp(initialTimestamp);

    vm.startPrank(mockVault);
    twabController.twabMint(alice, 1000);

    vm.warp(currentTimestamp);

    uint256 balance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      initialTimestamp - 100,
      initialTimestamp - 50
    );

    uint256 totalSupply = twabController.getAverageTotalSupplyBetween(
      mockVault,
      initialTimestamp - 100,
      initialTimestamp - 50
    );

    assertEq(balance, 0);
    assertEq(totalSupply, 0);

    balance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      initialTimestamp - 100,
      initialTimestamp
    );
    totalSupply = twabController.getAverageTotalSupplyBetween(
      mockVault,
      initialTimestamp - 100,
      initialTimestamp
    );

    assertEq(balance, 0);
    assertEq(totalSupply, 0);

    vm.warp(initialTimestamp);
    balance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      initialTimestamp - 50,
      initialTimestamp + 50
    );
    totalSupply = twabController.getAverageTotalSupplyBetween(
      mockVault,
      initialTimestamp - 50,
      initialTimestamp + 50
    );

    assertEq(balance, 0);
    assertEq(totalSupply, 0);

    vm.warp(currentTimestamp);
    balance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      initialTimestamp - 50,
      initialTimestamp + 50
    );

    totalSupply = twabController.getAverageTotalSupplyBetween(
      mockVault,
      initialTimestamp - 50,
      initialTimestamp + 50
    );

    assertEq(balance, 500);
    assertEq(totalSupply, 500);

    balance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      initialTimestamp + 50,
      initialTimestamp + 51
    );

    totalSupply = twabController.getAverageTotalSupplyBetween(
      mockVault,
      initialTimestamp + 50,
      initialTimestamp + 51
    );

    assertEq(balance, 1000);
    assertEq(totalSupply, 1000);

    vm.stopPrank();
  }

  function testTotalSupply() external {
    assertEq(twabController.totalSupply(mockVault), 0);

    vm.startPrank(mockVault);
    twabController.twabMint(alice, 100);

    assertEq(twabController.totalSupply(mockVault), 100);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 100);

    utils.timeTravel(1 days);

    changePrank(mockVault);
    twabController.twabMint(bob, 100);

    assertEq(twabController.totalSupply(mockVault), 200);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 200);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) - 1), 100);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp)), 200);

    utils.timeTravel(1 days);

    twabController.twabBurn(bob, 50);

    assertEq(twabController.totalSupply(mockVault), 150);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 150);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) - 1), 200);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp)), 150);

    utils.timeTravel(1 days);

    twabController.twabMint(bob, 50);

    assertEq(twabController.totalSupply(mockVault), 200);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 200);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp)), 200);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) - 1), 150);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) + 1 days), 200);

    vm.stopPrank();
  }

  function testSponsorshipDelegation() external {
    assertEq(twabController.totalSupply(mockVault), 0);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);

    vm.startPrank(mockVault);
    twabController.twabMint(alice, 100);

    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 100);
    assertEq(twabController.totalSupply(mockVault), 100);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 100);

    changePrank(alice);
    twabController.delegate(mockVault, twabController.SPONSORSHIP_ADDRESS());

    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.totalSupply(mockVault), 100);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);

    twabController.delegate(mockVault, bob);

    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 100);
    assertEq(twabController.totalSupply(mockVault), 100);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 100);

    vm.stopPrank();
  }

  function testMint() external {
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

    vm.startPrank(mockVault);
    twabController.twabMint(alice, 100);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 100);
    assertEq(accountDetails.delegateBalance, 100);

    vm.stopPrank();
  }

  function testBurn() external {
    vm.startPrank(mockVault);

    twabController.twabMint(alice, 100);
    twabController.twabBurn(alice, 100);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);

    vm.stopPrank();
  }

  function testTransfer() external {
    uint112 _amount = 100;

    vm.startPrank(mockVault);
    twabController.twabMint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);

    changePrank(alice);
    twabController.delegate(mockVault, bob);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);

    changePrank(mockVault);
    twabController.twabTransfer(alice, carole, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, carole), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, carole), _amount);

    vm.stopPrank();
  }

  /* ============ delegate ============ */
  function testDelegate() external {
    vm.startPrank(mockVault);
    twabController.twabMint(alice, 100);

    assertEq(twabController.delegateOf(mockVault, alice), alice);
    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 100);

    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);

    assertEq(twabController.delegateBalanceOf(mockVault, carole), 0);
    assertEq(twabController.balanceOf(mockVault, carole), 0);

    changePrank(alice);
    twabController.delegate(mockVault, bob);

    assertEq(twabController.delegateOf(mockVault, alice), bob);
    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 100);

    assertEq(twabController.balanceOf(mockVault, carole), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carole), 0);

    twabController.delegate(mockVault, carole);

    assertEq(twabController.delegateOf(mockVault, alice), carole);
    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);

    assertEq(twabController.balanceOf(mockVault, carole), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carole), 100);

    changePrank(mockVault);
    twabController.twabMint(alice, 100);

    assertEq(twabController.balanceOf(mockVault, alice), 200);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, carole), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carole), 200);

    vm.stopPrank();
  }

  function testDelegateToSponsorship() external {
    address _sponsorship = twabController.SPONSORSHIP_ADDRESS();

    assertEq(twabController.delegateOf(mockVault, alice), alice);

    vm.startPrank(alice);
    twabController.delegate(mockVault, _sponsorship);

    assertEq(twabController.delegateOf(mockVault, alice), _sponsorship);

    changePrank(mockVault);
    twabController.twabMint(alice, 100);

    assertEq(twabController.balanceOf(mockVault, alice), 100);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, _sponsorship), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, _sponsorship), 0);

    vm.stopPrank();
  }

  function testDelegateAlreadySet() external {
    vm.startPrank(alice);

    vm.expectRevert(bytes("TC/delegate-already-set"));
    twabController.delegate(mockVault, alice);

    vm.stopPrank();
  }

  /* ============ TWAB ============ */
  function testTwabSuccessive() external {
    deal({ token: address(token), to: alice, give: 10000 });

    uint256 t0 = 1 days;
    uint256 t1 = t0 + 1 days;
    uint256 t2 = t1 + 1 days;
    uint256 t3 = t2 + 12 hours;

    vm.warp(t0);

    vm.startPrank(mockVault);
    twabController.twabMint(alice, 100);

    vm.warp(t1);
    twabController.twabMint(alice, 100);

    vm.warp(t2);
    twabController.twabBurn(alice, 100);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 100);
    assertEq(accountDetails.delegateBalance, 100);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestTwab(
      mockVault,
      alice
    );

    assertEq(twab.amount, 25920000);
    assertEq(twab.timestamp, t2);
    assertEq(index, 2);

    vm.warp(t3);
    twabController.twabMint(alice, 100);

    account = twabController.getAccount(mockVault, alice);

    assertEq(account.details.balance, 200);
    assertEq(account.details.delegateBalance, 200);

    (index, twab) = twabController.getNewestTwab(mockVault, alice);

    assertEq(twab.amount, 30240000);
    assertEq(twab.timestamp, t3);
    assertEq(index, 3);

    vm.stopPrank();
  }

  function testTwabOverwrite() external {
    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    // twab 0 0 86400s (1 day)
    // twab 1 8640000000000000000000000 172800s (2 days)
    // twab 2 25920000000000000000000000 259200s (3 days)
    // twab 3 30240000000000000000000000 324000s (3 days + 12 hours)
    // twab 4 0 0

    uint256 t0 = 1 days;
    uint256 t1 = 2 days;
    uint256 t2 = 3 days;
    uint256 t3 = 3 days + 12 hours;
    uint256 t4 = 3 days + 18 hours;

    vm.warp(t0);

    vm.startPrank(mockVault);
    twabController.twabMint(alice, 100);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    assertEq(accountDetails.balance, 100);
    assertEq(accountDetails.delegateBalance, 100);
    assertEq(accountDetails.nextTwabIndex, 1);
    assertEq(accountDetails.cardinality, 1);

    vm.warp(t1);
    twabController.twabMint(alice, 100);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    assertEq(accountDetails.balance, 200);
    assertEq(accountDetails.delegateBalance, 200);
    assertEq(accountDetails.nextTwabIndex, 2);
    assertEq(accountDetails.cardinality, 2);

    vm.warp(t2);
    twabController.twabBurn(alice, 100);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    assertEq(accountDetails.balance, 100);
    assertEq(accountDetails.delegateBalance, 100);
    assertEq(accountDetails.nextTwabIndex, 3);
    assertEq(accountDetails.cardinality, 3);

    vm.warp(t3);
    twabController.twabBurn(alice, 100);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.nextTwabIndex, 4);
    assertEq(accountDetails.cardinality, 4);

    vm.warp(t4);
    twabController.twabMint(alice, 100);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    assertEq(accountDetails.balance, 100);
    assertEq(accountDetails.delegateBalance, 100);
    assertEq(accountDetails.nextTwabIndex, 4);
    assertEq(accountDetails.cardinality, 4);

    assertEq(account.twabs[0].amount, 0);
    assertEq(account.twabs[1].amount, 8640000);
    assertEq(account.twabs[2].amount, 25920000);
    assertEq(account.twabs[3].amount, 30240000);
    assertEq(account.twabs[4].amount, 0);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestTwab(
      mockVault,
      alice
    );

    assertEq(twab.amount, 30240000);
    assertEq(twab.timestamp, t4);
    assertEq(index, 3);

    vm.stopPrank();
  }

  function testGetOldestAndNewestTwab() external {
    (uint16 newestIndex, ObservationLib.Observation memory newestTwab) = twabController
      .getNewestTwab(mockVault, alice);

    assertEq(newestTwab.amount, 0);
    assertEq(newestTwab.timestamp, 0);
    assertEq(newestIndex, 364);

    (uint16 oldestIndex, ObservationLib.Observation memory oldestTwab) = twabController
      .getOldestTwab(mockVault, alice);

    assertEq(oldestTwab.amount, 0);
    assertEq(oldestTwab.timestamp, 0);
    assertEq(oldestIndex, 0);

    vm.startPrank(mockVault);

    // Wrap around the TWAB storage
    for (uint32 i = 0; i <= 365; i++) {
      vm.warp((i + 1) * 1 days);
      twabController.twabMint(alice, 100);
    }

    (newestIndex, newestTwab) = twabController.getNewestTwab(mockVault, alice);

    assertEq(newestTwab.amount, 577108800000);
    assertEq(newestTwab.timestamp, 366 days);
    assertEq(newestIndex, 0);

    (oldestIndex, oldestTwab) = twabController.getOldestTwab(mockVault, alice);

    assertEq(oldestTwab.amount, 8640000);
    assertEq(oldestTwab.timestamp, 2 days);
    assertEq(oldestIndex, 1);

    vm.stopPrank();
  }
}
