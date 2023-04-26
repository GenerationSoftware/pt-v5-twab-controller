// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { Utils } from "./Utils.sol";

import { TwabLib } from "src/libraries/TwabLib.sol";
import { ObservationLib } from "src/libraries/ObservationLib.sol";

contract BaseSetup is Test {
  Utils internal utils;

  address payable[] internal users;
  address internal owner;
  address internal dev;
  address internal alice;
  address internal bob;
  address internal carole;
  address internal dave;

  function setUp() public virtual {
    utils = new Utils();
    users = utils.createUsers(6);
    owner = users[0];
    dev = users[1];
    alice = users[2];
    bob = users[3];
    carole = users[4];
    dave = users[5];
    vm.label(owner, "Owner");
    vm.label(dev, "Developer");
    vm.label(alice, "Alice");
    vm.label(bob, "Bob");
    vm.label(carole, "Carole");
    vm.label(dave, "Dave");
  }

  function logObservations(TwabLib.Account memory account, uint256 amount) internal {
    for (uint256 i = 0; i < amount; i++) {
      ObservationLib.Observation memory observation = account.twabs[i];
      console.log("Observation: ", i, observation.amount, observation.timestamp);
    }
    console.log("--");
  }
}
