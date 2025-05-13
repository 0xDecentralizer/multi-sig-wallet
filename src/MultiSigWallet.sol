// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BytesUtils} from "./BytesUtils.sol";

/// @title MultiSigWallet
/// @notice A multi-signature wallet contract that requires multiple confirmations for transactions
/// @dev Implements a multi-signature wallet with configurable number of required confirmations
contract MultiSigWallet {
    using BytesUtils for bytes;

    // ============ Errors ============
    error MSW_NotOwner();
    error MSW_OldOwnerInvalid();
    error MSW_TxDoesNotExist();
    error MSW_TxAlreadyExecuted();
    error MSW_TxAlreadySigned();
    error MSW_TxNotSigned();
    error MSW_NotEnoughConfirmations();
    error MSW_InsufficientBalance();
    error MSW_TransactionFailed();
    error MSW_DuplicateOwner();
    error MSW_InvalidOwnerAddress();
    error MSW_EmptyOwnersList();
    error MSW_ConfirmationsExceedOwnersCount();
    error MSW_InvalidRequireConfirmations();
    error MSW_InvalidFunctionSelector();
    error MSW_TransactionExpired();

    // ============ Events ============
    event TransactionSubmitted(
        address indexed owner, 
        uint256 indexed txIndex, 
        address indexed to, 
        uint256 value, 
        bytes data,
        uint256 expiration
    );
    event TransactionConfirmed(address indexed owner, uint256 indexed txIndex);
    event ConfirmationRevoked(address indexed owner, uint256 indexed txIndex);
    event TransactionExecuted(address indexed owner, uint256 indexed txIndex);
    event Deposited(address indexed sender, uint256 value);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event RequireConfirmationsChanged(uint8 indexed oldReqConf, uint8 indexed newReqConf);

    // ============ Structs ============
    struct Transaction {
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
    constructor(address[] memory _owners, uint8 _requiredConfirmations) {
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

    // ============ External Functions ============
    /// @notice Submit a new transaction to be executed
    /// @param _to The address to send the transaction to
    /// @param _value The amount of ETH to send
    /// @param _data The transaction data
    function submitTransaction(
        address _to, 
        uint256 _value, 
        bytes memory _data,
        uint256 _expiration
    ) external onlyOwner {
        Transaction memory newTransaction = Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            numConfirmations: 0,
            expiration: block.timestamp + _expiration // test it
        });
        transactions.push(newTransaction);

        emit TransactionSubmitted(msg.sender, transactions.length - 1, _to, _value, _data, _expiration);
    }

    /// @notice Confirm a transaction
    /// @param _txIndex The index of the transaction to confirm
    function confirmTransaction(uint256 _txIndex) external onlyOwner {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();
        if (transactions[_txIndex].executed) revert MSW_TxAlreadyExecuted();
        if (isConfirmed[msg.sender][_txIndex]) revert MSW_TxAlreadySigned();
        if (block.timestamp > transactions[_txIndex].expiration) revert MSW_TransactionExpired(); // need to test this

        transactions[_txIndex].numConfirmations += 1;
        isConfirmed[msg.sender][_txIndex] = true;

        emit TransactionConfirmed(msg.sender, _txIndex);
    }

    /// @notice Revoke a transaction confirmation
    /// @param _txIndex The index of the transaction to revoke confirmation for
    function revokeConfirmation(uint256 _txIndex) external onlyOwner {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();
        if (transactions[_txIndex].executed) revert MSW_TxAlreadyExecuted();
        if (!isConfirmed[msg.sender][_txIndex]) revert MSW_TxNotSigned();
        if (block.timestamp > transactions[_txIndex].expiration) revert MSW_TransactionExpired(); // need to test this

        transactions[_txIndex].numConfirmations -= 1;
        isConfirmed[msg.sender][_txIndex] = false;

        emit ConfirmationRevoked(msg.sender, _txIndex);
    }

    /// @notice Execute a confirmed transaction
    /// @param _txIndex The index of the transaction to execute
    function executeTransaction(uint256 _txIndex) external onlyOwner {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();
        if (block.timestamp > transactions[_txIndex].expiration) revert MSW_TransactionExpired(); // need to test this

        Transaction storage transaction = transactions[_txIndex];

        if (transaction.executed) revert MSW_TxAlreadyExecuted();
        if (transaction.numConfirmations < requiredConfirmations) revert MSW_NotEnoughConfirmations();

        bytes memory txData = transaction.data;

        bytes4 selector;
        assembly {
            selector := mload(add(txData, 32))
        }

        if (selector == this.submitAddOwner.selector)
            _executeAddOwner(txData, transaction);
        else if (selector == this.submitRemoveOwner.selector)
            _executeRemoveOwner(txData, transaction);    
        else if (selector == this.changeRequiredConfirmations.selector)
            _executeChangeRequiredConfirmations(txData);
        else
            _executeTransaction(txData, _txIndex, transaction);
    }

    /// @notice Submit a transaction to add a new owner
    /// @param _newOwner The address of the new owner to add
    function submitAddOwner(address _newOwner, uint256 _expiration) external onlyOwner {
        if (_newOwner == address(0)) revert MSW_InvalidOwnerAddress();
        if (isOwner[_newOwner]) revert MSW_DuplicateOwner();

        bytes memory data = abi.encodeWithSelector(this.submitAddOwner.selector, _newOwner);

        transactions.push(Transaction({
            to: address(this),
            value: 0,
            data: data,
            executed: false,
            numConfirmations: 0,
            expiration: block.timestamp + _expiration // need to test this
        }));

        emit TransactionSubmitted(msg.sender, transactions.length - 1, address(this), 0, data, _expiration);
    }

    /// @notice Submit a transaction to remove an owner
    /// @param _ownerToRemove The address of the owner to remove
    function submitRemoveOwner(address _ownerToRemove, uint256 _expiration) external onlyOwner {
        if (!isOwner[_ownerToRemove]) revert MSW_OldOwnerInvalid();
        if (owners.length - 1 < requiredConfirmations) revert MSW_ConfirmationsExceedOwnersCount();

        bytes memory data = abi.encodeWithSelector(this.submitRemoveOwner.selector, _ownerToRemove);

        transactions.push(Transaction({
            to: address(this),
            value: 0,
            data: data,
            executed: false,
            numConfirmations: 0,
            expiration: block.timestamp + _expiration // need to test this
        }));

        emit TransactionSubmitted(msg.sender, transactions.length - 1, address(this), 0, data, _expiration);
    }

    /// @notice Submit a transaction to change the required number of confirmations
    /// @param _newRequiredConfirmations The new number of required confirmations
    function changeRequiredConfirmations(uint8 _newRequiredConfirmations, uint256 _expiration) external onlyOwner {
        if (_newRequiredConfirmations > owners.length) revert MSW_ConfirmationsExceedOwnersCount();
        if (_newRequiredConfirmations < 1) revert MSW_InvalidRequireConfirmations();
        if (_newRequiredConfirmations == requiredConfirmations) revert MSW_InvalidRequireConfirmations();

        bytes memory data = abi.encodeWithSelector(
            this.changeRequiredConfirmations.selector, 
            _newRequiredConfirmations
        );

        transactions.push(Transaction({
            to: address(this),
            value: 0,
            data: data,
            executed: false,
            numConfirmations: 0,
            expiration: block.timestamp + _expiration // need to test this
        }));

        emit TransactionSubmitted(msg.sender, transactions.length - 1, address(this), 0, data, _expiration);
    }

    // ============ Internal Functions ============
    function _executeAddOwner(bytes memory txData, Transaction storage transaction) internal {
        address newOwner = abi.decode(txData.sliceBytes(4), (address));

        isOwner[newOwner] = true;
        owners.push(newOwner);

        transaction.executed = true;
        emit OwnerAdded(newOwner);
    }

    function _executeRemoveOwner(bytes memory txData, Transaction storage transaction) internal {
        address oldOwner = abi.decode(txData.sliceBytes(4), (address));

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

    function _executeChangeRequiredConfirmations(
        bytes memory txData
    ) internal {
        uint8 oldReqConf = requiredConfirmations;
        uint8 newReqConf = abi.decode(txData.sliceBytes(4), (uint8));

        requiredConfirmations = newReqConf;
        
        emit RequireConfirmationsChanged(oldReqConf, newReqConf);
    }

    function _executeTransaction(
        bytes memory txData, 
        uint256 _txIndex, 
        Transaction storage transaction
    ) internal {
        if (transaction.value > address(this).balance) revert MSW_InsufficientBalance();
        
        transaction.executed = true;

        (bool success,) = transaction.to.call{value: transaction.value}(txData);
        if (!success) revert MSW_TransactionFailed();

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
}