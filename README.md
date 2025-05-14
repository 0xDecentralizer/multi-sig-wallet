# Multi-Signature Wallet

A robust, upgradeable **multi-signature wallet** smart contract built with Solidity. Designed for secure, decentralized management of funds by multiple owners.

---

## Key Features
- **Multi-Owner Governance:** Transactions require multiple owner approvals before execution
- **Secure Transaction Flow:** Owners can submit, confirm, revoke, and execute transactions safely
- **Transparent Auditing:** Events emitted for all critical actions for easy tracking and integration
- **Flexibility:** Customizable number of required confirmations during deployment
- **Token Support:** Handles both native tokens (ETH) and ERC20 tokens
- **Owner Management:** Add and remove owners through multi-sig consensus
- **Dynamic Configuration:** Adjustable required confirmations through owner voting
- **Transaction Expiration:** Configurable expiration time for pending transactions
- **Enhanced Security:** Comprehensive error handling and validation checks

---

## Contract Overview

| Component | Description |
|:----------|:------------|
| **Owners** | List of authorized wallet controllers |
| **Transactions** | Struct containing recipient address, amount, token address, call data, execution status, and expiration time |
| **Confirmations** | Mapping to track which owners have approved each transaction |
| **Modifiers** | Role-based access control and transaction state validation |
| **Events** | Comprehensive event system for all wallet operations |

---

## Core Functions

### Transaction Management
- `submitTransaction(address token, address to, uint256 value, bytes data, uint256 expiration)`
- `confirmTransaction(uint256 txIndex)`
- `executeTransaction(uint256 txIndex)`
- `revokeConfirmation(uint256 txIndex)`

### Owner Management
- `submitAddOwner(address newOwner, uint256 expiration)`
- `submitRemoveOwner(address ownerToRemove, uint256 expiration)`
- `changeRequiredConfirmations(uint8 newRequired, uint256 expiration)`

Each function is protected with appropriate access control to ensure wallet integrity.

---

## How to Deploy

1. Clone this repository
2. Deploy the contract with:
   - **Owners array** (at least one address, no duplicates)
   - **Required confirmations** (at least 1, not more than the number of owners)

**Example constructor parameters:**
```plaintext
owners: [0xOwner1, 0xOwner2, 0xOwner3]
requiredConfirmations: 2
```

3. Use Foundry for testing and deployment.

---

## Security Best Practices
- Owners must be fully trusted parties
- Critical transactions should require high confirmation thresholds
- Set appropriate expiration times for transactions
- Consider implementing time locks for production environments
- Validate token addresses and amounts before transactions

---

## Features in Detail

### Token Support
- Native ETH transactions
- ERC20 token transfers
- Automatic token balance validation
- Support for custom token contracts

### Transaction Expiration
- Configurable expiration time for each transaction
- Automatic invalidation of expired transactions
- Prevents stale transaction execution

### Owner Management
- Multi-sig consensus for owner changes
- Validation of owner addresses
- Prevention of duplicate owners
- Dynamic adjustment of required confirmations

---

## Tech Stack
- Solidity ^0.8.22
- Foundry / Hardhat for testing and deployment
- OpenZeppelin (optional security enhancements)

---

## License
[MIT License](LICENSE)

---

## Author
Crafted with focus on security, simplicity, and scalability.
