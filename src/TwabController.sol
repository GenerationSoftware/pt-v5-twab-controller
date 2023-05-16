// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

import { TwabLib } from "./libraries/TwabLib.sol";
import { ObservationLib } from "./libraries/ObservationLib.sol";

/**
 * @title  PoolTogether V5 TwabController
 * @author PoolTogether Inc Team
 * @dev    Time-Weighted Average Balance Controller for ERC20 tokens.
 * @notice This TwabController uses the TwabLib to provide token balances and on-chain historical
            lookups to a user(s) time-weighted average balance. Each user is mapped to an
            Account struct containing the TWAB history (ring buffer) and ring buffer parameters.
            Every token.transfer() creates a new TWAB observation. The new TWAB observation is
            stored in the circular ring buffer, as either a new observation or rewriting a
            previous observation with new parameters. One observation per day is stored.
            The TwabLib guarantees minimum 1 year of search history.
 */
contract TwabController {
  /// @notice Allows users to revoke their chances to win by delegating to the sponsorship address.
  address public constant SPONSORSHIP_ADDRESS = address(1);

  /* ============ State ============ */

  /// @notice Record of token holders TWABs for each account for each vault
  mapping(address => mapping(address => TwabLib.Account)) internal userObservations;

  /// @notice Record of tickets total supply and ring buff parameters used for observation.
  mapping(address => TwabLib.Account) internal totalSupplyObservation;

  /// @notice vault => user => delegate
  mapping(address => mapping(address => address)) internal delegates;

  /* ============ Events ============ */

  /**
   * @notice Emitted when a balance or delegateBalance is increased.
   * @param vault the vault for which the balance increased
   * @param user the users who's balance increased
   * @param amount the amount the balance increased by
   * @param delegateAmount the amount the delegateBalance increased by
   */
  event IncreasedBalance(
    address indexed vault,
    address indexed user,
    uint96 amount,
    uint96 delegateAmount
  );

  /**
   * @notice Emited when a balance or delegateBalance is decreased.
   * @param vault the vault for which the balance decreased
   * @param user the users who's balance decreased
   * @param amount the amount the balance decreased by
   * @param delegateAmount the amount the delegateBalance decreased by
   */
  event DecreasedBalance(
    address indexed vault,
    address indexed user,
    uint96 amount,
    uint96 delegateAmount
  );

  /**
   * @notice Emited when an Observation is recorded to the Ring Buffer.
   * @param vault the vault for which the balance decreased
   * @param user the users who's balance decreased
   * @param amount the amount the balance decreased by
   * @param delegateAmount the amount the delegateBalance decreased by
   * @param isNew whether the observation observation is new or not
   * @param observation the observation that was created or updated
   */
  event ObservationRecorded(
    address indexed vault,
    address indexed user,
    uint96 amount,
    uint96 delegateAmount,
    bool isNew,
    ObservationLib.Observation observation
  );

  /**
   * @notice Emitted when a user delegates their balance to another address.
   * @param vault the vault for which the balance was delegated
   * @param delegator the user who delegated their balance
   * @param delegate the user who received the delegated balance
   */
  event Delegated(address indexed vault, address indexed delegator, address indexed delegate);

  /**
   * @notice Emitted when the total supply or delegateTotalSupply is increased.
   * @param vault the vault for which the total supply increased
   * @param amount the amount the total supply increased by
   * @param delegateAmount the amount the delegateTotalSupply increased by
   */
  event IncreasedTotalSupply(address indexed vault, uint96 amount, uint96 delegateAmount);

  /**
   * @notice Emitted when the total supply or delegateTotalSupply is decreased.
   * @param vault the vault for which the total supply decreased
   * @param amount the amount the total supply decreased by
   * @param delegateAmount the amount the delegateTotalSupply decreased by
   */
  event DecreasedTotalSupply(address indexed vault, uint96 amount, uint96 delegateAmount);

  /**
   * @notice Emited when an Observation is recorded to the Ring Buffer.
   * @param vault the vault for which the balance decreased
   * @param amount the amount the balance decreased by
   * @param delegateAmount the amount the delegateBalance decreased by
   * @param isNew whether the observation observation is new or not
   * @param observation the observation that was created or updated
   */
  event TotalSupplyObservationRecorded(
    address indexed vault,
    uint96 amount,
    uint96 delegateAmount,
    bool isNew,
    ObservationLib.Observation observation
  );

  /* ============ External Read Functions ============ */

  /**
   * @notice Loads the current TWAB Account data for a specific vault stored for a user
   * @dev Note this is a very expensive function
   * @param vault the vault for which the data is being queried
   * @param user the user who's data is being queried
   * @return The current TWAB Account data of the user
   */
  function getAccount(address vault, address user) external view returns (TwabLib.Account memory) {
    return userObservations[vault][user];
  }

  /**
   * @notice The current token balance of a user for a specific vault
   * @param vault the vault for which the balance is being queried
   * @param user the user who's balance is being queried
   * @return The current token balance of the user
   */
  function balanceOf(address vault, address user) external view returns (uint256) {
    return userObservations[vault][user].details.balance;
  }

  /**
   * @notice The total supply of tokens for a vault
   * @param vault the vault for which the total supply is being queried
   * @return The total supply of tokens for a vault
   */
  function totalSupply(address vault) external view returns (uint256) {
    return totalSupplyObservation[vault].details.balance;
  }

  /**
   * @notice The total delegated amount of tokens for a vault.
   * @dev Delegated balance is not 1:1 with the token total supply. Users may delegate their
   *      balance to the sponsorship address, which will result in those tokens being subtracted
   *      from the total.
   * @param vault the vault for which the total delegated supply is being queried
   * @return The total delegated amount of tokens for a vault
   */
  function totalSupplyDelegateBalance(address vault) external view returns (uint256) {
    return totalSupplyObservation[vault].details.delegateBalance;
  }

  /**
   * @notice The current delegate of a user for a specific vault
   * @param vault the vault for which the delegate balance is being queried
   * @param user the user who's delegate balance is being queried
   * @return The current delegate balance of the user
   */
  function delegateOf(address vault, address user) external view returns (address) {
    return _delegateOf(vault, user);
  }

  /**
   * @notice The current delegateBalance of a user for a specific vault
   * @dev the delegateBalance is the sum of delegated balance to this user
   * @param vault the vault for which the delegateBalance is being queried
   * @param user the user who's delegateBalance is being queried
   * @return The current delegateBalance of the user
   */
  function delegateBalanceOf(address vault, address user) external view returns (uint256) {
    return userObservations[vault][user].details.delegateBalance;
  }

  /**
   * @notice Looks up a users balance at a specific time in the past
   * @param vault the vault for which the balance is being queried
   * @param user the user who's balance is being queried
   * @param targetTime the time in the past for which the balance is being queried
   * @return The balance of the user at the target time
   */
  function getBalanceAt(
    address vault,
    address user,
    uint32 targetTime
  ) external view returns (uint256) {
    TwabLib.Account storage _account = userObservations[vault][user];
    return TwabLib.getBalanceAt(_account.observations, _account.details, targetTime);
  }

  /**
   * @notice Looks up the total supply at a specific time in the past
   * @param vault the vault for which the total supply is being queried
   * @param targetTime the time in the past for which the total supply is being queried
   * @return The total supply at the target time
   */
  function getTotalSupplyAt(address vault, uint32 targetTime) external view returns (uint256) {
    TwabLib.Account storage _account = totalSupplyObservation[vault];
    return TwabLib.getBalanceAt(_account.observations, _account.details, targetTime);
  }

  /**
   * @notice Looks up the average balance of a user between two timestamps
   * @dev Timestamps are Unix timestamps denominated in seconds
   * @param vault the vault for which the average balance is being queried
   * @param user the user who's average balance is being queried
   * @param startTime the start of the time range for which the average balance is being queried
   * @param endTime the end of the time range for which the average balance is being queried
   * @return The average balance of the user between the two timestamps
   */
  function getTwabBetween(
    address vault,
    address user,
    uint32 startTime,
    uint32 endTime
  ) external view returns (uint256) {
    TwabLib.Account storage _account = userObservations[vault][user];
    return TwabLib.getTwabBetween(_account.observations, _account.details, startTime, endTime);
  }

  /**
   * @notice Looks up the average total supply between two timestamps
   * @dev Timestamps are Unix timestamps denominated in seconds
   * @param vault the vault for which the average total supply is being queried
   * @param startTime the start of the time range for which the average total supply is being queried
   * @param endTime the end of the time range for which the average total supply is being queried
   * @return The average total supply between the two timestamps
   */
  function getTotalSupplyTwabBetween(
    address vault,
    uint32 startTime,
    uint32 endTime
  ) external view returns (uint256) {
    TwabLib.Account storage _account = totalSupplyObservation[vault];
    return TwabLib.getTwabBetween(_account.observations, _account.details, startTime, endTime);
  }

  /**
   * @notice Looks up the newest observation observation for a user
   * @param vault the vault for which the observation is being queried
   * @param user the user who's observation is being queried
   * @return index The index of the observation observation
   * @return observation The observation observation of the user
   */
  function getNewestObservation(
    address vault,
    address user
  ) external view returns (uint16, ObservationLib.Observation memory) {
    TwabLib.Account storage _account = userObservations[vault][user];
    return TwabLib.getNewestObservation(_account.observations, _account.details);
  }

  /**
   * @notice Looks up the oldest observation observation for a user
   * @param vault the vault for which the observation is being queried
   * @param user the user who's observation is being queried
   * @return index The index of the observation observation
   * @return observation The observation observation of the user
   */
  function getOldestObservation(
    address vault,
    address user
  ) external view returns (uint16, ObservationLib.Observation memory) {
    TwabLib.Account storage _account = userObservations[vault][user];
    return TwabLib.getOldestObservation(_account.observations, _account.details);
  }

  /* ============ External Write Functions ============ */

  /**
   * @notice Mints new balance and delegateBalance for a given user
   * @dev Note that if the provided user to mint to is delegating that the delegate's
   *      delegateBalance will be updated.
   * @param _to The address to mint balance and delegateBalance to
   * @param _amount The amount to mint
   */
  function mint(address _to, uint96 _amount) external {
    _transferBalance(msg.sender, address(0), _to, _amount);
  }

  /**
   * @notice Burns balance and delegateBalance for a given user
   * @dev Note that if the provided user to burn from is delegating that the delegate's
   *      delegateBalance will be updated.
   * @param _from The address to burn balance and delegateBalance from
   * @param _amount The amount to burn
   */
  function burn(address _from, uint96 _amount) external {
    _transferBalance(msg.sender, _from, address(0), _amount);
  }

  /**
   * @notice Transfers balance and delegateBalance from a given user
   * @dev Note that if the provided user to transfer from is delegating that the delegate's
   *      delegateBalance will be updated.
   * @param _from The address to transfer the balance and delegateBalance from
   * @param _to The address to transfer balance and delegateBalance to
   * @param _amount The amount to transfer
   */
  function transfer(address _from, address _to, uint96 _amount) external {
    _transferBalance(msg.sender, _from, _to, _amount);
  }

  /**
   * @notice Sets a delegate for a user which forwards the delegateBalance tied to the user's
   *          balance to the delegate's delegateBalance.
   * @param _vault The vault for which the delegate is being set
   * @param _to the address to delegate to
   */
  function delegate(address _vault, address _to) external {
    _delegate(_vault, msg.sender, _to);
  }

  /**
   * @notice Delegate user balance to the sponsorship address.
   * @dev Must only be called by the Vault contract.
   * @param _from Address of the user delegating their balance to the sponsorship address.
   */
  function sponsor(address _from) external {
    _delegate(msg.sender, _from, SPONSORSHIP_ADDRESS);
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Transfers a user's vault balance from one address to another.
   * @dev If the user is delegating, their delegate's delegateBalance is also updated.
   * @dev If we are minting or burning tokens then the total supply is also updated.
   * @param _vault the vault for which the balance is being transferred
   * @param _from the address from which the balance is being transferred
   * @param _to the address to which the balance is being transferred
   * @param _amount the amount of balance being transferred
   */
  function _transferBalance(address _vault, address _from, address _to, uint96 _amount) internal {
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

  /**
   * @notice Looks up the delegate of a user.
   * @param _vault the vault for which the user's delegate is being queried
   * @param _user the address to query the delegate of
   * @return The address of the user's delegate
   */
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

  /**
   * @notice Transfers a user's vault delegateBalance from one address to another.
   * @param _vault the vault for which the delegateBalance is being transferred
   * @param _fromDelegate the address from which the delegateBalance is being transferred
   * @param _toDelegate the address to which the delegateBalance is being transferred
   * @param _amount the amount of delegateBalance being transferred
   */
  function _transferDelegateBalance(
    address _vault,
    address _fromDelegate,
    address _toDelegate,
    uint96 _amount
  ) internal {
    // If we are transferring tokens from a delegated account to an undelegated account
    if (_fromDelegate != address(0) && _fromDelegate != SPONSORSHIP_ADDRESS) {
      _decreaseBalances(_vault, _fromDelegate, 0, _amount);

      // burn
      if (_toDelegate == address(0) || _toDelegate == SPONSORSHIP_ADDRESS) {
        _decreaseTotalSupplyBalances(_vault, 0, _amount);
      }
    }

    // If we are transferring tokens from an undelegated account to a delegated account
    if (_toDelegate != address(0) && _toDelegate != SPONSORSHIP_ADDRESS) {
      _increaseBalances(_vault, _toDelegate, 0, _amount);

      // mint
      if (_fromDelegate == address(0) || _fromDelegate == SPONSORSHIP_ADDRESS) {
        _increaseTotalSupplyBalances(_vault, 0, _amount);
      }
    }
  }

  /**
   * @notice Sets a delegate for a user which forwards the delegateBalance tied to the user's
   *          balance to the delegate's delegateBalance.
   * @param _vault The vault for which the delegate is being set
   * @param _from the address to delegate from
   * @param _to the address to delegate to
   */
  function _delegate(address _vault, address _from, address _to) internal {
    address _currentDelegate = _delegateOf(_vault, _from);
    require(_to != _currentDelegate, "TC/delegate-already-set");

    delegates[_vault][_from] = _to;

    _transferDelegateBalance(
      _vault,
      _currentDelegate,
      _to,
      uint96(userObservations[_vault][_from].details.balance)
    );

    emit Delegated(_vault, _from, _to);
  }

  /**
   * @notice Increases a user's balance and delegateBalance for a specific vault.
   * @param _vault the vault for which the balance is being increased
   * @param _user the address of the user whose balance is being increased
   * @param _amount the amount of balance being increased
   * @param _delegateAmount the amount of delegateBalance being increased
   */
  function _increaseBalances(
    address _vault,
    address _user,
    uint96 _amount,
    uint96 _delegateAmount
  ) internal {
    TwabLib.Account storage _account = userObservations[_vault][_user];

    (
      ObservationLib.Observation memory _observation,
      bool _isNewObservation,
      bool _isObservationRecorded
    ) = TwabLib.increaseBalances(_account, _amount, _delegateAmount);

    // Always emit the balance change event
    emit IncreasedBalance(_vault, _user, _amount, _delegateAmount);

    // Conditionally emit the observation recorded event
    if (_isObservationRecorded) {
      emit ObservationRecorded(
        _vault,
        _user,
        _amount,
        _delegateAmount,
        _isNewObservation,
        _observation
      );
    }
  }

  /**
   * @notice Decreases the a user's balance and delegateBalance for a specific vault.
   * @param _vault the vault for which the totalSupply balance is being decreased
   * @param _amount the amount of balance being decreased
   * @param _delegateAmount the amount of delegateBalance being decreased
   */
  function _decreaseBalances(
    address _vault,
    address _user,
    uint96 _amount,
    uint96 _delegateAmount
  ) internal {
    TwabLib.Account storage _account = userObservations[_vault][_user];

    (
      ObservationLib.Observation memory _observation,
      bool _isNewObservation,
      bool _isObservationRecorded
    ) = TwabLib.decreaseBalances(
        _account,
        _amount,
        _delegateAmount,
        "TC/observation-burn-lt-delegate-balance"
      );

    // Always emit the balance change event
    emit DecreasedBalance(_vault, _user, _amount, _delegateAmount);

    // Conditionally emit the observation recorded event
    if (_isObservationRecorded) {
      emit ObservationRecorded(
        _vault,
        _user,
        _amount,
        _delegateAmount,
        _isNewObservation,
        _observation
      );
    }
  }

  /**
   * @notice Decreases the totalSupply balance and delegateBalance for a specific vault.
   * @param _vault the vault for which the totalSupply balance is being decreased
   * @param _amount the amount of balance being decreased
   * @param _delegateAmount the amount of delegateBalance being decreased
   */
  function _decreaseTotalSupplyBalances(
    address _vault,
    uint96 _amount,
    uint96 _delegateAmount
  ) internal {
    TwabLib.Account storage _account = totalSupplyObservation[_vault];

    (
      ObservationLib.Observation memory _observation,
      bool _isNewObservation,
      bool _isObservationRecorded
    ) = TwabLib.decreaseBalances(
        _account,
        _amount,
        _delegateAmount,
        "TC/burn-amount-exceeds-total-supply-balance"
      );

    // Always emit the balance change event
    emit DecreasedTotalSupply(_vault, _amount, _delegateAmount);

    // Conditionally emit the observation recorded event
    if (_isObservationRecorded) {
      emit TotalSupplyObservationRecorded(
        _vault,
        _amount,
        _delegateAmount,
        _isNewObservation,
        _observation
      );
    }
  }

  /**
   * @notice Increases the totalSupply balance and delegateBalance for a specific vault.
   * @param _vault the vault for which the totalSupply balance is being increased
   * @param _amount the amount of balance being increased
   * @param _delegateAmount the amount of delegateBalance being increased
   */
  function _increaseTotalSupplyBalances(
    address _vault,
    uint96 _amount,
    uint96 _delegateAmount
  ) internal {
    TwabLib.Account storage _account = totalSupplyObservation[_vault];

    (
      ObservationLib.Observation memory _observation,
      bool _isNewObservation,
      bool _isObservationRecorded
    ) = TwabLib.increaseBalances(_account, _amount, _delegateAmount);

    // Always emit the balance change event
    emit IncreasedTotalSupply(_vault, _amount, _delegateAmount);

    // Conditionally emit the observation recorded event
    if (_isObservationRecorded) {
      emit TotalSupplyObservationRecorded(
        _vault,
        _amount,
        _delegateAmount,
        _isNewObservation,
        _observation
      );
    }
  }
}
