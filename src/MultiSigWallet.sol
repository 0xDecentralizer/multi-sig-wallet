// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract MultiSigWallet {
    address[] private owners;
    uint8 public immutable requireConfirmations;

    mapping(address => bool) public isOwner;
    mapping(address => mapping(uint256 => bool)) public isConfirmed;

    constructor(address[] memory _owners, uint8 _requireConfirmations) {
        require(_owners.length != 0, "Owners list can't be empty!");
        require(_owners.length >= _requireConfirmations, "Confirmations can't be greater than number of owners");

        for (uint256 i = 0; i < _owners.length;) {
            address owner = _owners[i];
            require(owner != address(0), "Owner can't be 0 address");
            require(!isOwner[owner], "Duplicate Owner not accepted");

            isOwner[owner] = true;
            owners.push(owner);

            unchecked {
                i++;
            }
        }
        requireConfirmations = _requireConfirmations;
    }

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not an owner!");
        _;
    }

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
    }

    function signTransaction(uint256 _txIndex) external onlyOwner {
        require(_txIndex < transactions.length, "There is no such TX!");
        require(!transactions[_txIndex].executed, "Executed Tx cannot be sign!");
        require(!isConfirmed[msg.sender][_txIndex], "You signed this TX before!");

        transactions[_txIndex].numConfirmations += 1;
        isConfirmed[msg.sender][_txIndex] = true;
    }

    function executeTransaction(uint256 _txIndex) public onlyOwner {
        require(_txIndex < transactions.length, "There is no such TX!");
        require(!transactions[_txIndex].executed, "Executed TX cannot be execute again!");
        require(transactions[_txIndex].numConfirmations >= requireConfirmations, "Not enough confirmations!");

        Transaction storage transaction = transactions[_txIndex];
        transaction.executed = true;

        require(transaction.value <= address(this).balance, "Insufficient balance!");

        (bool success,) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "Transaction failed");
    }
}
