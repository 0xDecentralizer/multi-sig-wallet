// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract MultiSigWallet {
    
    address[] private owners;
    uint8 requireConfirmations;
    
    mapping(address => bool) isOwner;
    mapping(address => mapping (uint256 => bool)) public isConfirmed;

    constructor(address [] memory _owners, uint8 _requireConfirmations) {
        require(_owners.length != 0, "Owners list can't be empty!");
        require(
            _owners.length >= _requireConfirmations,
            "Confirmations can't be greater than number of owners"
        );
        
        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Owner can't be 0 address");
            require(!isOwner[owner], "Duplicate Owner not accepted");

            isOwner[owner] = true; // ************ TEST NEEDED ************
            owners.push(owner); // ************ TEST NEEDED ************
        }
        requireConfirmations = _requireConfirmations;
    }

    modifier onlyOwners {
        require(isOwner[msg.sender], "Not an owner!");
        _;
    }

    struct Transactions {
        address to;
        uint256 value;
        bytes32 data;
        bool executed;
        uint8 numConfirmations;
    }

    Transactions[] public transactions;

    function setTransaction(address _to, uint256 _value, bytes32 _data) external onlyOwners {
        Transactions memory newTransaction = Transactions ({
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            numConfirmations: 0
        });
        transactions.push(newTransaction);
    }

    function signTransaction(uint256 _txIndex) external onlyOwners {
        require(_txIndex < transactions.length, "There is no such TX!");
        require(transactions[_txIndex].executed == false, "This TX has been executed!");
        require(isConfirmed[msg.sender][_txIndex] == false, "You signed this TX before!");

        transactions[_txIndex].numConfirmations += 1;
        isConfirmed[msg.sender][_txIndex] = true;   
    }

}