// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { TwabLib, Account } from "./libraries/TwabLib.sol";
import { ObservationLib } from "./libraries/ObservationLib.sol";
import { ExtendedSafeCastLib } from "./libraries/ExtendedSafeCastLib.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title  PoolTogether V5 TwabController
 * @author PoolTogether Inc Team
 * @dev    Time-Weighted Average Balance Controller for ERC20 tokens.
 * @notice This TwabController uses the TwabLib to provide token balances and on-chain historical
              lookups to a user(s) time-weighted average balance. Each user is mapped to an
              Account struct containing the TWAB history (ring buffer) and ring buffer parameters.
              Every token.transfer() creates a new TWAB checkpoint. The new TWAB checkpoint is
              stored in the circular ring buffer, as either a new checkpoint or rewriting a
              previous checkpoint with new parameters. One checkpoint per day is stored.
              The TwabLib guarantees minimum 1 year of search history.
 */
contract TwabController {
  using ExtendedSafeCastLib for uint256;

  /// @notice Allows users to revoke their chances to win by delegating to the sponsorship address.
  address public constant SPONSORSHIP_ADDRESS = address(1);

  /* ============ State ============ */

  /// @notice Record of token holders TWABs for each account for each vault
  mapping(address => mapping(address => Account)) internal userTwabs;

  /// @notice Record of tickets total supply and ring buff parameters used for observation.
  mapping(address => Account) internal totalSupplyTwab;

  // vault => user => delegate
  mapping(address => mapping(address => address)) internal delegates;

  /* ============ Events ============ */

  event NewUserTwab(
    address indexed vault,
    address indexed account,
    ObservationLib.Observation newTwab
  );

  event Delegated(address indexed vault, address indexed delegator, address indexed delegate);

  event NewTotalSupplyTwab(address indexed vault, ObservationLib.Observation newTotalSupplyTwab);

  /* ============ External Read Functions ============ */

  function balanceOf(address vault, address user) external view returns (uint256) {
    return userTwabs[vault][user].balance;
  }

  function totalSupply(address vault) external view returns (uint256) {
    return totalSupplyTwab[vault].balance;
  }

  function totalSupplyDelegateBalance(address vault) external view returns (uint256) {
    return totalSupplyTwab[vault].delegateBalance;
  }

  function delegateOf(address _vault, address _user) external view returns (address) {
    return _delegateOf(_vault, _user);
  }

  function delegateBalanceOf(address vault, address user) external view returns (uint256) {
    return userTwabs[vault][user].delegateBalance;
  }

  function getAccount(address vault, address _user) external view returns (Account memory) {
    return userTwabs[vault][_user];
  }

  function getBalanceAt(
    address _vault,
    address _user,
    uint32 _target
  ) external view returns (uint256) {
    return TwabLib.getBalanceAt(userTwabs[_vault][_user], _target);
  }

  function getTotalSupplyAt(address vault, uint32 _target) external view returns (uint256) {
    return TwabLib.getBalanceAt(totalSupplyTwab[vault], _target);
  }

  function getAverageBalanceBetween(
    address _vault,
    address _user,
    uint32 _startTime,
    uint32 _endTime
  ) external view returns (uint256) {
    return TwabLib.getAverageBalanceBetween(userTwabs[_vault][_user], _startTime, _endTime);
  }

  function getAverageTotalSupplyBetween(
    address _vault,
    uint32 _startTime,
    uint32 _endTime
  ) external view returns (uint256) {
    return TwabLib.getAverageBalanceBetween(totalSupplyTwab[_vault], _startTime, _endTime);
  }

  function getNewestTwab(
    address _vault,
    address _user
  ) external view returns (uint16 index, ObservationLib.Observation memory twab) {
    return TwabLib.newestTwab(userTwabs[_vault][_user]);
  }

  function getOldestTwab(
    address _vault,
    address _user
  ) external view returns (uint16 index, ObservationLib.Observation memory twab) {
    return TwabLib.oldestTwab(userTwabs[_vault][_user]);
  }

  /* ============ External Write Functions ============ */

  // Updates the users (or delegates) delegateBalance
  // Updates the users token balance
  function twabMint(address _to, uint112 _amount) external {
    _transferBalance(msg.sender, address(0), _to, _amount);
  }

  // Updates the users (or delegates) delegateBalance
  // Updates the users token balance
  function twabBurn(address _from, uint112 _amount) external {
    _transferBalance(msg.sender, _from, address(0), _amount);
  }

  // Updates the users (or delegates) delegateBalance
  // Updates the users token balance
  function twabTransfer(address _from, address _to, uint112 _amount) external {
    _transferBalance(msg.sender, _from, _to, _amount);
  }

  function delegate(address _vault, address _to) external {
    _delegate(_vault, msg.sender, _to);
  }

  /* ============ Internal Functions ============ */

  function _transferBalance(address _vault, address _from, address _to, uint112 _amount) internal {
    if (_from == _to) {
      return;
    }

    // If we are transferring tokens from a delegated account to an undelegated account
    if (_from != address(0)) {
      address _fromDelegate = _delegateOf(_vault, _from);
      bool _isFromDelegate = _fromDelegate == _from;

      _decreaseBalances(_vault, _from, _amount, _isFromDelegate ? _amount : 0);

      if (!_isFromDelegate) {
        _decreaseBalances(
          _vault,
          _fromDelegate,
          0,
          _fromDelegate != SPONSORSHIP_ADDRESS ? _amount : 0
        );
      }

      // burn
      if (_to == address(0)) {
        _decreaseTotalSupplyBalances(
          _vault,
          _amount,
          _fromDelegate != SPONSORSHIP_ADDRESS ? _amount : 0
        );
      }
    }

    // If we are transferring tokens from an undelegated account to a delegated account
    if (_to != address(0)) {
      address _toDelegate = _delegateOf(_vault, _to);
      bool _isToDelegate = _toDelegate == _to;

      _increaseBalances(_vault, _to, _amount, _isToDelegate ? _amount : 0);

      if (!_isToDelegate) {
        _increaseBalances(_vault, _toDelegate, 0, _toDelegate != SPONSORSHIP_ADDRESS ? _amount : 0);
      }

      // mint
      if (_from == address(0)) {
        _increaseTotalSupplyBalances(
          _vault,
          _amount,
          _toDelegate != SPONSORSHIP_ADDRESS ? _amount : 0
        );
      }
    }
  }

  function _delegateOf(address _vault, address _user) internal view returns (address) {
    address _userDelegate;

    if (_user != address(0)) {
      _userDelegate = delegates[_vault][_user];

      // If the user has not delegated, then the user is the delegate
      if (_userDelegate == address(0)) {
        _userDelegate = _user;
      }
    }

    return _userDelegate;
  }

  function _transferDelegateBalance(
    address _vault,
    address _fromDelegate,
    address _toDelegate,
    uint112 _amount
  ) internal {
    // If we are transferring tokens from a delegated account to an undelegated account
    if (_fromDelegate != address(0)) {
      _decreaseBalances(_vault, _fromDelegate, 0, _amount);

      // burn
      if (_toDelegate == address(0) || _toDelegate == SPONSORSHIP_ADDRESS) {
        _decreaseTotalSupplyBalances(_vault, 0, _amount);
      }
    }

    // If we are transferring tokens from an undelegated account to a delegated account
    if (_toDelegate != address(0)) {
      _increaseBalances(_vault, _toDelegate, 0, _amount);

      // mint
      if (_fromDelegate == address(0) || _fromDelegate == SPONSORSHIP_ADDRESS) {
        _increaseTotalSupplyBalances(_vault, 0, _amount);
      }
    }
  }

  function _delegate(address _vault, address _from, address _toDelegate) internal {
    address _currentDelegate = _delegateOf(_vault, _from);
    require(_toDelegate != _currentDelegate, "TC/delegate-already-set");

    delegates[_vault][_from] = _toDelegate;

    _transferDelegateBalance(
      _vault,
      _currentDelegate,
      _toDelegate,
      userTwabs[_vault][_from].balance
    );

    emit Delegated(_vault, _from, _toDelegate);
  }

  function _increaseBalances(
    address _vault,
    address _account,
    uint112 _amount,
    uint112 _delegateAmount
  ) internal {
    (ObservationLib.Observation memory _twab, bool _isNewTwab) = TwabLib.increaseBalances(
      userTwabs[_vault][_account],
      _amount,
      _delegateAmount
    );

    if (_isNewTwab) {
      emit NewUserTwab(_vault, _account, _twab);
    }
  }

  function _decreaseBalances(
    address _vault,
    address _account,
    uint112 _amount,
    uint112 _delegateAmount
  ) internal {
    (ObservationLib.Observation memory _twab, bool _isNewTwab) = TwabLib.decreaseBalances(
      userTwabs[_vault][_account],
      _amount,
      _delegateAmount,
      "TC/twab-burn-lt-delegate-balance"
    );

    if (_isNewTwab) {
      emit NewUserTwab(_vault, _account, _twab);
    }
  }

  function _decreaseTotalSupplyBalances(
    address _vault,
    uint112 _amount,
    uint112 _delegateAmount
  ) internal {
    (ObservationLib.Observation memory _totalSupply, bool _tsIsNewTwab) = TwabLib.decreaseBalances(
      totalSupplyTwab[_vault],
      _amount,
      _delegateAmount,
      "TC/burn-amount-exceeds-total-supply-balance"
    );

    if (_tsIsNewTwab) {
      emit NewTotalSupplyTwab(_vault, _totalSupply);
    }
  }

  function _increaseTotalSupplyBalances(
    address _vault,
    uint112 _amount,
    uint112 _delegateAmount
  ) internal {
    (ObservationLib.Observation memory _totalSupply, bool _tsIsNewTwab) = TwabLib.increaseBalances(
      totalSupplyTwab[_vault],
      _amount,
      _delegateAmount
    );

    if (_tsIsNewTwab) {
      emit NewTotalSupplyTwab(_vault, _totalSupply);
    }
  }
}
