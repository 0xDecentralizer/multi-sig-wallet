// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract MultiSigWallet {
    
    address[] private owners;
    uint8 requireConfirmations;
    
    mapping(address => bool) isOwner;
    mapping(address => mapping (uint256 => bool)) isConfirmed;

    constructor(address [] memory _owners, uint8 _requireConfirmations) {
        require(_owners.length != 0, "Owners list can't be empty!");
        require(
            _owners.length >= _requireConfirmations,
            "Confirmations can't be greater than number of owners"
        );
        for (uint i = 0; i < _owners.length; i++) {
            for (uint j = 0; j < _owners.length; j++) {
                if(_owners[i] == _owners[j] && i != j) {
                    revert("Onwers not uniqe!");
                }
            }
        }
        owners = _owners;
        requireConfirmations = _requireConfirmations;
    }

    modifier onlyOwners {
        for (uint i = 0; i < owners.length; i++) {
                if(msg.sender == owners[i]) {
                    _;
                }
        }
    }

    struct Transactions {
        address to;
        uint256 value;
        bytes32 data;
        bool executed;
        uint8 numConfirmations;
    }

    Transactions[] transactions;
    uint256 transactionCounts;

    function setTransaction(address _to, uint256 _value, bytes32 _data) external onlyOwners {
        Transactions memory newTransaction = Transactions ({
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            numConfirmations: 0
        });
        transactions.push(newTransaction);
        transactionCounts += 1;
    }

    function signTransaction(uint256 _txIndex) external onlyOwners {
        require(_txIndex < transactionCounts, "There is no such TX!");
        require(transactions[_txIndex].executed == false, "This TX has been executed!");
        require(isConfirmed[msg.sender][_txIndex] == false, "You signed this TX before!");

        transactions[_txIndex].numConfirmations += 1;
        isConfirmed[msg.sender][_txIndex] = true;   
    }

}