// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { TwabController } from "../../../src/TwabController.sol";
import { TwabLib } from "../../../src/libraries/TwabLib.sol";
import { ObservationLib, MAX_CARDINALITY } from "../../../src/libraries/ObservationLib.sol";
import { VaultAddressSet, VaultAddressSetLib } from "../helpers/VaultAddressSet.sol";

import { Utils } from "../../utils/Utils.sol";

contract TwabControllerHandler is CommonBase, StdCheats, StdUtils {
  using VaultAddressSetLib for VaultAddressSet;
  uint32 public constant PERIOD_OFFSET = 10 days;
  uint32 public constant PERIOD_LENGTH = 1 days;
  mapping(string => uint256) public h_fnCallCount;

  Utils public utils = new Utils();
  TwabController public twabController;

  address[] internal actors;
  address[] internal vaults;
  VaultAddressSet internal _addrs;

  address internal currentActor;
  address internal currentVault;

  // h_ to identify handler variables.
  uint256 public h_totalMinted;
  uint256 public h_totalBurned;
  uint256 public h_initialBlockTimestamp = block.timestamp;
  uint256 public h_blockTimestamp = PERIOD_OFFSET;
  uint256 public h_blockTimestampChanges;
  mapping(address => ObservationLib.Observation) public h_oldestObservationPerVault;
  mapping(address => ObservationLib.Observation) public h_newestObservationPerVault;

  constructor(TwabController _twabController) {
    twabController = _twabController;

    // Initialize the state of the system to have some actors and vaults to reuse.
    actors = utils.createUsers(10);
    vaults = utils.createUsers(3);
  }

  /* ============ Mint ============ */

  function mint(
    uint96 amount,
    uint256 vaultSeed,
    uint256 actorSeed,
    uint256 numSeconds
  ) public useAnyVaultAndActor(vaultSeed, actorSeed) countCall("mint") {
    timeTravel(numSeconds);

    amount = uint96(
      bound(amount, 1, type(uint96).max - uint96(twabController.totalSupply(currentVault)))
    );

    vm.prank(currentVault);
    twabController.mint(currentActor, amount);

    h_totalMinted += amount;
  }

  /* ============ Burn ============ */

  function burn(
    uint96 amount,
    uint256 vaultSeed,
    uint256 actorSeed,
    uint256 numSeconds
  ) public useVaultAndActorWithBalance(vaultSeed, actorSeed) countCall("burn") {
    timeTravel(numSeconds);
    amount = uint96(bound(amount, 0, twabController.balanceOf(currentVault, currentActor)));

    vm.prank(currentVault);
    twabController.burn(currentActor, amount);

    h_totalBurned += amount;
  }

  /* ============ Transfer ============ */

  function transfer(
    uint96 amount,
    uint256 vaultSeed,
    uint256 actorSeed,
    address to,
    uint256 numSeconds
  ) public useVaultAndActorWithBalance(vaultSeed, actorSeed) countCall("transfer") {
    timeTravel(numSeconds);

    require(to != address(0) && to != address(1), "Invalid to address");

    amount = uint96(bound(amount, 0, twabController.balanceOf(currentVault, currentActor)));

    // Manually add the new actor so they are tracked.
    if (amount > 0) {
      _addrs.addActor(currentVault, to);
    }

    // Transfer from current actor to new actor
    vm.prank(currentVault);
    twabController.transfer(currentActor, to, amount);
  }

  /* ============ Delegate ============ */

  // To reduce the amount of calls to delegating/sponsoring we combine the two.
  function delegate(
    uint256 vaultSeed,
    uint256 actorSeed,
    uint256 delegateSeed,
    uint256 numSeconds,
    bool sponsor
  ) public useVaultAndActorWithBalance(vaultSeed, actorSeed) countCall("delegate") {
    timeTravel(numSeconds);

    if (sponsor) {
      // Sponsor the new delegate
      vm.prank(currentVault);
      twabController.sponsor(currentActor);
    } else {
      address newDelegate = _addrs.randomVaultActor(currentVault, delegateSeed);

      // Manually add the new actor so they are tracked.
      if (twabController.balanceOf(currentVault, currentActor) > 0) {
        _addrs.addActor(currentVault, newDelegate);
      }

      // Delegate to the new actor
      vm.prank(currentActor);
      twabController.delegate(currentVault, newDelegate);
    }
  }

  /* ============ Helper Modifiers ============ */

  modifier countCall(string memory key) {
    h_fnCallCount[key]++;
    _;
  }

  modifier useAnyVaultAndActor(uint256 vaultSeed, uint256 actorSeed) {
    currentVault = random(vaults, vaultSeed);
    currentActor = random(actors, actorSeed);
    _addrs.addActor(currentVault, currentActor);
    _;
  }

  modifier useVaultAndActorWithBalance(uint256 vaultSeed, uint256 actorSeed) {
    // Look up actors and vaults that have already been used, not just any.
    currentVault = _addrs.randomVault(vaultSeed);
    currentActor = _addrs.randomVaultActor(currentVault, actorSeed);

    require(twabController.balanceOf(currentVault, currentActor) > 0, "Actor has no balance");
    _;
  }

  /* ============ Helper Functions ============ */

  function random(address[] memory addresses, uint256 seed) public pure returns (address) {
    return addresses[seed % addresses.length];
  }

  /**
   * We need to alter time to be able to test Observation overwrites.
   * This gets called at the start of each fn called.
   * @param numSeconds The number of seconds to time travel.
   */
  function timeTravel(uint256 numSeconds) public {
    // Bound the time travel to a reasonable amount.
    uint256 time = bound(numSeconds, 0, 24 * PERIOD_LENGTH);
    h_blockTimestamp += time;
    vm.warp(h_blockTimestamp);

    h_blockTimestampChanges++;
  }

  function forEachVault(function(address) external func) public {
    return _addrs.forEachVault(func);
  }

  function forEachVaultActor(address vault, function(address, address) external func) public {
    return _addrs.forEachVaultActor(vault, func);
  }

  function forEachVaultActorPair(function(address, address) external func) public {
    return _addrs.forEachVaultActorPair(func);
  }

  function reduceVaults(
    uint256 acc,
    function(uint256, address) external returns (uint256) func
  ) public returns (uint256) {
    return _addrs.reduceVaults(acc, func);
  }

  function reduceVaultActors(
    uint256 acc,
    address vault,
    function(uint256, address, address) external returns (uint256) func
  ) public returns (uint256) {
    return _addrs.reduceVaultActors(acc, vault, func);
  }

  function reduceVaultActorPairs(
    uint256 acc,
    function(uint256, address, address) external returns (uint256) func
  ) public returns (uint256) {
    return _addrs.reduceVaultActorPairs(acc, func);
  }

  function reduceVaultsNewestTimestampSafety() external view returns (bool, bool) {
    bool isVaultsSafe = true;
    bool isActorsSafe = true;
    ObservationLib.Observation memory newestObservation;

    // For Each Vault
    for (uint256 i; i < _addrs.vaults.length; ++i) {
      address vault = _addrs.vaults[i];

      // If the vault is saved
      if (_addrs.vaultSaved[vault]) {
        (, newestObservation) = twabController.getNewestTotalSupplyObservation(vault);

        // Check if the newest observation is safe for this vault
        isVaultsSafe = isVaultsSafe && twabController.hasFinalized(newestObservation.timestamp);

        // For Each Actor
        for (uint256 j; j < _addrs.actors[vault].length; ++j) {
          address actor = _addrs.actors[vault][j];

          // If the actor is saved
          if (_addrs.actorSaved[vault][actor]) {
            (, newestObservation) = twabController.getNewestObservation(vault, actor);

            // Check if the newest observation is safe for this actor
            isActorsSafe = isActorsSafe && twabController.hasFinalized(newestObservation.timestamp);
          }
        }
      }
    }
    return (isVaultsSafe, isActorsSafe);
  }

  function reduceTimestampChecks() external returns (bool, bool) {
    bool isVaultsSafe = true;
    bool isActorsSafe = true;
    ObservationLib.Observation memory newestObservation;
    ObservationLib.Observation memory observation;
    TwabLib.Account memory account;

    // Need to jump back to the latest time stamp to ensure hasFinalized checks are safe.
    vm.warp(h_blockTimestamp);

    // For Each Vault
    for (uint256 i; i < _addrs.vaults.length; ++i) {
      address vault = _addrs.vaults[i];

      // If the vault is saved
      if (_addrs.vaultSaved[vault]) {
        account = twabController.getTotalSupplyAccount(vault);
        (, newestObservation) = twabController.getNewestTotalSupplyObservation(vault);

        // Check if the newest observation is safe for this vault
        isVaultsSafe = isVaultsSafe && twabController.hasFinalized(newestObservation.timestamp);

        // Check if each observation is safe for this vault
        for (uint256 o_i; o_i < account.details.cardinality; ++o_i) {
          observation = account.observations[o_i];
          isVaultsSafe = isVaultsSafe && twabController.hasFinalized(observation.timestamp);
        }

        // Check if each period end timestamp is safe for this vault
        uint256 newestPeriod = twabController.getTimestampPeriod(newestObservation.timestamp);
        for (uint32 p_i = 1; p_i < newestPeriod; ++p_i) {
          uint32 timestamp = PERIOD_OFFSET + (p_i * PERIOD_LENGTH);
          isVaultsSafe = isVaultsSafe && twabController.hasFinalized(timestamp);
        }

        // For Each Actor
        for (uint256 j; j < _addrs.actors[vault].length; ++j) {
          address actor = _addrs.actors[vault][j];

          // If the actor is saved
          if (_addrs.actorSaved[vault][actor]) {
            account = twabController.getAccount(vault, actor);
            (, newestObservation) = twabController.getNewestObservation(vault, actor);

            // Check if the newest observation is safe for this actor
            isActorsSafe = isActorsSafe && twabController.hasFinalized(newestObservation.timestamp);

            // Check if each observation is safe for this actor
            for (uint256 o_i; o_i < account.details.cardinality; ++o_i) {
              observation = account.observations[o_i];
              isActorsSafe = isActorsSafe && twabController.hasFinalized(observation.timestamp);
            }

            // Check if each period end timestamp is safe for this actor
            newestPeriod = twabController.getTimestampPeriod(newestObservation.timestamp);
            for (uint32 p_i = 1; p_i <= newestPeriod; ++p_i) {
              uint32 timestamp = PERIOD_OFFSET + (p_i * PERIOD_LENGTH);
              twabController.getTimestampPeriod(timestamp);
              isVaultsSafe = isVaultsSafe && twabController.hasFinalized(timestamp);
            }
          }
        }
      }
    }
    return (isVaultsSafe, isActorsSafe);
  }

  function reduceFullRangeTwabs() external view returns (uint256, uint256) {
    uint256 vaultAcc = 0;
    uint256 actorAcc = 0;
    ObservationLib.Observation memory newestObservation;

    // For Each Vault
    for (uint256 i; i < _addrs.vaults.length; ++i) {
      address vault = _addrs.vaults[i];

      // If the vault is saved
      if (_addrs.vaultSaved[vault]) {
        // Find newest observation for that vault
        (, newestObservation) = twabController.getNewestTotalSupplyObservation(vault);

        uint32 finalizedBy = uint32(block.timestamp - PERIOD_LENGTH);

        // If there's no range to query across, skip
        if (finalizedBy > PERIOD_OFFSET) {
          // Add TWAB between time start and newest observation for that vault's total supply
          vaultAcc += twabController.getTotalSupplyTwabBetween(vault, PERIOD_OFFSET, finalizedBy);

          // For Each Actor
          for (uint256 j; j < _addrs.actors[vault].length; ++j) {
            // If the actor is saved
            if (_addrs.actorSaved[vault][_addrs.actors[vault][j]]) {
              // Add TWAB between oldest and newest observation for that user in the vault
              actorAcc += twabController.getTwabBetween(
                vault,
                _addrs.actors[vault][j],
                PERIOD_OFFSET,
                finalizedBy
              );
            }
          }
        }
      }
    }

    return (vaultAcc, actorAcc);
  }

  function sumUserBalancesAcrossVaults() external returns (uint256) {
    return reduceVaultActorPairs(0, this.accumulateActorBalance);
  }

  function sumUserFullRangeTwabsAcrossVaults() external returns (uint256) {
    return reduceVaultActorPairs(0, this.accumulateActorBalance);
  }

  function sumTotalSupplyAcrossVaults() external returns (uint256) {
    return reduceVaults(0, this.accumulateTotalSupply);
  }

  function accumulateActorBalance(
    uint256 acc,
    address vault,
    address actor
  ) external view returns (uint256) {
    return acc + twabController.balanceOf(vault, actor);
  }

  function accumulateActorTwab(
    uint256 acc,
    address vault,
    address actor,
    uint32 startTime,
    uint32 endTime
  ) external view returns (uint256) {
    return acc + twabController.getTwabBetween(vault, actor, startTime, endTime);
  }

  function accumulateTotalSupply(uint256 acc, address vault) external view returns (uint256) {
    return acc + twabController.totalSupply(vault);
  }
}
