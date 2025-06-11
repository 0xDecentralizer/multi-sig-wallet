// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MultiSigWalletErrors.sol";
import "./MultiSigWalletEvents.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";

/// @title MultiSigWallet
/// @notice A multi-signature wallet contract that requires multiple confirmations for transactions
/// @dev Implements a multi-signature wallet with configurable number of required confirmations
/// @custom:security-contact security@example.com
contract MultiSigWallet is Initializable, ReentrancyGuardUpgradeable {
    using Bytes for bytes;

    // ============ Constants ============
    /// @notice Maximum size of transaction data in bytes (1MB)
    uint256 public constant MAX_TRANSACTION_DATA_SIZE = 1024 * 1024;
    /// @notice Address representing native token (ETH)
    address constant NATIVE_TOKEN = address(0x0);
    /// @notice Time lock period for transactions (currently unused)
    uint256 constant TIME_LOCK = 1 days;
    /// @notice Maximum number of transactions that can be confirmed in a single call
    uint256 constant MAX_MULTI_CONFIRM = 3;

    // ============ Structs ============
    /// @notice Structure representing a transaction in the wallet
    /// @param token Address of the token to transfer (NATIVE_TOKEN for ETH)
    /// @param to Recipient address
    /// @param value Amount to transfer
    /// @param data Transaction data (empty for simple transfers)
    /// @param executed Whether the transaction has been executed
    /// @param numConfirmations Number of confirmations received
    /// @param expiration Timestamp when the transaction expires
    struct Transaction {
        address token;
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint8 numConfirmations;
        uint256 expiration;
    }

    // ============ State Variables ============
    /// @notice List of wallet owners
    address[] private owners;
    /// @notice Number of required confirmations for transaction execution
    uint8 public requiredConfirmations;
    /// @notice Mapping of addresses to their owner status
    mapping(address => bool) public isOwner;
    /// @notice Mapping of owner address to transaction index to confirmation status
    mapping(address => mapping(uint256 => bool)) public isConfirmed;
    /// @notice Array of all transactions
    Transaction[] public transactions;

    // ============ Modifiers ============
    /// @notice Restricts function access to wallet owners only
    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert MSW_NotOwner();
        _;
    }

    // ============ Constructor ============
    /// @notice Initializes the multi-signature wallet
    /// @param _owners Array of initial owner addresses
    /// @param _requiredConfirmations Number of required confirmations for transactions
    /// @dev This function can only be called once during contract deployment
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

    /// @notice Disables the initializer to prevent multiple initializations
    constructor() {
        _disableInitializers();
    }

    // ============ External Functions ============
    /// @notice Submit a new transaction to be executed
    /// @param _token Address of the token to transfer (NATIVE_TOKEN for ETH)
    /// @param _to Recipient address
    /// @param _value Amount to transfer
    /// @param _data Transaction data (empty for simple transfers)
    /// @param _expiration Time in seconds until transaction expires
    /// @dev Only owners can submit transactions
    function submitTransaction(address _token, address _to, uint256 _value, bytes memory _data, uint256 _expiration)
        external
        onlyOwner
    {
        if (_data.length > MAX_TRANSACTION_DATA_SIZE) revert MSW_TransactionDataTooLarge();
        if (_to == address(0)) revert MSW_InvalidRecipientAddress();
        Transaction memory newTransaction = Transaction({
            token: _token,
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
    /// @param _txIndex Index of the transaction to confirm
    /// @dev Only owners can confirm transactions
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

    /// @notice Confirm multiple transactions in a single call
    /// @param _txIndices Array of transaction indices to confirm
    /// @dev Only owners can confirm transactions, limited to MAX_MULTI_CONFIRM transactions per call
    function confirmMultipleTransactions(uint256[] memory _txIndices) external onlyOwner {
        if (_txIndices.length > MAX_MULTI_CONFIRM) revert MSW_TooManyConfirmations();
        for (uint256 i = 0; i < _txIndices.length; i++) {
            uint256 txIndex = _txIndices[i];
            if (txIndex >= transactions.length) revert MSW_TxDoesNotExist();

            Transaction storage transaction = transactions[txIndex];
            if (block.timestamp > transaction.expiration) revert MSW_TransactionExpired();
            if (transaction.executed) revert MSW_TxAlreadyExecuted();
            if (isConfirmed[msg.sender][txIndex]) revert MSW_TxAlreadySigned();

            transaction.numConfirmations += 1;
            isConfirmed[msg.sender][txIndex] = true;
            emit TransactionConfirmed(msg.sender, txIndex);
        }
    }

    /// @notice Revoke a previously given confirmation
    /// @param _txIndex Index of the transaction to revoke confirmation for
    /// @dev Only owners can revoke their own confirmations
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
    /// @param _txIndex Index of the transaction to execute
    /// @dev Only owners can execute transactions that have enough confirmations
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
    /// @param _newOwner Address of the new owner to add
    /// @param _expiration Time in seconds until transaction expires
    /// @dev Only owners can submit add owner transactions
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
    /// @param _ownerToRemove Address of the owner to remove
    /// @param _expiration Time in seconds until transaction expires
    /// @dev Only owners can submit remove owner transactions
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
    /// @param _newRequiredConfirmations New number of required confirmations
    /// @param _expiration Time in seconds until transaction expires
    /// @dev Only owners can submit change required confirmations transactions
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
    /// @notice Internal function to execute add owner transaction
    /// @param txData Encoded transaction data
    /// @param transaction Transaction storage reference
    function _executeAddOwner(bytes memory txData, Transaction storage transaction) internal {
        address newOwner = abi.decode(txData.slice(4), (address));

        isOwner[newOwner] = true;
        owners.push(newOwner);

        transaction.executed = true;
        emit OwnerAdded(newOwner);
    }

    /// @notice Internal function to execute remove owner transaction
    /// @param txData Encoded transaction data
    /// @param transaction Transaction storage reference
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

    /// @notice Internal function to execute change required confirmations transaction
    /// @param txData Encoded transaction data
    /// @param transaction Transaction storage reference
    function _executeChangeRequiredConfirmations(bytes memory txData, Transaction storage transaction) internal {
        uint8 oldReqConf = requiredConfirmations;
        uint8 newReqConf = abi.decode(txData.slice(4), (uint8));

        transaction.executed = true;
        requiredConfirmations = newReqConf;

        emit RequireConfirmationsChanged(oldReqConf, newReqConf);
    }

    /// @notice Internal function to execute a regular transaction
    /// @param txData Transaction data
    /// @param _txIndex Transaction index
    /// @param transaction Transaction storage reference
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
    /// @notice Get the total number of owners
    /// @return Number of owners
    function getOwnerCount() public view returns (uint256) {
        return owners.length;
    }

    /// @notice Get all owner addresses
    /// @return Array of owner addresses
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    /// @notice Get transaction details by index
    /// @param _txIndex Index of the transaction
    /// @return Transaction details
    function getTransaction(uint256 _txIndex) public view returns (Transaction memory) {
        if (_txIndex >= transactions.length) revert MSW_TxDoesNotExist();
        return transactions[_txIndex];
    }

    /// @notice Function to receive ETH
    /// @dev This function is called when ETH is sent to the contract
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Storage gap for future upgrades
    uint256[100] private __gap;
}
