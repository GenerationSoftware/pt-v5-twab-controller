// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

import { TwabController, SameDelegateAlreadySet } from "src/TwabController.sol";
import { TwabLib } from "src/libraries/TwabLib.sol";
import { ObservationLib } from "src/libraries/ObservationLib.sol";
import { BaseTest } from "test/utils/BaseTest.sol";

contract TwabControllerTest is BaseTest {
  TwabController public twabController;
  address public mockVault = address(0x1234);
  ERC20 public token;
  uint16 public constant MAX_CARDINALITY = 365;

  event IncreasedBalance(
    address indexed vault,
    address indexed user,
    uint96 amount,
    uint96 delegateAmount
  );

  event DecreasedBalance(
    address indexed vault,
    address indexed user,
    uint96 amount,
    uint96 delegateAmount
  );

  event ObservationRecorded(
    address indexed vault,
    address indexed user,
    uint112 balance,
    uint112 delegateBalance,
    bool isNew,
    ObservationLib.Observation observation
  );

  event Delegated(address indexed vault, address indexed delegator, address indexed delegate);

  event IncreasedTotalSupply(address indexed vault, uint96 amount, uint96 delegateAmount);

  event DecreasedTotalSupply(address indexed vault, uint96 amount, uint96 delegateAmount);

  event TotalSupplyObservationRecorded(
    address indexed vault,
    uint112 balance,
    uint112 delegateBalance,
    bool isNew,
    ObservationLib.Observation observation
  );

  function setUp() public override {
    super.setUp();

    twabController = new TwabController();
    token = new ERC20("Test", "TST");

    // Ensure time is >= the hardcoded offset.
    vm.warp(TwabLib.PERIOD_OFFSET);
  }

  function testGetAccount() external {
    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);
    assertEq(accountDetails.cardinality, 0);

    for (uint256 i = 0; i < MAX_CARDINALITY; i++) {
      assertEq(account.observations[i].cumulativeBalance, 0);
      assertEq(account.observations[i].timestamp, 0);
    }
  }

  function testBalanceOf() external {
    assertEq(twabController.balanceOf(mockVault, alice), 0);

    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);

    vm.stopPrank();
  }

  function testGetBalanceAt() external {
    vm.startPrank(mockVault);

    // Before history started
    assertEq(twabController.getBalanceAt(mockVault, alice, 0), 0);
    // At history start
    assertEq(twabController.getBalanceAt(mockVault, alice, TwabLib.PERIOD_OFFSET), 0);

    // Mint at history start
    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    // Half way through a period.
    vm.warp(TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2));
    assertEq(twabController.getBalanceAt(mockVault, alice, TwabLib.PERIOD_OFFSET), _amount);
    assertEq(
      twabController.getBalanceAt(mockVault, alice, TwabLib.PERIOD_OFFSET + 10 seconds),
      _amount
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        alice,
        TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2)
      ),
      _amount
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        alice,
        TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2) + 10 seconds
      ),
      _amount
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        alice,
        TwabLib.PERIOD_OFFSET + ((TwabLib.PERIOD_LENGTH / 4) * 3)
      ),
      _amount
    );

    // Mint at half way through a period.
    twabController.mint(alice, _amount);

    // Recheck the last set of timestamps.
    // Balances will have changed due to overwrites.
    assertEq(twabController.getBalanceAt(mockVault, alice, TwabLib.PERIOD_OFFSET), _amount);
    assertEq(
      twabController.getBalanceAt(mockVault, alice, TwabLib.PERIOD_OFFSET + 10 seconds),
      _amount
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        alice,
        TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2)
      ),
      _amount * 2
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        alice,
        TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2) + 10 seconds
      ),
      _amount * 2
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        alice,
        TwabLib.PERIOD_OFFSET + ((TwabLib.PERIOD_LENGTH / 4) * 3)
      ),
      _amount * 2
    );

    // 3 quarters of the way through the period, transfer half the balance.
    vm.warp(TwabLib.PERIOD_OFFSET + ((TwabLib.PERIOD_LENGTH / 4) * 3));
    twabController.transfer(alice, bob, _amount);

    // Recheck the last set of timestamps.
    // Balances will have changed due to overwrites.
    assertEq(twabController.getBalanceAt(mockVault, alice, TwabLib.PERIOD_OFFSET), _amount);
    assertEq(
      twabController.getBalanceAt(mockVault, alice, TwabLib.PERIOD_OFFSET + 10 seconds),
      _amount
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        alice,
        TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2)
      ),
      _amount
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        alice,
        TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2) + 10 seconds
      ),
      _amount
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        alice,
        TwabLib.PERIOD_OFFSET + ((TwabLib.PERIOD_LENGTH / 4) * 3)
      ),
      _amount
    );

    // Check Bob's balance
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        bob,
        TwabLib.PERIOD_OFFSET + ((TwabLib.PERIOD_LENGTH / 4) * 3) - 1 seconds
      ),
      0
    );
    assertEq(
      twabController.getBalanceAt(
        mockVault,
        bob,
        TwabLib.PERIOD_OFFSET + ((TwabLib.PERIOD_LENGTH / 4) * 3)
      ),
      _amount
    );

    vm.stopPrank();
  }

  function testGetTwabBetween() external {
    uint32 initialTimestamp = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH;
    uint32 currentTimestamp = initialTimestamp + TwabLib.PERIOD_LENGTH;

    vm.warp(initialTimestamp);

    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    vm.warp(currentTimestamp);

    // Avg balance from before the first observation
    // [before,before] observation
    uint256 balance = twabController.getTwabBetween(
      mockVault,
      alice,
      initialTimestamp - 100,
      initialTimestamp - 50
    );
    uint256 totalSupply = twabController.getTotalSupplyTwabBetween(
      mockVault,
      initialTimestamp - 100,
      initialTimestamp - 50
    );
    assertEq(balance, 0);
    assertEq(totalSupply, 0);

    // [before,at] observation
    balance = twabController.getTwabBetween(
      mockVault,
      alice,
      initialTimestamp - 100,
      initialTimestamp
    );
    totalSupply = twabController.getTotalSupplyTwabBetween(
      mockVault,
      initialTimestamp - 100,
      initialTimestamp
    );
    assertEq(balance, 0);
    assertEq(totalSupply, 0);

    // [before,after] observation
    balance = twabController.getTwabBetween(
      mockVault,
      alice,
      initialTimestamp - 50,
      initialTimestamp + 50
    );
    totalSupply = twabController.getTotalSupplyTwabBetween(
      mockVault,
      initialTimestamp - 50,
      initialTimestamp + 50
    );
    assertEq(balance, _amount / 2);
    assertEq(totalSupply, _amount / 2);

    // [at,after] observation
    balance = twabController.getTwabBetween(
      mockVault,
      alice,
      initialTimestamp,
      initialTimestamp + 50
    );
    totalSupply = twabController.getTotalSupplyTwabBetween(
      mockVault,
      initialTimestamp,
      initialTimestamp + 50
    );
    assertEq(balance, _amount);
    assertEq(totalSupply, _amount);

    // [after,after] observation
    balance = twabController.getTwabBetween(
      mockVault,
      alice,
      initialTimestamp + 50,
      initialTimestamp + 51
    );
    totalSupply = twabController.getTotalSupplyTwabBetween(
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

    uint96 _mintAmount = 1000e18;

    vm.startPrank(mockVault);
    twabController.mint(alice, _mintAmount);

    assertEq(twabController.totalSupply(mockVault), _mintAmount);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _mintAmount);

    utils.timeTravel(1 days);

    changePrank(mockVault);
    twabController.mint(bob, _mintAmount);

    uint96 _totalSupplyAmountBeforeBurn = _mintAmount * 2;

    assertEq(twabController.totalSupply(mockVault), _totalSupplyAmountBeforeBurn);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), _totalSupplyAmountBeforeBurn);
    assertEq(twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp) - 1), _mintAmount);
    assertEq(
      twabController.getTotalSupplyAt(mockVault, uint32(block.timestamp)),
      _totalSupplyAmountBeforeBurn
    );

    utils.timeTravel(1 days);

    uint96 _burnAmount = 500e18;
    twabController.burn(bob, _burnAmount);

    uint96 _totalSupplyAmountAfterBurn = _totalSupplyAmountBeforeBurn - _burnAmount;

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

    twabController.mint(bob, _mintAmount);

    uint96 _totalSupplyAmountAfterMint = _totalSupplyAmountAfterBurn + _mintAmount;

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

  function testSponsorship() external {
    uint256 aliceTwab;
    uint256 totalSupplyTwab;
    uint256 bobTwab;
    uint96 amount = 100e18;
    uint32 t0 = TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH / 2);
    uint32 t1 = t0 + TwabLib.PERIOD_LENGTH;
    uint32 t2 = t1 + TwabLib.PERIOD_LENGTH;
    uint32 t3 = t2 + TwabLib.PERIOD_LENGTH;

    vm.startPrank(mockVault);
    vm.warp(t0);
    twabController.mint(alice, amount);
    vm.warp(t1);
    twabController.sponsor(alice);
    vm.warp(t2);
    twabController.transfer(alice, bob, amount / 2);
    vm.warp(t3);

    // Alice's TWAB is the same as total supply TWAB
    aliceTwab = twabController.getTwabBetween(mockVault, alice, t0, t1);
    totalSupplyTwab = twabController.getTotalSupplyTwabBetween(mockVault, t0, t1);
    assertEq(aliceTwab, totalSupplyTwab);
    assertEq(aliceTwab, amount);
    assertEq(totalSupplyTwab, amount);

    // Both TWABs are now 0 due to sponsorship
    aliceTwab = twabController.getTwabBetween(mockVault, alice, t1, t2);
    totalSupplyTwab = twabController.getTotalSupplyTwabBetween(mockVault, t1, t2);
    assertEq(aliceTwab, 0);
    assertEq(totalSupplyTwab, 0);

    // Alice's TWAB is still 0 due to sponsorship
    // Bob's TWAB is 1/2 amount, the same as total supply TWAB
    aliceTwab = twabController.getTwabBetween(mockVault, alice, t2, t3);
    bobTwab = twabController.getTwabBetween(mockVault, bob, t2, t3);
    totalSupplyTwab = twabController.getTotalSupplyTwabBetween(mockVault, t2, t3);
    assertEq(aliceTwab, 0);
    assertEq(bobTwab, amount / 2);
    assertEq(totalSupplyTwab, amount / 2);
  }

  function testSponsorshipDelegation() external {
    assertEq(twabController.totalSupply(mockVault), 0);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);

    uint96 _amount = 1000e18;

    vm.startPrank(mockVault);
    twabController.mint(alice, _amount);

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

  function testSimpleSponsorshipDelegation() external {
    assertEq(twabController.totalSupply(mockVault), 0);
    assertEq(twabController.totalSupplyDelegateBalance(mockVault), 0);

    uint96 _amount = 10;

    vm.startPrank(mockVault);
    twabController.mint(alice, _amount);
    twabController.mint(bob, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.balanceOf(mockVault, bob), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, twabController.SPONSORSHIP_ADDRESS()), 0);

    twabController.sponsor(bob);
    vm.stopPrank();
    vm.prank(alice);
    twabController.delegate(mockVault, bob);

    // Balances stay the same
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.balanceOf(mockVault, bob), _amount);
    // Delegate balances have changed
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, twabController.SPONSORSHIP_ADDRESS()), 0);
  }

  function testMint() external {
    uint96 _amount = 1000e18;
    vm.expectEmit(true, true, false, true);
    emit IncreasedBalance(mockVault, alice, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit ObservationRecorded(
      mockVault,
      alice,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({
        balance: _amount,
        cumulativeBalance: 0,
        timestamp: uint32(block.timestamp)
      })
    );

    vm.expectEmit(true, false, false, true);
    emit IncreasedTotalSupply(mockVault, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit TotalSupplyObservationRecorded(
      mockVault,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({
        balance: _amount,
        cumulativeBalance: 0,
        timestamp: uint32(block.timestamp)
      })
    );

    vm.startPrank(mockVault);

    twabController.mint(alice, _amount);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, _amount);
    assertEq(accountDetails.delegateBalance, _amount);

    vm.stopPrank();
  }

  function testBurn() external {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    vm.expectEmit(true, true, false, true);
    emit DecreasedBalance(mockVault, alice, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit ObservationRecorded(
      mockVault,
      alice,
      0,
      0,
      false,
      ObservationLib.Observation({
        balance: 0,
        cumulativeBalance: 0,
        timestamp: uint32(block.timestamp)
      })
    );

    vm.expectEmit(true, false, false, true);
    emit DecreasedTotalSupply(mockVault, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit TotalSupplyObservationRecorded(
      mockVault,
      0,
      0,
      false,
      ObservationLib.Observation({
        balance: 0,
        cumulativeBalance: 0,
        timestamp: uint32(block.timestamp)
      })
    );
    twabController.burn(alice, _amount);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    TwabLib.AccountDetails memory accountDetails = account.details;

    assertEq(accountDetails.balance, 0);
    assertEq(accountDetails.delegateBalance, 0);

    vm.stopPrank();
  }

  function testIsNewEvent() external {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    vm.expectEmit(true, true, false, true);
    emit IncreasedBalance(mockVault, alice, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit ObservationRecorded(
      mockVault,
      alice,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({
        balance: _amount,
        cumulativeBalance: 0,
        timestamp: uint32(block.timestamp)
      })
    );

    vm.expectEmit(true, false, false, true);
    emit IncreasedTotalSupply(mockVault, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit TotalSupplyObservationRecorded(
      mockVault,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({
        balance: _amount,
        cumulativeBalance: 0,
        timestamp: uint32(block.timestamp)
      })
    );
    twabController.mint(alice, _amount);

    vm.expectEmit(true, true, false, true);
    emit DecreasedBalance(mockVault, alice, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit ObservationRecorded(
      mockVault,
      alice,
      0,
      0,
      false,
      ObservationLib.Observation({
        balance: 0,
        cumulativeBalance: 0,
        timestamp: uint32(block.timestamp)
      })
    );

    vm.expectEmit(true, false, false, true);
    emit DecreasedTotalSupply(mockVault, _amount, _amount);

    vm.expectEmit(true, false, false, true);
    emit TotalSupplyObservationRecorded(
      mockVault,
      0,
      0,
      false,
      ObservationLib.Observation({
        balance: 0,
        cumulativeBalance: 0,
        timestamp: uint32(block.timestamp)
      })
    );
    twabController.burn(alice, _amount);
    vm.stopPrank();
  }

  function testTransfer() external {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);

    changePrank(alice);
    twabController.delegate(mockVault, bob);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);

    changePrank(mockVault);
    twabController.transfer(alice, charlie, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, charlie), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, charlie), _amount);

    vm.stopPrank();
  }

  /* ============ delegate ============ */

  function testDelegate() external {
    vm.startPrank(mockVault);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    assertEq(twabController.delegateOf(mockVault, alice), alice);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), _amount);

    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);
    assertEq(twabController.balanceOf(mockVault, bob), 0);

    assertEq(twabController.delegateBalanceOf(mockVault, charlie), 0);
    assertEq(twabController.balanceOf(mockVault, charlie), 0);

    changePrank(alice);
    twabController.delegate(mockVault, bob);

    assertEq(twabController.delegateOf(mockVault, alice), bob);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), _amount);

    assertEq(twabController.balanceOf(mockVault, charlie), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, charlie), 0);

    twabController.delegate(mockVault, charlie);

    assertEq(twabController.delegateOf(mockVault, alice), charlie);
    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, bob), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, bob), 0);

    assertEq(twabController.balanceOf(mockVault, charlie), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, charlie), _amount);

    changePrank(mockVault);
    twabController.mint(alice, _amount);

    uint96 _totalAmount = _amount * 2;

    assertEq(twabController.balanceOf(mockVault, alice), _totalAmount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, charlie), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, charlie), _totalAmount);

    vm.stopPrank();
  }

  function testDelegateToSponsorship() external {
    address _sponsorshipAddress = twabController.SPONSORSHIP_ADDRESS();

    assertEq(twabController.delegateOf(mockVault, alice), alice);

    vm.startPrank(mockVault);
    twabController.sponsor(alice);

    assertEq(twabController.delegateOf(mockVault, alice), _sponsorshipAddress);

    uint96 _amount = 1000e18;
    twabController.mint(alice, _amount);

    assertEq(twabController.balanceOf(mockVault, alice), _amount);
    assertEq(twabController.delegateBalanceOf(mockVault, alice), 0);

    assertEq(twabController.balanceOf(mockVault, _sponsorshipAddress), 0);
    assertEq(twabController.delegateBalanceOf(mockVault, _sponsorshipAddress), 0);

    vm.stopPrank();
  }

  function testDelegateAlreadySet() external {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(SameDelegateAlreadySet.selector, alice));
    twabController.delegate(mockVault, alice);

    vm.stopPrank();
  }

  /* ============ TWAB ============ */

  struct ObservationInfo {
    uint32 timestamp;
    uint96 amount;
    uint16 expectedIndex;
  }

  function mintAndValidate(
    address vault,
    address user,
    ObservationInfo memory observation
  ) internal {
    vm.startPrank(vault);
    vm.warp(observation.timestamp);
    twabController.mint(user, observation.amount);
    TwabLib.Account memory account = twabController.getAccount(vault, user);
    assertEq(account.observations[observation.expectedIndex].timestamp, observation.timestamp);
    assertEq(account.observations[observation.expectedIndex + 1].timestamp, 0);
    assertEq(account.details.nextObservationIndex, observation.expectedIndex + 1);
    assertEq(account.details.cardinality, observation.expectedIndex + 1);
    vm.stopPrank();
  }

  function burnAndValidate(
    address vault,
    address user,
    ObservationInfo memory observation
  ) internal {
    vm.startPrank(vault);
    vm.warp(observation.timestamp);
    twabController.burn(user, observation.amount);
    TwabLib.Account memory account = twabController.getAccount(vault, user);
    assertEq(account.observations[observation.expectedIndex].timestamp, observation.timestamp);
    assertEq(account.observations[observation.expectedIndex + 1].timestamp, 0);
    assertEq(account.details.nextObservationIndex, observation.expectedIndex + 1);
    assertEq(account.details.cardinality, observation.expectedIndex + 1);
    vm.stopPrank();
  }

  function mintAndValidateMultiple(
    address vault,
    address user,
    ObservationInfo[] memory observations
  ) internal {
    uint256 totalBalance = 0;
    for (uint256 i = 0; i < observations.length; i++) {
      // Update TWAB and validate it overwrote properly
      mintAndValidate(vault, user, observations[i]);

      // Validate balances
      uint256 balance = twabController.balanceOf(vault, user);
      uint256 delegateBalance = twabController.delegateBalanceOf(vault, user);
      totalBalance += observations[i].amount;
      assertEq(balance, totalBalance);
      assertEq(delegateBalance, totalBalance);
    }
  }

  function testOverwriteObservations_HappyPath() external {
    uint96 amount = 1e18;
    uint32 periodTenth = TwabLib.PERIOD_LENGTH / 10;
    uint32 t0 = TwabLib.PERIOD_OFFSET;
    uint32 t1 = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH;
    uint32 t2 = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH * 2;
    ObservationInfo[] memory testObservations = new ObservationInfo[](8);
    testObservations[0] = ObservationInfo(t0, amount, 0);
    testObservations[1] = ObservationInfo(t0 + periodTenth, amount, 1);
    testObservations[2] = ObservationInfo(t0 + (periodTenth * 2), amount, 1);
    testObservations[3] = ObservationInfo(t0 + (periodTenth * 3), amount, 1);
    testObservations[4] = ObservationInfo(t1, amount, 1);
    testObservations[5] = ObservationInfo(t1 + periodTenth, amount, 2);
    testObservations[6] = ObservationInfo(t2, amount, 2);
    testObservations[7] = ObservationInfo(t2 + periodTenth, amount, 3);
    mintAndValidateMultiple(mockVault, alice, testObservations);
  }

  function testOverwriteObservations_LongPeriodBetween() external {
    uint96 amount = 1e18;
    uint32 periodTenth = TwabLib.PERIOD_LENGTH / 10;
    uint32 t0 = TwabLib.PERIOD_OFFSET;
    uint32 t1 = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH;
    uint32 t2 = TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * 42);
    ObservationInfo[] memory testObservations = new ObservationInfo[](7);
    testObservations[0] = ObservationInfo(t0, amount, 0);
    testObservations[1] = ObservationInfo(t0 + periodTenth, amount, 1);
    testObservations[2] = ObservationInfo(t1 + periodTenth, amount, 2);
    testObservations[3] = ObservationInfo(t1 + (periodTenth * 2), amount, 2);
    testObservations[4] = ObservationInfo(t1 + (periodTenth * 3), amount, 2);
    testObservations[5] = ObservationInfo(t2 + periodTenth, amount, 3);
    testObservations[6] = ObservationInfo(t2 + (periodTenth * 2), amount, 3);
    mintAndValidateMultiple(mockVault, alice, testObservations);
  }

  function testOverwriteObservations_FullStateCheck() external {
    uint96 amount = 1e18;
    uint32 periodTenth = TwabLib.PERIOD_LENGTH / 10;
    uint32 t0 = TwabLib.PERIOD_OFFSET;
    uint32 t1 = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH;
    uint32 t2 = TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * 2);
    ObservationInfo[] memory testObservations = new ObservationInfo[](5);
    testObservations[0] = ObservationInfo(t0, amount, 0);
    testObservations[1] = ObservationInfo(t1, amount, 1);
    testObservations[2] = ObservationInfo(t2, amount, 2);
    testObservations[3] = ObservationInfo(t2 + (periodTenth * 8), amount, 3);
    testObservations[4] = ObservationInfo(t2 + (periodTenth * 9), amount, 3);
    mintAndValidateMultiple(mockVault, alice, testObservations);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    assertEq(account.observations[0].cumulativeBalance, 0);
    assertEq(account.observations[1].cumulativeBalance, 86400e18);
    assertEq(account.observations[2].cumulativeBalance, 259200e18);
    assertEq(account.observations[3].cumulativeBalance, 501120e18);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestObservation(
      mockVault,
      alice
    );

    assertEq(twab.cumulativeBalance, 501120e18);
    assertEq(twab.timestamp, t2 + (periodTenth * 9));
    assertEq(index, 3);
  }

  function testGetOldestAndNewestTwab() external {
    (uint16 newestIndex, ObservationLib.Observation memory newestObservation) = twabController
      .getNewestObservation(mockVault, alice);

    assertEq(newestObservation.cumulativeBalance, 0);
    assertEq(newestObservation.timestamp, 0);
    assertEq(newestIndex, MAX_CARDINALITY - 1);

    (uint16 oldestIndex, ObservationLib.Observation memory oldestObservation) = twabController
      .getOldestObservation(mockVault, alice);

    assertEq(oldestObservation.cumulativeBalance, 0);
    assertEq(oldestObservation.timestamp, 0);
    assertEq(oldestIndex, 0);

    vm.startPrank(mockVault);
    uint96 _amount = 1000e18;

    // Wrap around the TWAB storage
    uint32 t = TwabLib.PERIOD_OFFSET;
    for (uint256 i = 0; i <= MAX_CARDINALITY; i++) {
      vm.warp(t);
      twabController.mint(alice, _amount);
      t += TwabLib.PERIOD_LENGTH;
    }

    (newestIndex, newestObservation) = twabController.getNewestObservation(mockVault, alice);

    assertEq(newestObservation.cumulativeBalance, 5771088000000e18);
    assertEq(
      newestObservation.timestamp,
      TwabLib.PERIOD_OFFSET + (TwabLib.PERIOD_LENGTH * (MAX_CARDINALITY))
    );
    assertEq(newestIndex, 0);

    (oldestIndex, oldestObservation) = twabController.getOldestObservation(mockVault, alice);

    assertEq(oldestObservation.cumulativeBalance, 86400000e18);
    assertEq(oldestObservation.timestamp, TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH);
    assertEq(oldestIndex, 1);

    uint256 aliceTwab = twabController.getTwabBetween(
      mockVault,
      alice,
      oldestObservation.timestamp,
      newestObservation.timestamp
    );
    uint256 totalSupplyTwab = twabController.getTotalSupplyTwabBetween(
      mockVault,
      oldestObservation.timestamp,
      newestObservation.timestamp
    );

    assertEq(aliceTwab, totalSupplyTwab);

    vm.stopPrank();
  }

  function testTwabEquivalence() external {
    vm.startPrank(mockVault);
    uint96 _amount = 100e18;

    twabController.mint(alice, _amount);
    twabController.mint(bob, _amount);
    utils.timeTravel(TwabLib.PERIOD_LENGTH);
    twabController.transfer(alice, bob, _amount / 2);
    utils.timeTravel(TwabLib.PERIOD_LENGTH / 2);
    twabController.mint(alice, _amount);
    twabController.mint(bob, _amount);

    assertTwabEquivalence();

    vm.stopPrank();
  }

  function assertTwabEquivalence() internal {
    ObservationLib.Observation memory newestObservation;
    ObservationLib.Observation memory newestAliceObservation;
    ObservationLib.Observation memory newestBobObservation;
    uint256 aliceTwab;
    uint256 bobTwab;
    uint256 totalSupplyTwab;

    (, newestObservation) = twabController.getNewestTotalSupplyObservation(mockVault);
    (, newestAliceObservation) = twabController.getNewestObservation(mockVault, alice);
    (, newestBobObservation) = twabController.getNewestObservation(mockVault, bob);

    if (newestObservation.timestamp < newestAliceObservation.timestamp) {
      newestObservation = newestAliceObservation;
    }
    if (newestObservation.timestamp < newestBobObservation.timestamp) {
      newestObservation = newestBobObservation;
    }

    aliceTwab = twabController.getTwabBetween(
      mockVault,
      alice,
      TwabLib.PERIOD_OFFSET,
      newestObservation.timestamp
    );
    bobTwab = twabController.getTwabBetween(
      mockVault,
      bob,
      TwabLib.PERIOD_OFFSET,
      newestObservation.timestamp
    );
    totalSupplyTwab = twabController.getTotalSupplyTwabBetween(
      mockVault,
      TwabLib.PERIOD_OFFSET,
      newestObservation.timestamp
    );

    assertLt(aliceTwab, bobTwab);
    // Sum of Alice and Bob's TWABs should be less than or equal to the total supply TWAB
    assertApproxEqAbs(aliceTwab + bobTwab, totalSupplyTwab, 1);
    assertTimeRangeIsSafe(alice, TwabLib.PERIOD_OFFSET, newestObservation.timestamp);
  }

  function assertTimeRangeIsSafe(address user, uint32 start, uint32 end) internal {
    bool isSafeForUser = twabController.isTimeRangeSafe(mockVault, user, start, end);
    bool isSafeForTotalSupply = twabController.isTotalSupplyTimeRangeSafe(mockVault, start, end);
    assertTrue(isSafeForUser);
    assertTrue(isSafeForTotalSupply);
  }

  function testFlashLoanMitigation() external {
    uint96 largeAmount = 1000000e18;
    uint32 drawStart = TwabLib.PERIOD_OFFSET;
    uint32 drawEnd = drawStart + (TwabLib.PERIOD_LENGTH * 24); // Assume 24 periods in a day for testing purposes.

    // Store actual balance during draw N at the end of draw N+1
    vm.warp(drawEnd + 1 seconds);
    uint256 actualDrawBalance = twabController.getTwabBetween(mockVault, alice, drawStart, drawEnd);

    // "Flash loan" deposit immediately at draw start
    mintAndValidate(mockVault, alice, ObservationInfo(drawStart, largeAmount, 0));

    // Withdraw in the same block
    // Note - Second event in the same block doesn't trigger a new event. Observation will have no concept of the flash loan.
    // The flash loan will only be counted for the period of time it was held. Since all of this happens in the same block it will not be captured.
    burnAndValidate(mockVault, alice, ObservationInfo(drawStart, largeAmount, 0));

    // Store manipulated balance during draw N at the end of draw N+1
    vm.warp(drawEnd + 1 seconds);
    uint256 manipulatedDrawBalance = twabController.getTwabBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    assertEq(manipulatedDrawBalance, actualDrawBalance);
  }

  function testImmediateWithdrawalMitigation() external {
    uint96 largeAmount = 1000000e18;
    uint32 drawStart = TwabLib.PERIOD_OFFSET + TwabLib.PERIOD_LENGTH; // Offset draws and periods by 1 to ensure hardcoded value is safe.
    uint32 drawEnd = drawStart + (TwabLib.PERIOD_LENGTH * 24); // Assume 24 periods in a day for testing purposes.

    // Deposit immediately before draw start
    mintAndValidate(mockVault, alice, ObservationInfo(drawStart - 1 seconds, largeAmount, 0));

    // Withdraw immediately after draw start
    burnAndValidate(mockVault, alice, ObservationInfo(drawStart + 1 seconds, largeAmount, 1));

    // Store actual balance during draw N at the end of draw N+1
    vm.warp(drawEnd + 1 seconds);
    uint256 actualDrawBalance = twabController.getTwabBetween(mockVault, alice, drawStart, drawEnd);

    // Overwrite with large amount to force average across the entire draw period
    mintAndValidate(mockVault, alice, ObservationInfo(drawEnd + 1 seconds, largeAmount, 2));

    // Store attempted manipulated balance during draw N at the end of draw N+1
    vm.warp(drawEnd + 1 seconds);
    uint256 manipulatedDrawBalance = twabController.getTwabBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    assertEq(manipulatedDrawBalance, actualDrawBalance);
  }
}
