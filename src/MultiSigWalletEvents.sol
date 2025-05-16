// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// ============ Events ============
event TransactionSubmitted(
    address token,
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
