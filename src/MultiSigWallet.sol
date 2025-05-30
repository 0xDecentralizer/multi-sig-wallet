// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MultiSigWalletErrors.sol";
import "./MultiSigWalletEvents.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";


/// @title MultiSigWallet
/// @notice A multi-signature wallet contract that requires multiple confirmations for transactions
/// @dev Implements a multi-signature wallet with configurable number of required confirmations
contract MultiSigWallet is Initializable, ReentrancyGuardUpgradeable {
    using Bytes for bytes;

    // ============ Constants ============
    uint256 public constant MAX_TRANSACTION_DATA_SIZE = 1024 * 1024; // 1MB
    address constant NATIVE_TOKEN = address(0x0); // Represents native token (ETH) 

    // ============ Structs ============
    struct Transaction {
        address token; // test
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint8 numConfirmations;
        uint256 expiration;
    }

    // ============ State Variables ============
    address[] private owners;
    uint8 public requiredConfirmations;
    mapping(address => bool) public isOwner;
    mapping(address => mapping(uint256 => bool)) public isConfirmed;
    Transaction[] public transactions;

    // ============ Modifiers ============
    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert MSW_NotOwner();
        _;
    }

    // ============ Constructor ============
    function initialize(address[] memory _owners, uint8 _requiredConfirmations) public initializer {
        __ReentrancyGuard_init();
        if (_owners.length == 0) revert MSW_EmptyOwnersList();
        if (_owners.length < _requiredConfirmations) revert MSW_ConfirmationsExceedOwnersCount();

        for (uint256 i = 0; i < _owners.length;) {
            address owner = _owners[i];
            if (owner == address(0)) revert MSW_InvalidOwnerAddress();
            if (isOwner[owner]) revert MSW_DuplicateOwner();

            isOwner[owner] = true;
            owners.push(owner);

            unchecked {
                i++;
            }
        }
        requiredConfirmations = _requiredConfirmations;
    }

    constructor() {
        _disableInitializers();
    }

    // ============ External Functions ============
    /// @notice Submit a new transaction to be executed
    /// @param _to The address to send the transaction to
    /// @param _value The amount of ETH to send
    /// @param _data The transaction data
    function submitTransaction(
        address _token, // test
        address _to,
        uint256 _value,
        bytes memory _data,
        uint256 _expiration
    ) external onlyOwner {
        if (_data.length > MAX_TRANSACTION_DATA_SIZE) revert MSW_TransactionDataTooLarge();
        if (_to == address(0)) revert MSW_InvalidRecipientAddress();
        Transaction memory newTransaction = Transaction({
            token: _token, // test
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            numConfirmations: 0,
            expiration: block.timestamp + _expiration
        });
        transactions.push(newTransaction);

        emit TransactionSubmitted(_token, msg.sender, transactions.length - 1, _to, _value, _data, _expiration);
    }

    /// @notice Confirm a transaction
    /// @param _txIndex The index of the transaction to confirm
    function confirmTransaction(uint256 _txIndex) external onlyOwner {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();
        
        Transaction storage transaction = transactions[_txIndex];
        if (block.timestamp > transaction.expiration) revert MSW_TransactionExpired();
        if (transaction.executed) revert MSW_TxAlreadyExecuted();
        if (isConfirmed[msg.sender][_txIndex]) revert MSW_TxAlreadySigned();

        transaction.numConfirmations += 1;
        isConfirmed[msg.sender][_txIndex] = true;

        emit TransactionConfirmed(msg.sender, _txIndex);
    }

    /// @notice Revoke a transaction confirmation
    /// @param _txIndex The index of the transaction to revoke confirmation for
    function revokeConfirmation(uint256 _txIndex) external onlyOwner {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();

        Transaction storage transaction = transactions[_txIndex];
        if (block.timestamp > transaction.expiration) revert MSW_TransactionExpired();
        if (transaction.executed) revert MSW_TxAlreadyExecuted();
        if (!isConfirmed[msg.sender][_txIndex]) revert MSW_TxNotSigned();

        transaction.numConfirmations -= 1;
        isConfirmed[msg.sender][_txIndex] = false;

        emit ConfirmationRevoked(msg.sender, _txIndex);
    }

    /// @notice Execute a confirmed transaction
    /// @param _txIndex The index of the transaction to execute
    function executeTransaction(uint256 _txIndex) external onlyOwner nonReentrant {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();
        
        Transaction storage transaction = transactions[_txIndex];
        if (block.timestamp > transaction.expiration) revert MSW_TransactionExpired();
        if (transaction.executed) revert MSW_TxAlreadyExecuted();
        if (transaction.numConfirmations < requiredConfirmations) revert MSW_NotEnoughConfirmations();

        bytes memory txData = transaction.data;

        bytes4 selector;
        assembly {
            selector := mload(add(txData, 32))
        }

        if (selector == this.submitAddOwner.selector) {
            _executeAddOwner(txData, transaction);
        } else if (selector == this.submitRemoveOwner.selector) {
            _executeRemoveOwner(txData, transaction);
        } else if (selector == this.changeRequiredConfirmations.selector) {
            _executeChangeRequiredConfirmations(txData, transaction);
        } else {
            _executeTransaction(txData, _txIndex, transaction);
        }
    }

    /// @notice Submit a transaction to add a new owner
    /// @param _newOwner The address of the new owner to add
    function submitAddOwner(address _newOwner, uint256 _expiration) external onlyOwner {
        if (_newOwner == address(0)) revert MSW_InvalidOwnerAddress();
        if (isOwner[_newOwner]) revert MSW_DuplicateOwner();

        bytes memory data = abi.encodeWithSelector(this.submitAddOwner.selector, _newOwner);

        transactions.push(
            Transaction({
                token: address(0x0),
                to: address(this),
                value: 0,
                data: data,
                executed: false,
                numConfirmations: 0,
                expiration: block.timestamp + _expiration
            })
        );

        emit TransactionSubmitted(
            address(0x0), msg.sender, transactions.length - 1, address(this), 0, data, _expiration
        );
    }

    /// @notice Submit a transaction to remove an owner
    /// @param _ownerToRemove The address of the owner to remove
    function submitRemoveOwner(address _ownerToRemove, uint256 _expiration) external onlyOwner {
        if (!isOwner[_ownerToRemove]) revert MSW_OldOwnerInvalid();
        if (owners.length - 1 < requiredConfirmations) revert MSW_ConfirmationsExceedOwnersCount();

        bytes memory data = abi.encodeWithSelector(this.submitRemoveOwner.selector, _ownerToRemove);

        transactions.push(
            Transaction({
                token: address(0x0),
                to: address(this),
                value: 0,
                data: data,
                executed: false,
                numConfirmations: 0,
                expiration: block.timestamp + _expiration
            })
        );

        emit TransactionSubmitted(
            address(0x0), msg.sender, transactions.length - 1, address(this), 0, data, _expiration
        );
    }

    /// @notice Submit a transaction to change the required number of confirmations
    /// @param _newRequiredConfirmations The new number of required confirmations
    function changeRequiredConfirmations(uint8 _newRequiredConfirmations, uint256 _expiration) external onlyOwner {
        if (_newRequiredConfirmations > owners.length) revert MSW_ConfirmationsExceedOwnersCount();
        if (_newRequiredConfirmations < 1) revert MSW_InvalidRequireConfirmations();
        if (_newRequiredConfirmations == requiredConfirmations) revert MSW_InvalidRequireConfirmations();

        bytes memory data = abi.encodeWithSelector(this.changeRequiredConfirmations.selector, _newRequiredConfirmations);

        transactions.push(
            Transaction({
                token: address(0x0),
                to: address(this),
                value: 0,
                data: data,
                executed: false,
                numConfirmations: 0,
                expiration: block.timestamp + _expiration
            })
        );

        emit TransactionSubmitted(
            address(0x0), msg.sender, transactions.length - 1, address(this), 0, data, _expiration
        );
    }

    // ============ Internal Functions ============
    function _executeAddOwner(bytes memory txData, Transaction storage transaction) internal {
        address newOwner = abi.decode(txData.slice(4), (address));

        isOwner[newOwner] = true;
        owners.push(newOwner);

        transaction.executed = true;
        emit OwnerAdded(newOwner);
    }

    function _executeRemoveOwner(bytes memory txData, Transaction storage transaction) internal {
        address oldOwner = abi.decode(txData.slice(4), (address));

        isOwner[oldOwner] = false;

        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == oldOwner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }

        transaction.executed = true;
        emit OwnerRemoved(oldOwner);
    }

    function _executeChangeRequiredConfirmations(bytes memory txData, Transaction storage transaction) internal {
        uint8 oldReqConf = requiredConfirmations;
        uint8 newReqConf = abi.decode(txData.slice(4), (uint8));
        
        transaction.executed = true;
        requiredConfirmations = newReqConf;

        emit RequireConfirmationsChanged(oldReqConf, newReqConf);
    }

    function _executeTransaction(bytes memory txData, uint256 _txIndex, Transaction storage transaction) internal {
        transaction.executed = true;

        if (transaction.token == NATIVE_TOKEN) {
            if (transaction.value > address(this).balance) revert MSW_InsufficientBalance();
            (bool success,) = transaction.to.call{value: transaction.value}(txData);
            if (!success) revert MSW_TransactionFailed();
        } else {
            if (transaction.value > IERC20(transaction.token).balanceOf(address(this))) {
                revert MSW_InsufficientBalance();
            }
            (bool success, bytes memory data) = transaction.token.call(
                abi.encodeWithSelector(IERC20.transfer.selector, transaction.to, transaction.value)
            );
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert MSW_TransactionFailed();
        }
        emit TransactionExecuted(msg.sender, _txIndex);
    }

    // ============ View Functions ============
    /// @notice Get the number of owners
    /// @return The number of owners
    function getOwnerCount() public view returns (uint256) {
        return owners.length;
    }

    /// @notice Get all owners
    /// @return Array of owner addresses
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    /// @notice Get transaction details
    /// @param _txIndex The index of the transaction
    /// @return The transaction details
    function getTransaction(uint256 _txIndex) public view returns (Transaction memory) {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();
        return transactions[_txIndex];
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    uint256[100] private __gap; // gap for future upgrades
}
