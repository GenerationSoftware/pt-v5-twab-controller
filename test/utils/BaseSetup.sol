// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { Utils } from "./Utils.sol";

contract BaseSetup is Test {
  Utils internal utils;

  address payable[] internal users;
  address internal owner;
  address internal dev;
  address internal alice;
  address internal bob;

  function setUp() public virtual {
    utils = new Utils();
    users = utils.createUsers(4);
    owner = users[0];
    dev = users[1];
    alice = users[2];
    bob = users[3];
    vm.label(owner, "Owner");
    vm.label(dev, "Developer");
    vm.label(alice, "Alice");
    vm.label(bob, "Bob");
  }
}
