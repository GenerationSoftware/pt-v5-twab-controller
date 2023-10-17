// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { Utils } from "./Utils.sol";

import { TwabLib } from "../../src/libraries/TwabLib.sol";
import { ObservationLib } from "../../src/libraries/ObservationLib.sol";

contract BaseTest is Test {
  Utils internal utils;

  address payable[] internal users;
  address internal owner;
  address internal dev;
  address internal alice;
  address internal bob;
  address internal charlie;
  address internal dave;

  function setUp() public virtual {
    utils = new Utils();
    users = utils.createUsers(6);
    owner = users[0];
    dev = users[1];
    alice = users[2];
    bob = users[3];
    charlie = users[4];
    dave = users[5];
    vm.label(owner, "Owner");
    vm.label(dev, "Developer");
    vm.label(alice, "Alice");
    vm.label(bob, "Bob");
    vm.label(charlie, "Charlie");
    vm.label(dave, "Dave");
  }
}
