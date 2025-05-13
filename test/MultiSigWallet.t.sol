// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title MultiSigWalletTest
/// @notice Test suite for the MultiSigWallet contract
contract MultiSigWalletTest is Test {
    // ============ Constants and State Variables ============
    MultiSigWallet multiSigWallet;
    address owner1 = address(0x1);
    address owner2 = address(0x2);
    address owner3 = address(0x3);
    address[] owners;
    uint8 requiredConfirmations = 2;
    uint256 expirationTime = 604800; // 1 weeks

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
    event OwnerAdded(address indexed newOwner);
    event OwnerRemoved(address indexed oldOwner);
    event RequireConfirmationsChanged(uint8 indexed oldReqConf, uint8 indexed newReqConf);

    // ============ Setup ============
    function setUp() public {
        owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        multiSigWallet = new MultiSigWallet(owners, requiredConfirmations);
    }

    // ============ Helper Functions ============
    function setupTxWithTwoSignatures() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "", expirationTime);

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.confirmTransaction(txIndex);
    }

    // ============ Constructor Tests ============
    function test_initateWallet() public {
        multiSigWallet = new MultiSigWallet(owners, requiredConfirmations);

        assertEq(multiSigWallet.requiredConfirmations(), 2);
        assertEq(multiSigWallet.getOwnerCount(), 3);

        address[] memory walletOwners = multiSigWallet.getOwners();

        assertEq(walletOwners[0], address(0x1), "Owner at index 0 mismatch");
        assertEq(walletOwners[1], address(0x2), "Owner at index 1 mismatch");
        assertEq(walletOwners[2], address(0x3), "Owner at index 2 mismatch");

        assertEq(multiSigWallet.isOwner(walletOwners[0]), true);
        assertEq(multiSigWallet.isOwner(walletOwners[1]), true);
        assertEq(multiSigWallet.isOwner(walletOwners[2]), true);
    }

    function test_emptyOwners() public {
        owners = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_EmptyOwnersList.selector));
        multiSigWallet = new MultiSigWallet(owners, requiredConfirmations);
    }

    function test_requiredConfirmations() public {
        owners.pop();
        owners.pop();
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_ConfirmationsExceedOwnersCount.selector));
        multiSigWallet = new MultiSigWallet(owners, requiredConfirmations);
    }

    function test_duplicatedOwners() public {
        owners.push(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_DuplicateOwner.selector));
        multiSigWallet = new MultiSigWallet(owners, requiredConfirmations);
    }

    function testRevert_ownerCannotBeZeroAddress() public {
        owners.push(address(0));
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InvalidOwnerAddress.selector));
        multiSigWallet = new MultiSigWallet(owners, requiredConfirmations);
    }

    // ============ Transaction Submission Tests ============
    function testRevert_NonOwnerCannotCallSubmitTransaction() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.submitTransaction(address(0x111), 1, "", expirationTime);
    }

    function test_submitTransactionByOwner() public {
        address owner = owner1;
        address target = address(0xDe);
        uint256 value = 1 ether;
        uint256 txIndex = 0;
        bytes memory data = "0x123";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmitted(owner, txIndex, target, value, data, block.timestamp + expirationTime);
        multiSigWallet.submitTransaction(target, value, data, block.timestamp + expirationTime);

        // Validate state
        (address to, uint256 txValue, bytes memory txData, bool executed, uint256 numConfirmations, uint256 expiration) =
            multiSigWallet.transactions(0);

        assertEq(to, target, "Target address mismatch");
        assertEq(txValue, value, "Transaction value mismatch");
        assertEq(txData, data, "Transaction data mismatch");
        assertEq(executed, false, "Transaction should not be executed yet");
        assertEq(numConfirmations, 0, "Transaction should start with 0 confirmations");
        assertLt(block.timestamp, block.timestamp + expiration, "Transaction should not be expired");
    }

    // ============ Transaction Confirmation Tests ============
    function testRevert_ANonExistTxCannotBeSign() public {
        uint256 txIndex = 1;

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxDoesNotExist.selector));
        multiSigWallet.confirmTransaction(txIndex);
    }

    function testRevert_AnExecutedTxCannotBeSign() public {
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();
        vm.prank(owner1);
        vm.deal(address(multiSigWallet), 1 ether);
        multiSigWallet.executeTransaction(txIndex);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxAlreadyExecuted.selector));
        multiSigWallet.confirmTransaction(txIndex);
    }

    function testRevert_ownerCannotSignATxMoreThanOnce() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "", block.timestamp + expirationTime);

        vm.prank(owner2);
        multiSigWallet.confirmTransaction(txIndex);

        vm.prank(owner2);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxAlreadySigned.selector));
        multiSigWallet.confirmTransaction(txIndex);
    }

    function testRevert_NonOwnerCannotSignATx() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");
        uint256 txIndex = 0;

        vm.prank(owners[0]);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "", block.timestamp + expirationTime);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.confirmTransaction(txIndex);
    }

    function test_confirmTransactionByOwner() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "", block.timestamp + expirationTime);

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);

        (,,,, uint256 numConfirmations,) = multiSigWallet.transactions(0);
        assertEq(numConfirmations, 1);

        bool isConfirmed = multiSigWallet.isConfirmed(owner1, txIndex);
        assertEq(isConfirmed, true);
    }

    // ============ Transaction Execution Tests ============
    function testRevert_AnExecutedTxCannotBeExecuted() public {
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();
        vm.prank(owner1);
        vm.deal(address(multiSigWallet), 1 ether);
        multiSigWallet.executeTransaction(txIndex);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxAlreadyExecuted.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_NonExistentTxCannotBeExecuted() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxDoesNotExist.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_ExecuteTxWithInsufficientConfirmations() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "", block.timestamp + expirationTime);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotEnoughConfirmations.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_ExecuteTxWithInsufficientFund() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "", block.timestamp + expirationTime);

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.confirmTransaction(txIndex);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InsufficientBalance.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_ExecuteTxWithFailedCall() public {
        address target = address(multiSigWallet);
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(target, 1 wei, "0x1234", block.timestamp + expirationTime);

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.confirmTransaction(txIndex);

        vm.deal(address(multiSigWallet), 1 ether);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TransactionFailed.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function test_NonOwnerCannotCallExecuteTransaction() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.executeTransaction(0);
    }

    function test_ExecuteRegularTxWithSufficientFund() public {
        setupTxWithTwoSignatures();

        uint256 txIndex = 0;

        vm.prank(owner1);
        vm.deal(address(multiSigWallet), 1 ether);
        multiSigWallet.executeTransaction(txIndex);

        (,,, bool executed,,) = multiSigWallet.transactions(txIndex);

        assertEq(executed, true);
    }

    // ============ Owner Management Tests ============
    function test_ExecuteAddOwnerTxWithSufficientFund() public {
        address newOwner = address(0x4);
        uint256 txIndex = 0;
        uint256 numOwnersBeforeTx = multiSigWallet.getOwnerCount();

        vm.prank(owner1);
        multiSigWallet.submitAddOwner(newOwner, block.timestamp + expirationTime);

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.confirmTransaction(txIndex);

        vm.prank(owner1);
        vm.expectEmit(true, false, false, false);
        emit OwnerAdded(newOwner);
        multiSigWallet.executeTransaction(txIndex);

        assertEq(multiSigWallet.getOwnerCount(), numOwnersBeforeTx + 1);
        assertEq(multiSigWallet.isOwner(newOwner), true);

        (,,, bool executed,,) = multiSigWallet.transactions(txIndex);
        assertEq(executed, true);
    }

    function test_ExecuteRemoveOwnerTxWithSufficientFund() public {
        address oldOwner = owners[2];
        uint256 txIndex = 0;
        uint256 numOwnersBeforeTx = multiSigWallet.getOwnerCount();

        vm.prank(owner1);
        multiSigWallet.submitRemoveOwner(oldOwner, block.timestamp + expirationTime);

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.confirmTransaction(txIndex);

        vm.prank(owner1);
        vm.expectEmit(true, false, false, false);
        emit OwnerRemoved(oldOwner);
        multiSigWallet.executeTransaction(txIndex);

        assertEq(multiSigWallet.getOwnerCount(), numOwnersBeforeTx - 1);
        assertEq(multiSigWallet.isOwner(oldOwner), false);

        (,,, bool executed,,) = multiSigWallet.transactions(txIndex);
        assertEq(executed, true);
    }

    function test_AddOwnerTx() public {
        address newOwner = address(0x4);
        uint256 txIndex = 0;
        bytes memory _data = abi.encodeWithSelector(MultiSigWallet.submitAddOwner.selector, newOwner);

        vm.prank(owner1);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmitted(owner1, txIndex, address(multiSigWallet), 0, _data, block.timestamp + expirationTime);
        multiSigWallet.submitAddOwner(newOwner, block.timestamp + expirationTime);

        (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations, uint256 expiration) =
            multiSigWallet.transactions(txIndex);
        assertEq(to, address(multiSigWallet));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(executed, false);
        assertEq(numConfirmations, 0);
        assertLt(block.timestamp, block.timestamp + expiration, "Transaction should not be expired");
    }

    function testRevert_AddOwnerTxWithInvalidOwnerAddress() public {
        address newOwner = address(0x0);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InvalidOwnerAddress.selector));
        multiSigWallet.submitAddOwner(newOwner, block.timestamp + expirationTime);
    }

    function testRevert_AddOwnerTxWithDuplicateOwner() public {
        address newOwner = owners[1];

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_DuplicateOwner.selector));
        multiSigWallet.submitAddOwner(newOwner, block.timestamp + expirationTime);
    }

    function testRevert_NonOwnerCannotAddOwnerTx() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.submitAddOwner(address(0x4), block.timestamp + expirationTime);
    }

    function testRevert_AddOwnerTxWithInsufficientConfirmations() public {
        address newOwner = address(0x4);
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitAddOwner(newOwner, block.timestamp + expirationTime);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotEnoughConfirmations.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_RemoveOwnerTxWithInsufficientConfirmations() public {
        address oldOwner = owners[1];
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitRemoveOwner(oldOwner, block.timestamp + expirationTime);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotEnoughConfirmations.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_RemoveOwnerTxWithInvalidOwnerAddress() public {
        address oldOwner = address(0xDe);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_OldOwnerInvalid.selector));
        multiSigWallet.submitRemoveOwner(oldOwner, block.timestamp + expirationTime);
    }

    function testRevert_RemoveOwnerTxWithConfirmationsExceedOwnersCount() public {
        address oldOwner = owners[1];

        owners.pop();
        multiSigWallet = new MultiSigWallet(owners, requiredConfirmations);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_ConfirmationsExceedOwnersCount.selector));
        multiSigWallet.submitRemoveOwner(oldOwner, block.timestamp + expirationTime);
    }

    function testRevert_NonOwnerCannotRemoveOwner() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.submitRemoveOwner(owners[1], block.timestamp + expirationTime);
    }

    function test_RemoveOwnerTx() public {
        address oldOwner = owners[1];
        uint256 txIndex = 0;
        bytes memory _data = abi.encodeWithSelector(MultiSigWallet.submitRemoveOwner.selector, oldOwner);

        vm.prank(owner1);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmitted(owner1, txIndex, address(multiSigWallet), 0, _data, block.timestamp + expirationTime);
        multiSigWallet.submitRemoveOwner(oldOwner, block.timestamp + expirationTime);

        (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations, uint256 expiration) =
            multiSigWallet.transactions(txIndex);
        assertEq(to, address(multiSigWallet));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(executed, false);
        assertEq(numConfirmations, 0);
        assertLt(block.timestamp, block.timestamp + expiration, "Transaction should not be expired");
    }

    // ============ Confirmation Revocation Tests ============
    function testRevert_RevokingNonExistentTx() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxDoesNotExist.selector));
        multiSigWallet.revokeConfirmation(txIndex);
    }

    function testRevert_RevokingExecutedTx() public {
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();
        vm.deal(address(multiSigWallet), 1 ether);
        vm.prank(owner1);
        multiSigWallet.executeTransaction(txIndex);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxAlreadyExecuted.selector));
        multiSigWallet.revokeConfirmation(txIndex);
    }

    function testRevert_RevokingNotSignedTx() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "", block.timestamp + expirationTime);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxNotSigned.selector));
        multiSigWallet.revokeConfirmation(txIndex);
    }

    function testRevert_NonOwnerRevokingTx() public {
        address nonOwner = address(0x1234);
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.revokeConfirmation(txIndex);
    }

    function test_RevokingTx() public {
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();

        vm.prank(owner1);
        multiSigWallet.revokeConfirmation(txIndex);

        bool isConfirmed = multiSigWallet.isConfirmed(owner1, txIndex);
        assertEq(isConfirmed, false);

        (,,,, uint256 numConfirmations,) = multiSigWallet.transactions(0);
        assertEq(numConfirmations, 1);
    }

    // ============ Event Emission Tests ============
    function testEmit_SubmitTransaction() public {
        address owner = owner1;
        uint256 txIndex = 0;
        address target = address(0x1234);
        uint256 value = 1 wei;
        bytes memory data = "0x123";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmitted(owner, txIndex, target, value, data, expirationTime);
        multiSigWallet.submitTransaction(target, value, data, expirationTime);
    }

    function testEmit_ConfirmTransaction() public {
        address owner = owner1;
        uint256 txIndex = 0;
        address target = address(0x1234);
        uint256 value = 1 wei;
        bytes memory data = "0x123";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmitted(owner, txIndex, target, value, data, block.timestamp + expirationTime);
        multiSigWallet.submitTransaction(target, value, data, block.timestamp + expirationTime);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit TransactionConfirmed(owner, txIndex);
        multiSigWallet.confirmTransaction(txIndex);
    }

    function testEmit_RevokeConfirmation() public {
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();

        vm.prank(owner1);
        vm.expectEmit(true, true, false, false);
        emit ConfirmationRevoked(owner1, txIndex);
        multiSigWallet.revokeConfirmation(txIndex);
    }

    function testEmit_ExecuteTransaction() public {
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();
        vm.deal(address(multiSigWallet), 1 ether);

        vm.prank(owner1);
        vm.expectEmit(true, true, false, false);
        emit TransactionExecuted(owner1, txIndex);
        multiSigWallet.executeTransaction(txIndex);
    }

    // ============ View Function Tests ============
    function test_getTransaction() public {
        uint256 txIndex = 0;
        setupTxWithTwoSignatures();

        multiSigWallet.getTransaction(txIndex);

        (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations, uint256 expiration) =
            multiSigWallet.transactions(txIndex);

        assertEq(to, address(0x1234));
        assertEq(value, 1 wei);
        assertEq(data, "");
        assertEq(executed, false);
        assertEq(numConfirmations, 2);
        assertLt(block.timestamp, block.timestamp + expiration, "Transaction should not be expired");
    }

    function testRevert_getTxWithInvalidTxIndex() public {
        uint256 txIndex = 1;

        setupTxWithTwoSignatures();

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxDoesNotExist.selector));
        multiSigWallet.getTransaction(txIndex);
    }

    // ============ Required Confirmations Tests ============
    function testRevert_changeRequiredConfirmationsWithSameValue() public {
        uint8 newRequiredConfirmations = 2;

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InvalidRequireConfirmations.selector));
        multiSigWallet.changeRequiredConfirmations(newRequiredConfirmations, block.timestamp + expirationTime);
    }

    function testRevert_changeRequiredConfirmationsWithInvalidValue_1() public {
        uint8 newRequiredConfirmations = 0;

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InvalidRequireConfirmations.selector));
        multiSigWallet.changeRequiredConfirmations(newRequiredConfirmations, block.timestamp + expirationTime);
    }

    function testRevert_changeRequiredConfirmationsWithInvalidValue_2() public {
        uint8 newRequiredConfirmations = 4; // 4 confirmations are more than the number of owners (3)

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_ConfirmationsExceedOwnersCount.selector));
        multiSigWallet.changeRequiredConfirmations(newRequiredConfirmations, block.timestamp + expirationTime);
    }

    function testRevert_NonOwnerCannotChangeRequiredConfirmations() public {
        address nonOwner = address(0xDe);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.changeRequiredConfirmations(1, block.timestamp + expirationTime);
    }

    function test_changeRequiredConfirmations() public {
        // First add a new owner to allow increasing required confirmations to 3
        vm.startPrank(owner1);
        multiSigWallet.submitAddOwner(address(0x4), block.timestamp + expirationTime);
        multiSigWallet.confirmTransaction(0);
        vm.stopPrank();

        vm.prank(owner2);
        multiSigWallet.confirmTransaction(0);

        vm.prank(owner1);
        multiSigWallet.executeTransaction(0);

        // Now change required confirmations to 3
        uint8 newRequiredConfirmations = 3;
        uint256 changeReqConfTxIndex = 1;

        vm.prank(owner1);
        multiSigWallet.changeRequiredConfirmations(newRequiredConfirmations, block.timestamp + expirationTime);

        // Get required confirmations from owners
        vm.prank(owner1);
        multiSigWallet.confirmTransaction(changeReqConfTxIndex);

        vm.prank(owner2);
        multiSigWallet.confirmTransaction(changeReqConfTxIndex);

        // Execute the change
        vm.prank(owner1);
        vm.expectEmit(true, true, false, false);
        emit RequireConfirmationsChanged(2, newRequiredConfirmations);
        multiSigWallet.executeTransaction(changeReqConfTxIndex);

        // Verify the change
        assertEq(multiSigWallet.requiredConfirmations(), newRequiredConfirmations);
    }
}
