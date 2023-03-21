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

  event IncreasedBalance(
    address indexed vault,
    address indexed user,
    uint112 amount,
    bool isNew,
    ObservationLib.Observation twab
  );

  event DecreasedBalance(
    address indexed vault,
    address indexed user,
    uint112 amount,
    bool isNew,
    ObservationLib.Observation twab
  );

  event Delegated(address indexed vault, address indexed delegator, address indexed delegate);

  event IncreasedTotalSupply(
    address indexed vault,
    uint112 amount,
    bool isNew,
    ObservationLib.Observation twab
  );

  event DecreasedTotalSupply(
    address indexed vault,
    uint112 amount,
    bool isNew,
    ObservationLib.Observation twab
  );

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

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);

    vm.stopPrank();
  }

  function testGetBalanceAt() external {
    assertEq(twabController.getBalanceAt(mockVault, alice, 0), 0);

    vm.startPrank(mockVault);

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

    vm.warp(1 days);
    assertEq(twabController.getBalanceAt(mockVault, alice, 1), _amount);

    changePrank(mockVault);
    twabController.twabMint(alice, _amount);

    assertEq(twabController.getBalanceAt(mockVault, alice, 1 days), _amount * 2);

    twabController.twabTransfer(alice, bob, _amount);

    assertEq(twabController.getBalanceAt(mockVault, alice, 1 days), _amount);
    assertEq(twabController.getBalanceAt(mockVault, bob, 1 days), _amount);

    vm.stopPrank();
  }

  function testGetAverageBetween() external {
    uint32 initialTimestamp = 1000;
    uint32 currentTimestamp = 2000;

    vm.warp(initialTimestamp);

    vm.startPrank(mockVault);

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

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

    assertEq(balance, _amount / 2);
    assertEq(totalSupply, _amount / 2);

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

    assertEq(balance, _amount);
    assertEq(totalSupply, _amount);

    vm.stopPrank();
  }

  function testTotalSupply() external {
    assertEq(twabController.totalSupply(mockVault), 0);

    uint112 _mintAmount = 1000e18;

    vm.startPrank(mockVault);
    twabController.twabMint(alice, _mintAmount);

    assertEq(twabController.totalSupply(mockVault), _mintAmount);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _mintAmount);

    utils.timeTravel(1 days);

    changePrank(mockVault);
    twabController.twabMint(bob, _mintAmount);

    uint112 _totalSupplyAmountBeforeBurn = _mintAmount * 2;

    assertEq(twabController.totalSupply(mockVault), _totalSupplyAmountBeforeBurn);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _totalSupplyAmountBeforeBurn);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) - 1), _mintAmount);
    assertEq(
      twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp)),
      _totalSupplyAmountBeforeBurn
    );

    utils.timeTravel(1 days);

    uint112 _burnAmount = 500e18;
    twabController.twabBurn(bob, _burnAmount);

    uint112 _totalSupplyAmountAfterBurn = _totalSupplyAmountBeforeBurn - _burnAmount;

    assertEq(twabController.totalSupply(mockVault), _totalSupplyAmountAfterBurn);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _totalSupplyAmountAfterBurn);
    assertEq(
      twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) - 1),
      _totalSupplyAmountBeforeBurn
    );
    assertEq(
      twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp)),
      _totalSupplyAmountAfterBurn
    );

    utils.timeTravel(1 days);

    twabController.twabMint(bob, _mintAmount);

    uint112 _totalSupplyAmountAfterMint = _totalSupplyAmountAfterBurn + _mintAmount;

    assertEq(twabController.totalSupply(mockVault), _totalSupplyAmountAfterMint);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _totalSupplyAmountAfterMint);
    assertEq(
      twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp)),
      _totalSupplyAmountAfterMint
    );
    assertEq(
      twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) - 1),
      _totalSupplyAmountAfterBurn
    );
    assertEq(
      twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) + 1 days),
      _totalSupplyAmountAfterMint
    );

    vm.stopPrank();
  }

  function testSponsorshipDelegation() external {
    assertEq(twabController.totalSupply(mockVault), 0);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);

    uint112 _amount = 1000e18;

    vm.startPrank(mockVault);
    twabController.twabMint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);

    assertEq(twabController.totalSupply(mockVault), _amount);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _amount);

    twabController.sponsor(alice);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    address _sponsorshipAddress = twabController.SPONSORSHIP_ADDRESS();
    assertEq(twabController.balanceOf(mockVault, _sponsorshipAddress), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, _sponsorshipAddress), 0);

    assertEq(twabController.totalSupply(mockVault), _amount);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);

    changePrank(alice);
    twabController.delegate(mockVault, bob);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);

    assertEq(twabController.totalSupply(mockVault), _amount);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _amount);

    vm.stopPrank();
  }

  function testMint() external {
    uint112 _amount = 1000e18;
    vm.expectEmit(true, true, false, true);
    emit IncreasedBalance(
      mockVault,
      alice,
      _amount,
      true,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );

    vm.expectEmit(true, false, false, true);
    emit IncreasedTotalSupply(
      mockVault,
      _amount,
      true,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );

    vm.startPrank(mockVault);

    twabController.twabMint(alice, _amount);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, _amount);
    assertEq(accountDetails.delegateBalance, _amount);

    vm.stopPrank();
  }

  function testBurn() external {
    vm.startPrank(mockVault);

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

    vm.expectEmit(true, true, false, true);
    emit DecreasedBalance(
      mockVault,
      alice,
      _amount,
      false,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );

    vm.expectEmit(true, false, false, true);
    emit DecreasedTotalSupply(
      mockVault,
      _amount,
      false,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );
    twabController.twabBurn(alice, _amount);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);

    vm.stopPrank();
  }

  function testIsNewEvent() external {
    vm.startPrank(mockVault);

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

    vm.expectEmit(true, true, false, true);
    emit DecreasedBalance(
      mockVault,
      alice,
      _amount,
      false,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );

    vm.expectEmit(true, false, false, true);
    emit DecreasedTotalSupply(
      mockVault,
      _amount,
      false,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );
    twabController.twabBurn(alice, _amount);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);

    vm.stopPrank();
  }

  function testTransfer() external {
    vm.startPrank(mockVault);

    uint112 _amount = 1000e18;
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

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

    assertEq(twabController.delegateOf(mockVault, alice), alice);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);

    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);

    assertEq(twabController.delegateBalanceOf(mockVault, carole), 0);
    assertEq(twabController.balanceOf(mockVault, carole), 0);

    changePrank(alice);
    twabController.delegate(mockVault, bob);

    assertEq(twabController.delegateOf(mockVault, alice), bob);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);

    assertEq(twabController.balanceOf(mockVault, carole), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carole), 0);

    twabController.delegate(mockVault, carole);

    assertEq(twabController.delegateOf(mockVault, alice), carole);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);

    assertEq(twabController.balanceOf(mockVault, carole), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carole), _amount);

    changePrank(mockVault);
    twabController.twabMint(alice, _amount);

    uint112 _totalAmount = _amount * 2;

    assertEq(twabController.balanceOf(mockVault, alice), _totalAmount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, carole), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, carole), _totalAmount);

    vm.stopPrank();
  }

  function testDelegateToSponsorship() external {
    address _sponsorshipAddress = twabController.SPONSORSHIP_ADDRESS();

    assertEq(twabController.delegateOf(mockVault, alice), alice);

    vm.startPrank(mockVault);
    twabController.sponsor(alice);

    assertEq(twabController.delegateOf(mockVault, alice), _sponsorshipAddress);

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, _sponsorshipAddress), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, _sponsorshipAddress), 0);

    vm.stopPrank();
  }

  function testDelegateAlreadySet() external {
    vm.startPrank(alice);

    vm.expectRevert(bytes("TC/delegate-already-set"));
    twabController.delegate(mockVault, alice);

    vm.stopPrank();
  }

  /* ============ TWAB ============ */

  // TODO: Currently this test passes. It should fail/be handled differently.
  // 2 updates to an uninitialized twab within 24h results in 2 separate TWAB observations.
  // We want the TWAB hsitory to be a single observation per 24h period.
  function testFailTwabInitialTwoInOneDay() external {
    deal({ token: address(token), to: alice, give: 10000e18 });

    uint256 t0 = 1 days;
    uint256 t1 = t0 + 12 hours;

    vm.warp(t0);

    vm.startPrank(mockVault);

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

    vm.warp(t1);
    twabController.twabMint(alice, _amount);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, _amount * 2);
    assertEq(accountDetails.delegateBalance, _amount * 2);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestTwab(
      mockVault,
      alice
    );

    assertEq(twab.amount, 43200000e18);
    assertEq(twab.timestamp, t1);
    assertEq(index, 1);
  }

  function testTwabSuccessive() external {
    deal({ token: address(token), to: alice, give: 10000e18 });

    uint256 t0 = 1 days;
    uint256 t1 = t0 + 1 days;
    uint256 t2 = t1 + 1 days;
    uint256 t3 = t2 + 12 hours;

    vm.warp(t0);

    vm.startPrank(mockVault);

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

    vm.warp(t1);
    twabController.twabMint(alice, _amount);

    vm.warp(t2);
    twabController.twabBurn(alice, _amount);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, _amount);
    assertEq(accountDetails.delegateBalance, _amount);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestTwab(
      mockVault,
      alice
    );

    assertEq(twab.amount, 259200000e18);
    assertEq(twab.timestamp, t2);
    assertEq(index, 2);

    vm.warp(t3);
    twabController.twabMint(alice, _amount);

    account = twabController.getAccount(mockVault, alice);

    uint112 _totalAmount = _amount * 2;

    assertEq(account.details.balance, _totalAmount);
    assertEq(account.details.delegateBalance, _totalAmount);

    (index, twab) = twabController.getNewestTwab(mockVault, alice);

    assertEq(twab.amount, 302400000e18);
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

    uint112 _amount = 1000e18;
    twabController.twabMint(alice, _amount);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    assertEq(accountDetails.balance, _amount);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextTwabIndex, 1);
    assertEq(accountDetails.cardinality, 1);

    vm.warp(t1);
    twabController.twabMint(alice, _amount);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    uint112 _totalAmount = _amount * 2;

    assertEq(accountDetails.balance, _totalAmount);
    assertEq(accountDetails.delegateBalance, _totalAmount);
    assertEq(accountDetails.nextTwabIndex, 2);
    assertEq(accountDetails.cardinality, 2);

    vm.warp(t2);
    twabController.twabBurn(alice, _amount);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    assertEq(accountDetails.balance, _amount);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextTwabIndex, 3);
    assertEq(accountDetails.cardinality, 3);

    vm.warp(t3);
    twabController.twabBurn(alice, _amount);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.nextTwabIndex, 4);
    assertEq(accountDetails.cardinality, 4);

    vm.warp(t4);
    twabController.twabMint(alice, _amount);

    account = twabController.getAccount(mockVault, alice);
    accountDetails = account.details;

    assertEq(accountDetails.balance, _amount);
    assertEq(accountDetails.delegateBalance, _amount);
    assertEq(accountDetails.nextTwabIndex, 4);
    assertEq(accountDetails.cardinality, 4);

    assertEq(account.twabs[0].amount, 0);
    assertEq(account.twabs[1].amount, 86400000e18);
    assertEq(account.twabs[2].amount, 259200000e18);
    assertEq(account.twabs[3].amount, 302400000e18);
    assertEq(account.twabs[4].amount, 0);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestTwab(
      mockVault,
      alice
    );

    assertEq(twab.amount, 302400000e18);
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
    uint112 _amount = 1000e18;

    // Wrap around the TWAB storage
    for (uint32 i = 0; i <= 365; i++) {
      vm.warp((i + 1) * 1 days);
      twabController.twabMint(alice, _amount);
    }

    (newestIndex, newestTwab) = twabController.getNewestTwab(mockVault, alice);

    assertEq(newestTwab.amount, 5771088000000e18);
    assertEq(newestTwab.timestamp, 366 days);
    assertEq(newestIndex, 0);

    (oldestIndex, oldestTwab) = twabController.getOldestTwab(mockVault, alice);

    assertEq(oldestTwab.amount, 86400000e18);
    assertEq(oldestTwab.timestamp, 2 days);
    assertEq(oldestIndex, 1);

    vm.stopPrank();
  }
}
