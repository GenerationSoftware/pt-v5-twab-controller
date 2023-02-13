// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { TwabLib, Account, AccountDetails } from "./libraries/TwabLib.sol";
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

  /**
   * @notice Allows users to revoke their chances to win by delegating to the
              sponsorship address.
   * @dev    The user Account.AccountDetails.cardinality parameter can NOT exceed the max 
              cardinality variable. Preventing "corrupted" ring buffer lookup pointers and new 
              observation checkpoints. 
              The MAX_CARDINALITY in fact guarantees at least 1 year of records.
   */
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
    address indexed delegate,
    ObservationLib.Observation newTwab
  );

  event Delegated(address indexed vault, address indexed delegator, address indexed delegate);

  event NewTotalSupplyTwab(address indexed vault, ObservationLib.Observation newTotalSupplyTwab);

  /* ============ External Read Functions ============ */

  function balanceOf(address vault, address user) external view returns (uint256) {
    return userTwabs[vault][user].details.balance;
  }

  function totalSupply(address vault) external view returns (uint256) {
    return totalSupplyTwab[vault].details.balance;
  }

  function totalSupplyDelegateBalance(address vault) external view returns (uint256) {
    return totalSupplyTwab[vault].details.delegateBalance;
  }

  function delegateOf(address vault, address _user) external view returns (address) {
    return delegates[vault][_user];
  }

  function delegateBalanceOf(address vault, address user) external view returns (uint256) {
    return userTwabs[vault][user].details.delegateBalance;
  }

  function getAccount(address vault, address _user) external view returns (Account memory) {
    return userTwabs[vault][_user];
  }

  function getAccountDetails(
    address vault,
    address _user
  ) external view returns (AccountDetails memory) {
    return userTwabs[vault][_user].details;
  }

  function getBalanceAt(
    address vault,
    address _user,
    uint64 _target
  ) external view returns (uint256) {
    Account storage account = userTwabs[vault][_user];

    return
      TwabLib.getBalanceAt(
        account.twabs,
        account.details,
        uint32(_target),
        uint32(block.timestamp)
      );
  }

  function getTotalSupplyAt(address vault, uint64 _target) external view returns (uint256) {
    return
      TwabLib.getBalanceAt(
        totalSupplyTwab[vault].twabs,
        totalSupplyTwab[vault].details,
        uint32(_target),
        uint32(block.timestamp)
      );
  }

  function getAverageBalanceBetween(
    address vault,
    address _user,
    uint64 _startTime,
    uint64 _endTime
  ) external view returns (uint256) {
    Account storage account = userTwabs[vault][_user];

    return
      TwabLib.getAverageBalanceBetween(
        account.twabs,
        account.details,
        uint32(_startTime),
        uint32(_endTime),
        uint32(block.timestamp)
      );
  }

  function getAverageTotalSupplyBetween(
    address vault,
    uint64 _startTime,
    uint64 _endTime
  ) external view returns (uint256) {
    return
      TwabLib.getAverageBalanceBetween(
        totalSupplyTwab[vault].twabs,
        totalSupplyTwab[vault].details,
        uint32(_startTime),
        uint32(_endTime),
        uint32(block.timestamp)
      );
  }

  function getNewestTwab(
    address vault,
    address _user
  ) external view returns (uint16 index, ObservationLib.Observation memory twab) {
    return TwabLib.newestTwab(userTwabs[vault][_user].twabs, userTwabs[vault][_user].details);
  }

  function getOldestTwab(
    address vault,
    address _user
  ) external view returns (uint16 index, ObservationLib.Observation memory twab) {
    return TwabLib.oldestTwab(userTwabs[vault][_user].twabs, userTwabs[vault][_user].details);
  }

  /* ============ External Write Functions ============ */

  // Updates the users (or delegates) delegateBalance
  // Updates the users token balance
  function twabMint(address _to, uint256 _amount) external {
    // TODO: Should handle updating balance and delegateBalance inside Twablib
    // NOTE: Balance first so it's picked up in the delegateBalance update
    _mintBalance(msg.sender, _to, _amount);
    _mintDelegateBalance(msg.sender, _to, _amount);
  }

  // Updates the users (or delegates) delegateBalance
  // Updates the users token balance
  function twabBurn(address _from, uint256 _amount) external {
    // TODO: Should handle updating balance and delegateBalance inside Twablib
    // NOTE: Balance first so it's picked up in the delegateBalance update
    _burnBalance(msg.sender, _from, _amount);
    _burnDelegateBalance(msg.sender, _from, _amount);
  }

  // Updates the users (or delegates) delegateBalance
  // Updates the users token balance
  function twabTransfer(address _from, address _to, uint256 _amount) external {
    // NOTE: Balance first so it's picked up in the delegateBalance update
    _transferBalance(msg.sender, _from, _to, _amount);
    _transferDelegateBalanceRouter(msg.sender, _from, _to, _amount);
  }

  function delegate(address vault, address _from, address _to) external {
    _delegate(vault, _from, _to);
  }

  /* ============ Internal Functions ============ */

  function _transferBalance(address vault, address _from, address _to, uint256 _amount) internal {
    if (_from == _to) {
      return;
    }

    /// @param _amount The balance that is being transferred.
    // If we are transferring tokens from a delegated account to an undelegated account
    if (_from != address(0)) {
      _decreaseUserBalance(vault, _from, _amount);

      // burn
      if (_to == address(0)) {
        _decreaseTotalSupplyBalance(vault, _amount);
      }
    }

    // If we are transferring tokens from an undelegated account to a delegated account
    if (_to != address(0)) {
      _increaseUserBalance(vault, _to, _amount);

      // mint
      if (_from == address(0)) {
        _increaseTotalSupplyBalance(vault, _amount);
      }
    }
  }

  function _transferDelegateBalanceRouter(
    address vault,
    address _from,
    address _to,
    uint256 _amount
  ) internal {
    if (_from == _to) {
      return;
    }

    address _fromDelegate;
    if (_from != address(0)) {
      _fromDelegate = delegates[vault][_from];
      // If the user has not delegated, then the user is the delegate
      if (_fromDelegate == address(0)) {
        _fromDelegate = _from;
      }
    }

    address _toDelegate;
    if (_to != address(0)) {
      _toDelegate = delegates[vault][_to];
      // If the user has not delegated, then the user is the delegate
      if (_toDelegate == address(0)) {
        _toDelegate = _to;
      }
    }

    _transferDelegateBalance(vault, _fromDelegate, _toDelegate, _amount);
  }

  function _transferDelegateBalance(
    address vault,
    address _from,
    address _to,
    uint256 _amount
  ) internal {
    // If we are transferring tokens from a delegated account to an undelegated account
    if (_from != address(0)) {
      _decreaseUserDelegateBalance(vault, _from, _amount);

      // burn
      if (_to == address(0) || _to == SPONSORSHIP_ADDRESS) {
        _decreaseTotalSupplyDelegateBalance(vault, _amount);
      }
    }

    // If we are transferring tokens from an undelegated account to a delegated account
    if (_to != address(0)) {
      _increaseUserDelegateBalance(vault, _to, _amount);

      // mint
      if (_from == address(0) || _from == SPONSORSHIP_ADDRESS) {
        _increaseTotalSupplyDelegateBalance(vault, _amount);
      }
    }
  }

  function _mintBalance(address vault, address _to, uint256 _amount) internal {
    _transferBalance(vault, address(0), _to, _amount);
  }

  function _mintDelegateBalance(address vault, address _to, uint256 _amount) internal {
    _transferDelegateBalanceRouter(vault, address(0), _to, _amount);
  }

  function _burnBalance(address vault, address _from, uint256 _amount) internal {
    _transferBalance(vault, _from, address(0), _amount);
  }

  function _burnDelegateBalance(address vault, address _from, uint256 _amount) internal {
    _transferDelegateBalanceRouter(vault, _from, address(0), _amount);
  }

  function _delegate(address vault, address _from, address _to) internal {
    uint256 balance = userTwabs[vault][_from].details.balance;
    address currentDelegate = delegates[vault][_from];

    if (currentDelegate == _to) {
      return;
    }

    delegates[vault][_from] = _to;

    if (currentDelegate == address(0)) {
      currentDelegate = _from;
      if (currentDelegate == _to) {
        return;
      }
    }

    _transferDelegateBalance(vault, currentDelegate, _to, balance);

    emit Delegated(vault, _from, _to);
  }

  function _increaseUserDelegateBalance(address vault, address _to, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    Account storage _account = userTwabs[vault][_to];

    (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    ) = TwabLib.increaseDelegateBalance(_account, uint112(_amount), uint32(block.timestamp));

    _account.details = accountDetails;

    if (isNew) {
      emit NewUserTwab(vault, _to, twab);
    }
  }

  function _decreaseUserDelegateBalance(address vault, address _to, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    Account storage _account = userTwabs[vault][_to];

    (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory twab,
      bool isNew
    ) = TwabLib.decreaseDelegateBalance(
        _account,
        uint112(_amount),
        "TwabController/twab-burn-lt-delegate-balance",
        uint32(block.timestamp)
      );

    _account.details = accountDetails;

    if (isNew) {
      emit NewUserTwab(vault, _to, twab);
    }
  }

  function _increaseTotalSupplyDelegateBalance(address vault, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory _totalSupply,
      bool tsIsNew
    ) = TwabLib.increaseDelegateBalance(
        totalSupplyTwab[vault],
        uint112(_amount),
        uint32(block.timestamp)
      );

    totalSupplyTwab[vault].details = accountDetails;

    if (tsIsNew) {
      emit NewTotalSupplyTwab(vault, _totalSupply);
    }
  }

  function _decreaseTotalSupplyDelegateBalance(address vault, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    (
      AccountDetails memory accountDetails,
      ObservationLib.Observation memory tsTwab,
      bool tsIsNew
    ) = TwabLib.decreaseDelegateBalance(
        totalSupplyTwab[vault],
        uint112(_amount),
        "TwabController/burn-amount-exceeds-total-supply-twab",
        uint32(block.timestamp)
      );

    totalSupplyTwab[vault].details = accountDetails;

    if (tsIsNew) {
      emit NewTotalSupplyTwab(vault, tsTwab);
    }
  }

  function _increaseUserBalance(address vault, address _to, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }
    Account storage _account = userTwabs[vault][_to];
    AccountDetails memory accountDetails = TwabLib.increaseBalance(_account, uint112(_amount));
    _account.details = accountDetails;
  }

  function _decreaseUserBalance(address vault, address _to, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    Account storage _account = userTwabs[vault][_to];

    AccountDetails memory accountDetails = TwabLib.decreaseBalance(
      _account,
      uint112(_amount),
      "TwabController/twab-burn-lt-balance"
    );

    _account.details = accountDetails;
  }

  function _increaseTotalSupplyBalance(address vault, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    AccountDetails memory accountDetails = TwabLib.increaseBalance(
      totalSupplyTwab[vault],
      uint112(_amount)
    );
    totalSupplyTwab[vault].details = accountDetails;
  }

  function _decreaseTotalSupplyBalance(address vault, uint256 _amount) internal {
    if (_amount == 0) {
      return;
    }

    AccountDetails memory accountDetails = TwabLib.decreaseBalance(
      totalSupplyTwab[vault],
      uint112(_amount),
      "TwabController/burn-amount-exceeds-total-supply-balance"
    );
    totalSupplyTwab[vault].details = accountDetails;
  }
}
