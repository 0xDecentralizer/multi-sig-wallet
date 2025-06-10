# Multi-Signature Wallet

A secure, upgradeable multi-signature wallet smart contract built with Solidity. This contract enables decentralized management of funds through multi-owner governance.

## Features

- 🔐 Multi-owner governance with configurable confirmation thresholds
- 💰 Support for both ETH and ERC20 tokens
- ⚡ Dynamic owner management through multi-sig consensus
- 🔄 Upgradeable contract architecture
- ⏱️ Configurable transaction expiration
- 📝 Comprehensive event logging
- 🛡️ Extensive security checks and validations

## Prerequisites

- Solidity ^0.8.22
- Foundry
- OpenZeppelin Contracts

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/multi-sig-wallet.git
cd multi-sig-wallet

# Install dependencies
forge install
```

## Usage

### Deployment

Deploy the contract with the following parameters:

```solidity
constructor(
    address[] memory _owners,
    uint8 _requiredConfirmations
)
```

- `_owners`: Array of owner addresses (minimum 1, no duplicates)
- `_requiredConfirmations`: Number of required confirmations (minimum 1, maximum owners count)

### Core Functions

#### Transaction Management
```solidity
function submitTransaction(
    address token,
    address to,
    uint256 value,
    bytes data,
    uint256 expiration
) external returns (uint256 txIndex)

function confirmTransaction(uint256 txIndex) external
function executeTransaction(uint256 txIndex) external
function revokeConfirmation(uint256 txIndex) external
```

#### Owner Management
```solidity
function submitAddOwner(address newOwner, uint256 expiration) external
function submitRemoveOwner(address ownerToRemove, uint256 expiration) external
function changeRequiredConfirmations(uint8 newRequired, uint256 expiration) external
```

## Testing

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/MultiSigWallet.t.sol
```

## Security Considerations

1. **Owner Selection**
   - Choose trusted owners
   - Consider using hardware wallets
   - Implement proper key management

2. **Confirmation Threshold**
   - Set appropriate confirmation requirements
   - Consider transaction value and risk level
   - Implement time locks for critical operations

3. **Transaction Management**
   - Set reasonable expiration times
   - Validate token addresses and amounts
   - Monitor transaction status

## Architecture

The contract system consists of:

- `MultiSigWallet.sol`: Main contract implementation
- `MultiSigWalletEvents.sol`: Event definitions
- `MultiSigWalletErrors.sol`: Custom error definitions
- `Proxy.sol`: Upgradeability proxy
- `UpgradableSetup.sol`: Upgrade initialization

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support, please open an issue in the GitHub repository.
