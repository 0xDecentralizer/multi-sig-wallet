// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

contract MultiSigWalletTest is Test {
    // Constants and State Variables
    MultiSigWallet multiSigWallet;
    address owner1 = address(0x1);
    address owner2 = address(0x2);
    address owner3 = address(0x3);
    address[] owners;
    uint8 requireConfirmations = 2;

    // Events
    event TransactionSubmited(
        address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data
    );
    event TransactionConfirmed(address indexed owner, uint256 indexed txIndex);
    event ConfirmationRevoked(address indexed owner, uint256 indexed txIndex);
    event TransactionExecuted(address indexed owner, uint256 indexed txIndex);
    event OwnerAdded(address indexed newOwner);
    event OwnerRemoved(address indexed oldOwner);
    event RequireConfirmationsChanged(uint8 oldRequireConfirmations, uint8 newRequireConfirmations);

    // Setup
    function setUp() public {
        owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    // Helper Functions
    function setupTxWithTwoSignatures() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "");

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.confirmTransaction(txIndex);
    }

    // Constructor Tests
    function test_initateWallet() public {
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);

        assertEq(multiSigWallet.requireConfirmations(), 2);
        assertEq(multiSigWallet.numOwners(), 3);

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
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    function test_requireConfirmations() public {
        owners.pop();
        owners.pop();
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_ConfirmationsExceedOwnersCount.selector));
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    function test_duplicatedOwners() public {
        owners.push(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_DuplicateOwner.selector));
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    function testRevert_ownercannotBeZeroAddress() public {
        owners.push(address(0));
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InvalidOwnerAddress.selector));
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    // Transaction Submission Tests
    function testRevert_NonOwnerCannotCallSubmitTransaction() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.submitTransaction(address(0x111), 1, "");
    }

    function test_submitTransactionByOwner() public {
        address owner = owner1;
        address target = address(0xDe);
        uint256 value = 1 ether;
        uint256 txIndex = 0;
        bytes memory data = "0x123";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner, txIndex, target, value, data);
        multiSigWallet.submitTransaction(target, value, data);

        // Validate state
        (address to, uint256 txValue, bytes memory txData, bool executed, uint256 numConfirmations) =
            multiSigWallet.transactions(0);

        assertEq(to, target, "Target address mismatch");
        assertEq(txValue, value, "Transaction value mismatch");
        assertEq(txData, data, "Transaction data mismatch");
        assertEq(executed, false, "Transaction should not be executed yet");
        assertEq(numConfirmations, 0, "Transaction should start with 0 confimations");
    }

    // Transaction Confirmation Tests
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
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "");

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
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.confirmTransaction(txIndex);
    }

    function test_confirmTransactionByOwner() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "");

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);

        (,,,, uint256 numConfirmations) = multiSigWallet.transactions(0);
        assertEq(numConfirmations, 1);

        bool isConfirmed = multiSigWallet.isConfirmed(owner1, txIndex);
        assertEq(isConfirmed, true);
    }

    // Transaction Execution Tests
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
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "");

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotEnoughConfirmations.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_ExecuteTxWithInsufficientFund() public {
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "");

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
        multiSigWallet.submitTransaction(target, 1 wei, "0x1234");

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

        (,,, bool executed,) = multiSigWallet.transactions(txIndex);

        assertEq(executed, true);
    }

    // Owner Management Tests
    function test_ExecuteAddOwnerTxWithSufficientFund() public {
        address newOwner = address(0x4);
        uint256 txIndex = 0;
        uint256 numOwnersBeforeTx = multiSigWallet.numOwners();

        vm.prank(owner1);
        multiSigWallet.submitAddOwner(newOwner);

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.confirmTransaction(txIndex);

        vm.prank(owner1);
        vm.expectEmit(true, false, false, false);
        emit OwnerAdded(newOwner);
        multiSigWallet.executeTransaction(txIndex);

        assertEq(multiSigWallet.numOwners(), numOwnersBeforeTx + 1);
        assertEq(multiSigWallet.isOwner(newOwner), true);

        (,,, bool executed,) = multiSigWallet.transactions(txIndex);
        assertEq(executed, true);
    }

    function test_ExecuteRemoveOwnerTxWithSufficientFund() public {
        address oldOwner = owners[2];
        uint256 txIndex = 0;
        uint256 numOwnersBeforeTx = multiSigWallet.numOwners();

        vm.prank(owner1);
        multiSigWallet.submitRemoveOwner(oldOwner);

        vm.prank(owner1);
        multiSigWallet.confirmTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.confirmTransaction(txIndex);

        vm.prank(owner1);
        vm.expectEmit(true, false, false, false);
        emit OwnerRemoved(oldOwner);
        multiSigWallet.executeTransaction(txIndex);

        assertEq(multiSigWallet.numOwners(), numOwnersBeforeTx - 1);
        assertEq(multiSigWallet.isOwner(oldOwner), false);

        (,,, bool executed,) = multiSigWallet.transactions(txIndex);
        assertEq(executed, true);
    }

    function test_AddOwnerTx() public {
        address newOwner = address(0x4);
        uint256 txIndex = 0;
        bytes memory _data = abi.encodeWithSelector(MultiSigWallet.submitAddOwner.selector, newOwner);

        vm.prank(owner1);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner1, txIndex, address(multiSigWallet), 0, _data);
        multiSigWallet.submitAddOwner(newOwner);

        (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations) =
            multiSigWallet.transactions(txIndex);
        assertEq(to, address(multiSigWallet));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(executed, false);
        assertEq(numConfirmations, 0);
    }

    function testRevert_AddOwnerTxWithInvalidOwnerAddress() public {
        address newOwner = address(0x0);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InvalidOwnerAddress.selector));
        multiSigWallet.submitAddOwner(newOwner);
    }

    function testRevert_AddOwnerTxWithDuplicateOwner() public {
        address newOwner = owners[1];

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_DuplicateOwner.selector));
        multiSigWallet.submitAddOwner(newOwner);
    }

    function testRevert_NonOwnerCannotAddOwnerTx() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.submitAddOwner(address(0x4));
    }

    function testRevert_AddOwnerTxWithInsufficientConfirmations() public {
        address newOwner = address(0x4);
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitAddOwner(newOwner);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotEnoughConfirmations.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_RemoveOwnerTxWithInsufficientConfirmations() public {
        address oldOwner = owners[1];
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.submitRemoveOwner(oldOwner);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotEnoughConfirmations.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_RemoveOwnerTxWithInvalidOwnerAddress() public {
        address oldOwner = address(0xDe);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_OldOwnerInvalid.selector));
        multiSigWallet.submitRemoveOwner(oldOwner);
    }

    function testRevert_RemoveOwnerTxWithConfirmationsExceedOwnersCount() public {
        address oldOwner = owners[1];

        owners.pop();
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_ConfirmationsExceedOwnersCount.selector));
        multiSigWallet.submitRemoveOwner(oldOwner);
    }

    function testRevert_NonOwnerCannotRemoveOwner() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.submitRemoveOwner(owners[1]);
    }

    function test_RemoveOwnerTx() public {
        address oldOwner = owners[1];
        uint256 txIndex = 0;
        bytes memory _data = abi.encodeWithSelector(MultiSigWallet.submitRemoveOwner.selector, oldOwner);

        vm.prank(owner1);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner1, txIndex, address(multiSigWallet), 0, _data);
        multiSigWallet.submitRemoveOwner(oldOwner);

        (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations) =
            multiSigWallet.transactions(txIndex);
        assertEq(to, address(multiSigWallet));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(executed, false);
        assertEq(numConfirmations, 0);
    }

    // Confirmation Revocation Tests
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
        multiSigWallet.submitTransaction(address(0x1234), 1 wei, "");

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

        (,,,, uint256 numConfirmations) = multiSigWallet.transactions(0);
        assertEq(numConfirmations, 1);
    }

    // Event Emission Tests
    function testEmit_SubmitTransaction() public {
        address owner = owner1;
        uint256 txIndex = 0;
        address target = address(0x1234);
        uint256 value = 1 wei;
        bytes memory data = "0x123";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner, txIndex, target, value, data);
        multiSigWallet.submitTransaction(target, value, data);
    }

    function testEmit_ConfirmTransaction() public {
        address owner = owner1;
        uint256 txIndex = 0;
        address target = address(0x1234);
        uint256 value = 1 wei;
        bytes memory data = "0x123";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner, txIndex, target, value, data);
        multiSigWallet.submitTransaction(target, value, data);

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

    function test_getTransaction() public {
        uint256 txIndex = 0;
        setupTxWithTwoSignatures();

        multiSigWallet.getTransaction(txIndex);

        (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations) =
            multiSigWallet.transactions(txIndex);

        assertEq(to, address(0x1234));
        assertEq(value, 1 wei);
        assertEq(data, "");
        assertEq(executed, false);
        assertEq(numConfirmations, 2);
    }

    function testRevert_getTxWithInvalidTxIndex() public {
        uint256 txIndex = 1;

        setupTxWithTwoSignatures();

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxDoesNotExist.selector));
        multiSigWallet.getTransaction(txIndex);
    }

    function testRevert_changeRequireConfirmationsWithSameValue() public {
        uint8 newRequireConfirmations = 2;

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InvalidRequireConfirmations.selector));
        multiSigWallet.changeRequireConfirmations(newRequireConfirmations);
    }

    function testRevert_changeRequireConfirmationsWithInvalidValue_1() public {
        uint8 newRequireConfirmations = 0;

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InvalidRequireConfirmations.selector));
        multiSigWallet.changeRequireConfirmations(newRequireConfirmations);
    }

    function testRevert_changeRequireConfirmationsWithInvalidValue_2() public {
        uint8 newRequireConfirmations = 4; // 4 confirmations are more than the number of owners (3)

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_ConfirmationsExceedOwnersCount.selector));
        multiSigWallet.changeRequireConfirmations(newRequireConfirmations);
    }

    function testRevert_NonOwnerCannotChangeRequireConfirmations() public {
        address nonOwner = address(0xDe);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.changeRequireConfirmations(1);
    }

    function test_changeRequireConfirmations() public {
        // First add a new owner to allow increasing require confirmations to 3
        vm.startPrank(owner1);
        multiSigWallet.submitAddOwner(address(0x4));
        multiSigWallet.confirmTransaction(0);
        vm.stopPrank();

        vm.prank(owner2);
        multiSigWallet.confirmTransaction(0);

        vm.prank(owner1);
        multiSigWallet.executeTransaction(0);

        // Now change require confirmations to 3
        uint8 newRequireConfirmations = 3;
        uint256 changeReqConfTxIndex = 1;

        vm.prank(owner1);
        multiSigWallet.changeRequireConfirmations(newRequireConfirmations);

        // Get required confirmations from owners
        vm.prank(owner1);
        multiSigWallet.confirmTransaction(changeReqConfTxIndex);

        vm.prank(owner2);
        multiSigWallet.confirmTransaction(changeReqConfTxIndex);

        // Execute the change
        vm.prank(owner1);
        vm.expectEmit(true, true, false, false);
        emit RequireConfirmationsChanged(2, newRequireConfirmations);
        multiSigWallet.executeTransaction(changeReqConfTxIndex);

        // Verify the change
        assertEq(multiSigWallet.requireConfirmations(), newRequireConfirmations);
    }
}
