// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { TwabLib } from "./libraries/TwabLib.sol";
import { ObservationLib } from "./libraries/ObservationLib.sol";
import { ExtendedSafeCastLib } from "./libraries/ExtendedSafeCastLib.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

contract TwabController {
  using ExtendedSafeCastLib for uint256;

  /* ============ State ============ */

  /// @notice Record of token holders TWABs for each account for each vault
  mapping(address => mapping(address => TwabLib.Account)) internal userTwabs;

  /// @notice Record of tickets total supply and ring buff parameters used for observation.
  mapping(address => TwabLib.Account) internal totalSupplyTwab;

  // vault => user => delegate
  mapping(address => mapping(address => address)) internal delegates;

  /* ============ Events ============ */

  event NewUserTwab(
    address indexed vault,
    address indexed delegate,
    ObservationLib.Observation newTwab
  );

  event Delegated(address indexed vault, address indexed delegator, address indexed delegate);

  event NewTotalSupplyTwab(address indexed vault, ObservationLib.Observation newTotalSupplyTwab);

  /* ============ External Functions ============ */

  function getAccountDetails(
    address vault,
    address _user
  ) external returns (TwabLib.AccountDetails memory) {
    return userTwabs[vault][_user].details;
  }

  function balanceOf(address vault, address user) external returns (uint256) {
    return userTwabs[vault][user].details.balance;
  }

  function getBalanceAt(address vault, address _user, uint64 _target) external returns (uint256) {
    TwabLib.Account storage account = userTwabs[vault][_user];

    return
      TwabLib.getBalanceAt(
        account.twabs,
        account.details,
        uint32(_target),
        uint32(block.timestamp)
      );
  }

  function getAverageBalancesBetween(
    address vault,
    address _user,
    uint64[] calldata _startTimes,
    uint64[] calldata _endTimes
  ) external returns (uint256[] memory) {
    return _getAverageBalancesBetween(userTwabs[vault][_user], _startTimes, _endTimes);
  }

  function getAverageTotalSuppliesBetween(
    address vault,
    uint64[] calldata _startTimes,
    uint64[] calldata _endTimes
  ) external returns (uint256[] memory) {
    return _getAverageBalancesBetween(totalSupplyTwab[vault], _startTimes, _endTimes);
  }

  function getAverageBalanceBetween(
    address vault,
    address _user,
    uint64 _startTime,
    uint64 _endTime
  ) external returns (uint256) {
    TwabLib.Account storage account = userTwabs[vault][_user];

    return
      TwabLib.getAverageBalanceBetween(
        account.twabs,
        account.details,
        uint32(_startTime),
        uint32(_endTime),
        uint32(block.timestamp)
      );
  }

  function getBalancesAt(
    address vault,
    address _user,
    uint64[] calldata _targets
  ) external returns (uint256[] memory) {
    uint256 length = _targets.length;
    uint256[] memory _balances = new uint256[](length);

    TwabLib.Account storage twabContext = userTwabs[vault][_user];
    TwabLib.AccountDetails memory details = twabContext.details;

    for (uint256 i = 0; i < length; i++) {
      _balances[i] = TwabLib.getBalanceAt(
        twabContext.twabs,
        details,
        uint32(_targets[i]),
        uint32(block.timestamp)
      );
    }

    return _balances;
  }

  function getTotalSupplyAt(address vault, uint64 _target) external returns (uint256) {
    return
      TwabLib.getBalanceAt(
        totalSupplyTwab[vault].twabs,
        totalSupplyTwab[vault].details,
        uint32(_target),
        uint32(block.timestamp)
      );
  }

  function getTotalSuppliesAt(
    address vault,
    uint64[] calldata _targets
  ) external returns (uint256[] memory) {
    uint256 length = _targets.length;
    uint256[] memory totalSupplies = new uint256[](length);

    TwabLib.AccountDetails memory details = totalSupplyTwab[vault].details;

    for (uint256 i = 0; i < length; i++) {
      totalSupplies[i] = TwabLib.getBalanceAt(
        totalSupplyTwab[vault].twabs,
        details,
        uint32(_targets[i]),
        uint32(block.timestamp)
      );
    }

    return totalSupplies;
  }

  function totalSupply(address vault) external returns (uint256) {
    return totalSupplyTwab[vault].details.balance;
  }

  function mint(address vault, address _to, uint256 _amount) external {
    _transfer(vault, address(0), _to, _amount);
  }

  function burn(address vault, address _from, uint256 _amount) external {
    _transfer(vault, _from, address(0), _amount);
  }

  function twabTransfer(address vault, address _from, address _to, uint256 _amount) external {
    _transfer(vault, _from, _to, _amount);
  }

  function _transfer(address vault, address _from, address _to, uint256 _amount) internal {
    if (_from == _to) {
      return;
    }

    // Minting
    address _fromDelegate;
    if (_from != address(0)) {
      _fromDelegate = delegates[vault][_from];
    }

    // Burning
    address _toDelegate;
    if (_to != address(0)) {
      _toDelegate = delegates[vault][_to];
    }

    _transferTwab(vault, _fromDelegate, _toDelegate, _amount);
  }

  function delegateOf(address vault, address _user) external returns (address) {
    return delegates[vault][_user];
  }

  function delegateBalanceOf(address vault, address user) external returns (uint256) {
    return userTwabs[vault][user].details.delegateBalance;
  }

  function delegate(address vault, address _from, address _to) external {
    _delegate(vault, _from, _to);
  }

  /* ============ Internal Functions ============ */

  function _getAverageBalancesBetween(
    TwabLib.Account storage _account,
    uint64[] calldata _startTimes,
    uint64[] calldata _endTimes
  ) internal returns (uint256[] memory) {
    uint256 startTimesLength = _startTimes.length;
    require(startTimesLength == _endTimes.length, "Ticket/start-end-times-length-match");

    TwabLib.AccountDetails memory accountDetails = _account.details;

    uint256[] memory averageBalances = new uint256[](startTimesLength);
    uint32 currentTimestamp = uint32(block.timestamp);

    for (uint256 i = 0; i < startTimesLength; i++) {
      averageBalances[i] = TwabLib.getAverageBalanceBetween(
        _account.twabs,
        accountDetails,
        uint32(_startTimes[i]),
        uint32(_endTimes[i]),
        currentTimestamp
      );
    }

    return averageBalances;
  }

  function _delegate(address vault, address _from, address _to) internal {
    uint256 balance = userTwabs[vault][_from].details.balance;
    address currentDelegate = delegates[vault][_from];

    if (currentDelegate == _to) {
      return;
    }

    delegates[vault][_from] = _to;

    _transferTwab(vault, currentDelegate, _to, balance);

    emit Delegated(vault, _from, _to);
  }

  function _transferTwab(address vault, address _from, address _to, uint256 _amount) internal {
    /// @param _amount The balance that is being transferred.
    // If we are transferring tokens from a delegated account to an undelegated account
    if (_from != address(0)) {
      _decreaseUserTwab(vault, _from, _amount);

      // burn
      if (_to == address(0)) {
        _decreaseTotalSupplyTwab(vault, _amount);
      }
    }

    // If we are transferring tokens from an undelegated account to a delegated account
    if (_to != address(0)) {
      _increaseUserTwab(vault, _to, _amount);

      // mint
      if (_from == address(0)) {
        _increaseTotalSupplyTwab(vault, _amount);
      }
    }
  }

  function _increaseUserTwab(address vault, address _to, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    TwabLib.Account storage _account = userTwabs[vault][_to];

    (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    ) = TwabLib.increaseBalance(_account, uint112(_amount), uint32(block.timestamp));

    _account.details = accountDetails;

    if (isNew) {
      emit NewUserTwab(vault, _to, twab);
    }
  }

  function _decreaseUserTwab(address vault, address _to, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    TwabLib.Account storage _account = userTwabs[vault][_to];

    (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    ) = TwabLib.decreaseBalance(
        _account,
        uint112(_amount),
        "Ticket/twab-burn-lt-balance",
        uint32(block.timestamp)
      );

    _account.details = accountDetails;

    if (isNew) {
      emit NewUserTwab(vault, _to, twab);
    }
  }

  function _decreaseTotalSupplyTwab(address vault, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory tsTwab,
      bool tsIsNew
    ) = TwabLib.decreaseBalance(
        totalSupplyTwab[vault],
        uint112(_amount),
        "Ticket/burn-amount-exceeds-total-supply-twab",
        uint32(block.timestamp)
      );

    totalSupplyTwab[vault].details = accountDetails;

    if (tsIsNew) {
      emit NewTotalSupplyTwab(vault, tsTwab);
    }
  }

  /// @notice Increases the total supply twab.  Should be called anytime a balance moves from undelegated to delegated
  /// @param _amount The amount to increase the total by
  function _increaseTotalSupplyTwab(address vault, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    (
      TwabLib.AccountDetails memory accountDetails,
      ObservationLib.Observation memory _totalSupply,
      bool tsIsNew
    ) = TwabLib.increaseBalance(totalSupplyTwab[vault], uint112(_amount), uint32(block.timestamp));

    totalSupplyTwab[vault].details = accountDetails;

    if (tsIsNew) {
      emit NewTotalSupplyTwab(vault, _totalSupply);
    }
  }
}
