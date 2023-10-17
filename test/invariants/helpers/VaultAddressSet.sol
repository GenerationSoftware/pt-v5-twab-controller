// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Thanks horsefacts.
// https://mirror.xyz/horsefacts.eth/Jex2YVaO65dda6zEyfM_-DXlXhOWCAoSpOx5PLocYgw
// https://github.com/horsefacts/weth-invariant-testing/blob/main/test/helpers/AddressSet.sol

struct VaultAddressSet {
  address[] vaults;
  mapping(address => bool) vaultSaved;
  mapping(address => address[]) actors;
  mapping(address => mapping(address => bool)) actorSaved;
}

library VaultAddressSetLib {
  function addVault(VaultAddressSet storage s, address vault) internal {
    if (!s.vaultSaved[vault]) {
      s.vaults.push(vault);
      s.vaultSaved[vault] = true;
    }
  }

  function addActor(VaultAddressSet storage s, address vault, address actor) internal {
    addVault(s, vault);
    if (!s.actorSaved[vault][actor]) {
      s.actors[vault].push(actor);
      s.actorSaved[vault][actor] = true;
    }
  }

  function removeActor(VaultAddressSet storage s, address vault, address actor) internal {
    if (s.actors[vault].length == 0) {
      return;
    }

    // If there's only one actor, pop
    if (s.actors[vault].length == 1) {
      s.actorSaved[vault][actor] = false;
      s.actors[vault].pop();

      // Potentially remove vault
      if (s.actors[vault].length == 0) {
        removeVault(s, vault);
      }
      return;
    }

    // Find the actor's index
    for (uint256 i = 0; i < s.actors[vault].length; ++i) {
      if (s.actors[vault][i] == actor) {
        // Copy the last actor to i and pop.
        if (i != s.actors[vault].length - 1) {
          s.actors[vault][i] = s.actors[vault][s.actors[vault].length - 1];
        }

        // Remove actor
        s.actorSaved[vault][actor] = false;
        s.actors[vault].pop();

        // Potentially remove vault
        if (s.actors[vault].length == 0) {
          removeVault(s, vault);
        }
        return;
      }
    }
  }

  function removeVault(VaultAddressSet storage s, address vault) internal {
    // If there's none, skip
    if (s.vaults.length == 0) {
      return;
    }

    // If there's 1, pop
    if (s.vaults.length == 1) {
      s.vaultSaved[vault] = false;
      s.vaults.pop();
      return;
    }

    // Find the vault's index
    for (uint256 i = 0; i < s.vaults.length; ++i) {
      if (s.vaults[i] == vault) {
        // Copy the last vault to i and pop.
        if (i != s.actors[vault].length - 1) {
          s.actors[vault][i] = s.actors[vault][s.actors[vault].length - 1];
        }

        // Remove vault
        s.vaultSaved[vault] = false;
        s.vaults.pop();
        return;
      }
    }
  }

  function containsVault(VaultAddressSet storage s, address vault) internal view returns (bool) {
    return s.vaultSaved[vault];
  }

  function containsActor(
    VaultAddressSet storage s,
    address vault,
    address actor
  ) internal view returns (bool) {
    return s.actorSaved[vault][actor];
  }

  function countVaults(VaultAddressSet storage s) internal view returns (uint256) {
    return s.vaults.length;
  }

  function countVaultActors(
    VaultAddressSet storage s,
    address vault
  ) internal view returns (uint256) {
    return s.actors[vault].length;
  }

  function randomVault(VaultAddressSet storage s, uint256 seed) internal view returns (address) {
    if (s.vaults.length > 0) {
      return s.vaults[seed % s.vaults.length];
    } else {
      return address(0);
    }
  }

  function randomVaultActor(
    VaultAddressSet storage s,
    address vault,
    uint256 seed
  ) internal view returns (address) {
    if (s.actors[vault].length > 0) {
      return s.actors[vault][seed % s.actors[vault].length];
    } else {
      return address(0);
    }
  }

  function forEachVault(VaultAddressSet storage s, function(address) external func) internal {
    for (uint256 i; i < s.vaults.length; ++i) {
      if (s.vaultSaved[s.vaults[i]]) {
        func(s.vaults[i]);
      }
    }
  }

  function forEachVaultActor(
    VaultAddressSet storage s,
    address vault,
    function(address, address) external func
  ) internal {
    for (uint256 i; i < s.actors[vault].length; ++i) {
      if (s.actorSaved[vault][s.actors[vault][i]]) {
        func(vault, s.actors[vault][i]);
      }
    }
  }

  function forEachVaultActorPair(
    VaultAddressSet storage s,
    function(address, address) external func
  ) internal {
    for (uint256 i; i < s.vaults.length; ++i) {
      for (uint256 j; j < s.actors[s.vaults[i]].length; ++i) {
        if (s.actorSaved[s.vaults[i]][s.actors[s.vaults[i]][j]]) {
          func(s.vaults[i], s.actors[s.vaults[i]][j]);
        }
      }
    }
  }

  function reduceVaults(
    VaultAddressSet storage s,
    uint256 acc,
    function(uint256, address) external returns (uint256) func
  ) internal returns (uint256) {
    for (uint256 i; i < s.vaults.length; ++i) {
      if (s.vaultSaved[s.vaults[i]]) {
        acc = func(acc, s.vaults[i]);
      }
    }
    return acc;
  }

  function reduceVaultActors(
    VaultAddressSet storage s,
    uint256 acc,
    address vault,
    function(uint256, address, address) external returns (uint256) func
  ) internal returns (uint256) {
    for (uint256 i; i < s.actors[vault].length; ++i) {
      if (s.actorSaved[vault][s.actors[vault][i]]) {
        acc = func(acc, vault, s.actors[vault][i]);
      }
    }
    return acc;
  }

  function reduceVaultActorPairs(
    VaultAddressSet storage s,
    uint256 acc,
    function(uint256, address, address) external returns (uint256) func
  ) internal returns (uint256) {
    for (uint256 i = 0; i < s.vaults.length; ++i) {
      for (uint256 j = 0; j < s.actors[s.vaults[i]].length; ++j) {
        if (s.actorSaved[s.vaults[i]][s.actors[s.vaults[i]][j]]) {
          acc = func(acc, s.vaults[i], s.actors[s.vaults[i]][j]);
        }
      }
    }
    return acc;
  }
}
