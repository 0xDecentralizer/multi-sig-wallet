// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

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
error MSW_TransactionDataTooLarge();
error MSW_InvalidRecipientAddress();
error MSW_TooManyConfirmations();