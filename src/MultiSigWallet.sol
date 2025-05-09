// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BytesUtils} from "./BytesUtils.sol";

contract MultiSigWallet {
    address[] private owners;
    uint8 public immutable requireConfirmations;

    using BytesUtils for bytes;

    mapping(address => bool) public isOwner;
    mapping(address => mapping(uint256 => bool)) public isConfirmed;

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
    error MSW_InvalidFunctionSelector();

    event TransactionSubmited(
        address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data
    );
    event TransactionConfirmed(address indexed owner, uint256 indexed txIndex);
    event ConfirmationRevoked(address indexed owner, uint256 indexed txIndex);
    event TransactionExecuted(address indexed owner, uint256 indexed txIndex);
    event Deposited(address indexed sender, uint256 value);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event RequirementChanged(uint8 required);

    constructor(address[] memory _owners, uint8 _requireConfirmations) {
        if (_owners.length == 0) revert MSW_EmptyOwnersList();
        if (_owners.length < _requireConfirmations) revert MSW_ConfirmationsExceedOwnersCount();

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
        requireConfirmations = _requireConfirmations;
    }

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert MSW_NotOwner();
        _;
    }

    // modifier notExecuted(uint256 _txIndex) {
    //     if(transactions[_txIndex].executed) revert MSW_TxAlreadyExecuted();
    //     _;
    // }

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint8 numConfirmations;
    }

    Transaction[] public transactions;

    function numOwners() public view returns (uint256) {
        return owners.length;
    }

    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function setTransaction(address _to, uint256 _value, bytes memory _data) external onlyOwner {
        Transaction memory newTransaction =
            Transaction({to: _to, value: _value, data: _data, executed: false, numConfirmations: 0});
        transactions.push(newTransaction);

        emit TransactionSubmited(msg.sender, transactions.length - 1, _to, _value, _data);
    }

    function signTransaction(uint256 _txIndex) external onlyOwner {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();
        if (transactions[_txIndex].executed) revert MSW_TxAlreadyExecuted();
        if (isConfirmed[msg.sender][_txIndex]) revert MSW_TxAlreadySigned();

        transactions[_txIndex].numConfirmations += 1;
        isConfirmed[msg.sender][_txIndex] = true;

        emit TransactionConfirmed(msg.sender, _txIndex);
    }

    function unsignTransaction(uint256 _txIndex) external onlyOwner {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();
        if (transactions[_txIndex].executed) revert MSW_TxAlreadyExecuted();
        if (!isConfirmed[msg.sender][_txIndex]) revert MSW_TxNotSigned();

        transactions[_txIndex].numConfirmations -= 1;
        isConfirmed[msg.sender][_txIndex] = false;

        emit ConfirmationRevoked(msg.sender, _txIndex);
    }

    function executeTransaction(uint256 _txIndex) public onlyOwner {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();

        Transaction storage transaction = transactions[_txIndex];

        if (transaction.executed) revert MSW_TxAlreadyExecuted();
        if (transaction.numConfirmations < requireConfirmations) revert MSW_NotEnoughConfirmations();

        bytes memory txData = transaction.data;

        bytes4 selector;
        assembly {
            selector := mload(add(txData, 32))
        }

        if (selector == this.submitAddOwner.selector) {
            address newOwner = abi.decode(txData.sliceBytes(4), (address));

            isOwner[newOwner] = true;
            owners.push(newOwner);

            transaction.executed = true;
            emit OwnerAdded(newOwner);
        } else if (selector == this.submitRemoveOwner.selector) {
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
        } else {
            transaction.executed = true;

            if (transaction.value > address(this).balance) revert MSW_InsufficientBalance();

            (bool success,) = transaction.to.call{value: transaction.value}(txData);
            if (!success) revert MSW_TransactionFailed();

            emit TransactionExecuted(msg.sender, _txIndex);
        }
    }

    function submitAddOwner(address _owner) external onlyOwner {
        if (_owner == address(0)) revert MSW_InvalidOwnerAddress();
        if (isOwner[_owner]) revert MSW_DuplicateOwner();

        bytes memory data = abi.encodeWithSelector(this.submitAddOwner.selector, _owner);

        transactions.push(Transaction({to: address(this), value: 0, data: data, executed: false, numConfirmations: 0}));

        emit TransactionSubmited(msg.sender, transactions.length - 1, address(this), 0, data);
    }

    function submitRemoveOwner(address _owner) external onlyOwner {
        if (!isOwner[_owner]) revert MSW_OldOwnerInvalid();
        if (owners.length - 1 < requireConfirmations) revert MSW_ConfirmationsExceedOwnersCount();

        bytes memory data = abi.encodeWithSelector(this.submitRemoveOwner.selector, _owner);

        transactions.push(Transaction({to: address(this), value: 0, data: data, executed: false, numConfirmations: 0}));

        emit TransactionSubmited(msg.sender, transactions.length - 1, address(this), 0, data);
    }
}
