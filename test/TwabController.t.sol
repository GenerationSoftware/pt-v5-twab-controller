// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

import { TwabController } from "src/TwabController.sol";
import { TwabLib } from "src/libraries/TwabLib.sol";
import { ObservationLib } from "src/libraries/ObservationLib.sol";
import { BaseSetup } from "test/utils/BaseSetup.sol";

contract TwabControllerTest is BaseSetup {
  TwabController public twabController;
  address public mockVault = address(0x1234);
  ERC20 public token;
  uint16 public constant MAX_CARDINALITY = 365;

  event IncreasedBalance(
    address indexed vault,
    address indexed user,
    uint112 amount,
    uint112 delegateAmount,
    bool isNew,
    ObservationLib.Observation twab
  );

  event DecreasedBalance(
    address indexed vault,
    address indexed user,
    uint112 amount,
    uint112 delegateAmount,
    bool isNew,
    ObservationLib.Observation twab
  );

  event Delegated(address indexed vault, address indexed delegator, address indexed delegate);

  event IncreasedTotalSupply(
    address indexed vault,
    uint112 amount,
    uint112 delegateAmount,
    bool isNew,
    ObservationLib.Observation twab
  );

  event DecreasedTotalSupply(
    address indexed vault,
    uint112 amount,
    uint112 delegateAmount,
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
      _amount,
      true,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );

    vm.expectEmit(true, false, false, true);
    emit IncreasedTotalSupply(
      mockVault,
      _amount,
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
      _amount,
      false,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );

    vm.expectEmit(true, false, false, true);
    emit DecreasedTotalSupply(
      mockVault,
      _amount,
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
    vm.expectEmit(true, true, false, true);
    emit IncreasedBalance(
      mockVault,
      alice,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );
    vm.expectEmit(true, false, false, true);
    emit IncreasedTotalSupply(
      mockVault,
      _amount,
      _amount,
      true,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );
    twabController.twabMint(alice, _amount);

    vm.expectEmit(true, true, false, true);
    emit DecreasedBalance(
      mockVault,
      alice,
      _amount,
      _amount,
      false,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );

    vm.expectEmit(true, false, false, true);
    emit DecreasedTotalSupply(
      mockVault,
      _amount,
      _amount,
      false,
      ObservationLib.Observation({ amount: 0, timestamp: uint32(block.timestamp) })
    );
    twabController.twabBurn(alice, _amount);
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

  function testSecondObservationAlwaysStored() external {
    deal({ token: address(token), to: alice, give: 10000e18 });

    TwabLib.Account memory account;
    uint112 _amount = 1000e18;
    uint256 t0 = 1 days;
    uint256 t1 = 1 days + 12 hours;

    vm.startPrank(mockVault);

    vm.warp(t0);
    twabController.twabMint(alice, _amount);
    account = twabController.getAccount(mockVault, alice);
    assertEq(account.twabs[0].timestamp, t0);
    assertEq(account.twabs[1].timestamp, 0);
    assertEq(account.details.balance, _amount);
    assertEq(account.details.delegateBalance, _amount);

    vm.warp(t1);
    twabController.twabMint(alice, _amount);
    account = twabController.getAccount(mockVault, alice);
    assertEq(account.twabs[0].timestamp, t0);
    assertEq(account.twabs[1].timestamp, t1);
    assertEq(account.twabs[2].timestamp, 0);
    assertEq(account.details.balance, _amount * 2);
    assertEq(account.details.delegateBalance, _amount * 2);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestTwab(
      mockVault,
      alice
    );

    assertEq(twab.amount, 43200000e18);
    assertEq(twab.timestamp, t1);
    assertEq(index, 1);
  }

  struct TestTwabObservation {
    uint256 timestamp;
    uint112 amount;
    uint16 expectedIndex;
  }

  function validateTwabMintObservation(
    address vault,
    address user,
    TestTwabObservation memory twab
  ) internal {
    vm.startPrank(vault);
    vm.warp(twab.timestamp);
    twabController.twabMint(user, twab.amount);
    // TODO: Uncomment
    // TwabLib.Account memory account = twabController.getAccount(vault, user);
    // assertEq(account.twabs[twab.expectedIndex].timestamp, twab.timestamp);
    // assertEq(account.twabs[twab.expectedIndex + 1].timestamp, 0);
    // assertEq(account.details.nextTwabIndex, twab.expectedIndex + 1);
    // assertEq(account.details.cardinality, twab.expectedIndex + 1);
    vm.stopPrank();
  }

  function validateTwabBurnObservation(
    address vault,
    address user,
    TestTwabObservation memory twab
  ) internal {
    vm.startPrank(vault);
    vm.warp(twab.timestamp);
    twabController.twabBurn(user, twab.amount);
    TwabLib.Account memory account = twabController.getAccount(vault, user);
    // TODO: Uncomment
    // assertEq(account.twabs[twab.expectedIndex].timestamp, twab.timestamp);
    // assertEq(account.twabs[twab.expectedIndex + 1].timestamp, 0);
    // assertEq(account.details.nextTwabIndex, twab.expectedIndex + 1);
    // assertEq(account.details.cardinality, twab.expectedIndex + 1);
    vm.stopPrank();
  }

  function validateTwabMintObservations(
    address vault,
    address user,
    TestTwabObservation[] memory twabs
  ) internal {
    uint256 totalBalance = 0;
    for (uint256 i = 0; i < twabs.length; i++) {
      // Update TWAB and validate it overwrote properly
      validateTwabMintObservation(vault, user, twabs[i]);

      // Validate balances
      uint256 balance = twabController.balanceOf(vault, user);
      uint256 delegateBalance = twabController.delegateBalanceOf(vault, user);
      totalBalance += twabs[i].amount;
      assertEq(balance, totalBalance);
      assertEq(delegateBalance, totalBalance);
    }
  }

  function testOverwriteObservations_HappyPath() external {
    uint112 amount = 1e18;
    TestTwabObservation[] memory testTwabs = new TestTwabObservation[](8);
    testTwabs[0] = TestTwabObservation(1 days, amount, 0);
    testTwabs[1] = TestTwabObservation(1 days + 1 hours, amount, 1);
    testTwabs[2] = TestTwabObservation(1 days + 2 hours, amount, 1);
    testTwabs[3] = TestTwabObservation(1 days + 3 hours, amount, 1);
    testTwabs[4] = TestTwabObservation(2 days, amount, 1);
    testTwabs[5] = TestTwabObservation(2 days + 1 hours, amount, 2); // N - N-1 >= 24h (2 days - 1 days >= 24h)
    testTwabs[6] = TestTwabObservation(3 days, amount, 2);
    testTwabs[7] = TestTwabObservation(3 days + 1 hours, amount, 3); // N - N-1 >= 24h (3 days - 2 days >= 24h)
    validateTwabMintObservations(mockVault, alice, testTwabs);
  }

  function testOverwriteObservations_LongPeriodBetween() external {
    uint112 amount = 1e18;
    TestTwabObservation[] memory testTwabs = new TestTwabObservation[](5);
    testTwabs[0] = TestTwabObservation(1 days, amount, 0);
    testTwabs[1] = TestTwabObservation(1 days + 1 hours, amount, 1);
    testTwabs[2] = TestTwabObservation(2 days + 1 hours, amount, 1);
    testTwabs[3] = TestTwabObservation(42 days, amount, 2); // N - N-1 >= 24h (2 days + 1 hours - 1 days >= 24h)
    testTwabs[4] = TestTwabObservation(42 days + 1 hours, amount, 3); // N - N-1 >= 24h (42 days - 2 days + 1 hours >= 24h)
    validateTwabMintObservations(mockVault, alice, testTwabs);
  }

  function testOverwriteObservations_FullStateCheck() external {
    uint112 amount = 1e18;
    TestTwabObservation[] memory testTwabs = new TestTwabObservation[](5);
    testTwabs[0] = TestTwabObservation(1 days, amount, 0);
    testTwabs[1] = TestTwabObservation(2 days, amount, 1);
    testTwabs[2] = TestTwabObservation(3 days, amount, 2); // N - N-1 >= 24h (2 days - 1 days >= 24h)
    testTwabs[3] = TestTwabObservation(3 days + 12 hours, amount, 3); // N - N-1 >= 24h (3 days - 2 days >= 24h)
    testTwabs[4] = TestTwabObservation(3 days + 18 hours, amount, 3);
    validateTwabMintObservations(mockVault, alice, testTwabs);

    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    assertEq(account.twabs[0].amount, 0);
    assertEq(account.twabs[1].amount, 86400e18);
    assertEq(account.twabs[2].amount, 259200e18);
    assertEq(account.twabs[3].amount, 475200e18);
    assertEq(account.twabs[4].amount, 0);

    (uint16 index, ObservationLib.Observation memory twab) = twabController.getNewestTwab(
      mockVault,
      alice
    );

    assertEq(twab.amount, 475200e18);
    assertEq(twab.timestamp, 3 days + 18 hours);
    assertEq(index, 3);
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

  function testFlashLoanMitigation() external {
    uint112 amount = 1e18;
    uint112 largeAmount = 1000000e18;
    uint32 drawStart = 4 days;
    uint32 drawEnd = 5 days;

    // Get the TWAB controller into a state where it has some TWAB history
    validateTwabMintObservation(
      mockVault,
      alice,
      TestTwabObservation(drawStart - 2 days, amount, 0)
    );
    validateTwabBurnObservation(
      mockVault,
      alice,
      TestTwabObservation(drawStart - 1 days, amount, 1)
    );

    // Store actual balance during draw N at the end of draw N+1
    vm.warp(drawEnd + 1 days - 1 seconds);
    uint256 actualDrawBalance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    // Flash loan deposit immediately at draw start
    validateTwabMintObservation(mockVault, alice, TestTwabObservation(drawStart, largeAmount, 1));

    // Withdraw in the same block
    // Second event in the same block doesn't trigger a new event
    // Next observation will have no concept of the flash loan
    // Can I take the flash loan, trigger a new observation, claim, then burn it?
    // The flash loan will only be counted for the period of time it was held. Since all of this happens in the same block it will not be captured.
    validateTwabBurnObservation(mockVault, alice, TestTwabObservation(drawStart, largeAmount, 1));

    // Store manipulated balance during draw N at the end of draw N+1
    vm.warp(drawEnd + 1 days - 1 seconds);
    uint256 manipulatedDrawBalance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    assertEq(manipulatedDrawBalance, actualDrawBalance);
  }

  function testImmediateWithdrawalMitigation() external {
    uint112 amount = 1e18;
    uint112 largeAmount = 1000000e18;
    uint32 drawStart = 4 days;
    uint32 drawEnd = 5 days;

    // Get the TWAB controller into a state where it has some TWAB history
    validateTwabMintObservation(
      mockVault,
      alice,
      TestTwabObservation(drawStart - 2 days, amount, 0)
    );
    validateTwabBurnObservation(
      mockVault,
      alice,
      TestTwabObservation(drawStart - 2 days + 12 hours, amount, 1)
    );

    // Deposit immediately before draw start
    validateTwabMintObservation(
      mockVault,
      alice,
      TestTwabObservation(drawStart - 1 seconds, largeAmount, 1)
    );

    // Withdraw immediately after draw start
    validateTwabBurnObservation(
      mockVault,
      alice,
      TestTwabObservation(drawStart + 1 seconds, largeAmount, 1)
    );

    // Store actual balance during draw N at the end of draw N+1
    vm.warp(drawEnd + 1 days - 1 seconds);
    uint256 actualDrawBalance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    // Overwrite with large amount to force average across the entire draw period
    validateTwabMintObservation(
      mockVault,
      alice,
      TestTwabObservation(drawEnd + 1 days - 1 seconds, largeAmount, 1)
    );

    // Store attempted manipulated balance during draw N at the end of draw N+1
    vm.warp(drawEnd + 1 days - 1 seconds);
    uint256 manipulatedDrawBalance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    assertEq(manipulatedDrawBalance, actualDrawBalance);
  }

  // ======================= Exploits =======================

  // By creating tailored Observations post a TWAB Observation overwrite period, we can manipulate historic TWABs to be higher than they actually were.
  function testExploit_ObservationPostPeriodEnd() external {
    uint112 amount = 1e18;
    uint112 largeAmount = 1000000e18;
    uint32 drawStart = 4 days;
    uint32 drawEnd = 5 days;

    // Get the TWAB controller into a state where it has some TWAB history so we can ignore the special cases of the first and second Observations.
    validateTwabMintObservation(
      mockVault,
      alice,
      TestTwabObservation(drawStart - 3 days, amount, 0)
    );
    validateTwabMintObservation(
      mockVault,
      alice,
      TestTwabObservation(drawStart - 2 days, amount, 0)
    );

    // Create an Observation such that the next Observation will be recorded in a new slot and the Observation after that will overwrite the first.
    validateTwabBurnObservation(
      mockVault,
      alice,
      TestTwabObservation(drawStart + 1 seconds, amount * 2, 1)
    );

    // Store the actual balance during draw N at the end of draw N+1 (last moment that it is still claimable).
    vm.warp(drawEnd + 1 days - 1 seconds);
    uint256 actualDrawBalance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    // console.log("Pre manipuiation");
    // logObservations(6);

    // Deposit when draw N ends and draw N+1 begins.
    validateTwabMintObservation(mockVault, alice, TestTwabObservation(drawEnd, largeAmount, 1));

    // console.log("Post large deposit");
    // logObservations(6);

    // Withdraw when draw N+1 ends to overwrite the end TWAB Observation used to compute the average held during draw N.
    validateTwabBurnObservation(
      mockVault,
      alice,
      TestTwabObservation(drawEnd + 1 days - 1 seconds, largeAmount, 1)
    );

    // console.log("Post withdrawal of large deposit");
    // logObservations(6);

    // Store manipulated balance during draw N at the end of draw N+1
    vm.warp(drawEnd + 1 days - 1 seconds);
    uint256 manipulatedDrawBalance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    assertEq(manipulatedDrawBalance, actualDrawBalance);
  }

  function testExploit_FullObservationPostPeriodEnd() external {
    uint32 overwriteFrequency = 1 days;
    uint32 overwritesPerDraw = 24;
    uint112 smallAmount = 1e18;
    uint112 largeAmount = 1000000e18;
    // Setup such that the draw to manipulate is the second draw
    uint32 drawDuration = overwriteFrequency * overwritesPerDraw;
    uint32 drawStart = 0;
    uint32 drawEnd = drawStart + drawDuration;

    console.log("drawStart    %s", drawStart);
    console.log("drawEnd      %s", drawEnd);

    // Create an Observation such that the next Observation will be recorded in a new slot and the Observation after that will overwrite the first.
    validateTwabMintObservation(
      mockVault,
      alice,
      TestTwabObservation(drawEnd - overwriteFrequency + 1 seconds, smallAmount, 1)
    );

    // Store the actual balance during draw N at the end of draw N+1 (last moment that it is still claimable).
    vm.warp(drawEnd + drawDuration - 1 seconds);
    uint256 actualDrawBalance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );

    console.log("Pre manipuiation");
    console.log("actualDrawBalance    %s", actualDrawBalance);
    logObservations(6);

    // Deposit when overwrite period N ends and period N+1 begins.
    validateTwabMintObservation(mockVault, alice, TestTwabObservation(drawEnd, largeAmount, 1));

    console.log("Post large deposit");
    logObservations(6);

    // Withdraw when draw N+1 ends to overwrite the end TWAB Observation used to compute the average held during draw N.
    validateTwabBurnObservation(
      mockVault,
      alice,
      TestTwabObservation(drawEnd + overwriteFrequency - 1 seconds, largeAmount, 1)
    );

    console.log("Post withdrawal of large deposit");
    logObservations(6);

    // Store manipulated balance during draw N at the end of draw N+1
    vm.warp(drawEnd + drawDuration - 1 seconds);
    uint256 manipulatedDrawBalance = twabController.getAverageBalanceBetween(
      mockVault,
      alice,
      drawStart,
      drawEnd
    );
    console.log("manipulatedDrawBalance    %s", manipulatedDrawBalance);

    assertEq(manipulatedDrawBalance, actualDrawBalance);
  }

  // This actually results in a NEGATIVE impact on the users balance during the draw period, not an INCREASE as I intended. Still a problem though..
  // function testFailExploit_LastMomentWhale() external {
  //   uint112 amount = 100e18;
  //   uint32 drawStart = 4 days;
  //   uint32 drawEnd = 5 days;

  //   // Get the TWAB controller into a state where it has some TWAB history
  //   TestTwabObservation[] memory initialTwabs = new TestTwabObservation[](4);
  //   initialTwabs[0] = TestTwabObservation(drawStart - 3 days, amount, 0);
  //   initialTwabs[1] = TestTwabObservation(drawStart - 2 days, amount, 1);
  //   initialTwabs[2] = TestTwabObservation(drawStart - 1 days, amount, 2);

  //   // The Observation to be overwritten. Maximize the amount of time being overwritten by:
  //   // 1. Writing 1 second after the most recently finished draw started
  //   // 2. Overwriting at 1 second before current draw ends
  //   // Assuming you need the extra 1 second padding so it is inside the draw window
  //   initialTwabs[3] = TestTwabObservation(drawStart - 1 days + 1 seconds, amount, 3);
  //   validateTwabMintObservations(mockVault, alice, initialTwabs);

  //   // At the last moment before the next draw completes, cache state of system
  //   vm.warp(drawEnd + 1 days - 1 seconds);
  //   uint256 actualDrawBalance = twabController.getAverageBalanceBetween(
  //     mockVault,
  //     alice,
  //     drawStart,
  //     drawEnd
  //   );
  //   uint256 expectedBalance = amount * 4;
  //   assertEq(actualDrawBalance, expectedBalance);

  //   // Overwrite the observation with a large value
  //   validateTwabMintObservation(
  //     mockVault,
  //     alice,
  //     TestTwabObservation(drawEnd + 1 days - 1 seconds, 1000000000e18, 1)
  //   );

  //   // At the last moment before the next draw completes, cache state of system
  //   vm.warp(drawEnd + 1 days - 1 seconds);
  //   uint256 manipulatedDrawBalance = twabController.getAverageBalanceBetween(
  //     mockVault,
  //     alice,
  //     drawStart,
  //     drawEnd
  //   );

  //   // Assert that the manipulated balance is less than the expected balance.
  //   // Since we take an observation before applying the event, the historic average that changes
  //   // can only go down.
  //   assertEq(manipulatedDrawBalance, actualDrawBalance);
  // }

  // -------------------- Helpers --------------------

  function logObservations(uint256 amount) internal {
    TwabLib.Account memory account = twabController.getAccount(mockVault, alice);
    console.log("--");
    for (uint256 i = 0; i < amount; i++) {
      ObservationLib.Observation memory observation = account.twabs[i];
      console.log("Observation: ", i, observation.amount, observation.timestamp);
    }
    console.log("--");
  }
}
