// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

contract MultiSigWalletTest is Test {
    MultiSigWallet multiSigWallet;
    address[] owners;
    uint8 requireConfirmations = 2;

    event TransactionSubmited(address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data);
    event TransactionConfirmed(address indexed owner, uint256 indexed txIndex);
    event ConfirmationRevoked(address indexed owner, uint256 indexed txIndex);
    event TransactionExecuted(address indexed owner, uint256 indexed txIndex);
    event OwnerAdded(address indexed newOwner);
    event OwnerRemoved(address indexed oldOwner);

    function setUp() public {
        owners = new address[](3);
        owners[0] = address(0x1);
        owners[1] = address(0x2);
        owners[2] = address(0x3);
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    function setupTxWithTwoSignatures() public {
        address owner1 = owners[0];
        address owner2 = owners[1];
        uint256 txIndex = 0;

        vm.prank(owner1);
        multiSigWallet.setTransaction(address(0x1234), 1 wei, "");

        vm.prank(owner1);
        multiSigWallet.signTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.signTransaction(txIndex);
    }

    function test_emptyOwners() public {
        owners = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_EmptyOwnersList.selector));
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

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

    function testRevert_NonOwnerCannotCallSetTransaction() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));

        multiSigWallet.setTransaction(address(0x111), 1, "");
    }

    function test_setTransactionByOwner() public {
        address owner = owners[0];
        address target = address(0xDe);
        uint256 value = 1 ether;
        uint256 txIndex = 0;
        bytes memory data = "0x123";

        vm.prank(owners[0]);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner, txIndex, target, value, data);
        multiSigWallet.setTransaction(target, value, data);

        // Validate state
        (address to, uint256 txValue, bytes memory txData, bool executed, uint256 numConfirmations) =
            multiSigWallet.transactions(0);

        assertEq(to, target, "Target address mismatch");
        assertEq(txValue, value, "Transaction value mismatch");
        assertEq(txData, data, "Transaction data mismatch");
        assertEq(executed, false, "Transaction should not be executed yet");
        assertEq(numConfirmations, 0, "Transaction should start with 0 confimations");
    }

    function testRevert_ANonExistTxCannotBeSign() public {
        uint256 txIndex = 1;
        address owner = owners[0];
        vm.label(owner, "Owner");

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxDoesNotExist.selector));
        multiSigWallet.signTransaction(txIndex);
    }

    function testRevert_AnExecutedTxCannotBeSign() public {
        address owner = owners[0];
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();
        vm.prank(owner);
        vm.deal(address(multiSigWallet), 1 ether);
        multiSigWallet.executeTransaction(txIndex);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxAlreadyExecuted.selector));
        multiSigWallet.signTransaction(txIndex);
    }

    function testRevert_ownerCannotSignATxMoreThanOnce() public {
        address owner1 = owners[0];
        address owner2 = owners[1];
        uint256 txIndex;

        // Initial a transaction by one of the owners
        vm.prank(owner1);
        multiSigWallet.setTransaction(address(0x1234), 1 wei, "");
        txIndex = 0;

        // Sign the transaction by one of the owners
        vm.prank(owner2);
        multiSigWallet.signTransaction(txIndex);

        // Sign the EXACT transaction again
        vm.prank(owner2);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxAlreadySigned.selector));
        multiSigWallet.signTransaction(txIndex);
    }
    
    function testRevert_NonOwnerCannotSignATx() public {
        address nonOwner = address(0xDe);
        vm.label(nonOwner, "NonOwner");
        uint256 txIndex = 0;

        // Initial a transaction by one of the owners
        vm.prank(owners[0]);
        multiSigWallet.setTransaction(address(0x1234), 1 wei, "");

        // Sign the transaction by a non-owner
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.signTransaction(txIndex);
    }

    function test_signTransactionByOwner() public {
        address owner = owners[0];
        uint256 txIndex = 0;

        vm.prank(owner);
        multiSigWallet.setTransaction(address(0x1234), 1 wei, "");

        vm.prank(owner);
        multiSigWallet.signTransaction(txIndex);

        (,,,, uint256 numConfirmations) = multiSigWallet.transactions(0);
        assertEq(numConfirmations, 1);

        bool isConfirmed = multiSigWallet.isConfirmed(owner, txIndex);
        assertEq(isConfirmed, true);
    }

    function testRevert_AnExecutedTxCannotBeExecuted() public {
        address owner = owners[0];
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();
        vm.prank(owner);
        vm.deal(address(multiSigWallet), 1 ether);
        multiSigWallet.executeTransaction(txIndex);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxAlreadyExecuted.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_NonExistentTxCannotBeExecuted() public {
        address owenr = owners[0];
        uint256 txIndex = 0;

        vm.prank(owenr);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxDoesNotExist.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_ExecuteTxWithInsufficientConfirmations() public {
        address owner = owners[0];
        uint256 txIndex = 0;

        // Set a transaction with - It has 0 confirmations
        vm.prank(owner);
        multiSigWallet.setTransaction(address(0x1234), 1 wei, "");

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotEnoughConfirmations.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_ExecuteTxWithInsufficientFund() public {
        address owner = owners[0];
        address owner2 = owners[1];
        uint256 txIndex = 0;

        // Set a transaction with - It has 0 confirmations
        vm.prank(owner);
        multiSigWallet.setTransaction(address(0x1234), 1 wei, "");

        // Confirm the transaction
        vm.prank(owner);
        multiSigWallet.signTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.signTransaction(txIndex);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InsufficientBalance.selector));
        multiSigWallet.executeTransaction(txIndex);
    }

    function testRevert_ExecuteTxWithFailedCall() public {
        address owner = owners[0];
        address owner2 = owners[1];
        address target = address(multiSigWallet);
        uint256 txIndex = 0;

        // Set a transaction with - It has 0 confirmations
        vm.prank(owner);
        multiSigWallet.setTransaction(target, 1 wei, "0x1234"); // There is no function with this signature

        // Confirm the transaction
        vm.prank(owner);
        multiSigWallet.signTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.signTransaction(txIndex);

        vm.deal(address(multiSigWallet), 1 ether);

        vm.prank(owner);
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

        address owner = owners[0];
        uint256 txIndex = 0;

        vm.prank(owner);
        vm.deal(address(multiSigWallet), 1 ether);
        multiSigWallet.executeTransaction(txIndex);

        (,,, bool executed,) = multiSigWallet.transactions(txIndex);

        assertEq(executed, true);
    }

    function test_ExecuteAddOwnerTxWithSufficientFund() public {
        address owner1 = owners[0];
        address owner2 = owners[1];
        address newOwner = address(0x4);
        uint256 txIndex = 0;
        uint256 numOwnersBeforeTx = multiSigWallet.numOwners();

        vm.prank(owner1);
        multiSigWallet.submitAddOwner(newOwner);

        vm.prank(owner1);
        multiSigWallet.signTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.signTransaction(txIndex);

        vm.prank(owner1);
        vm.expectEmit(true, false, false, false);
        emit OwnerAdded(newOwner);
        multiSigWallet.executeTransaction(txIndex);

        assertEq(multiSigWallet.numOwners(), numOwnersBeforeTx + 1);
        assertEq(multiSigWallet.isOwner(newOwner), true);

        (,,, bool executed, ) = multiSigWallet.transactions(txIndex);
        assertEq(executed, true);
    }

    function test_ExecuteRemoveOwnerTxWithSufficientFund() public {
        address owner1 = owners[0];
        address owner2 = owners[1];
        address oldOwner = owners[2];
        uint256 txIndex = 0;
        uint256 numOwnersBeforeTx = multiSigWallet.numOwners();

        vm.prank(owner1);
        multiSigWallet.submitRemoveOwner(oldOwner);

        vm.prank(owner1);
        multiSigWallet.signTransaction(txIndex);
        vm.prank(owner2);
        multiSigWallet.signTransaction(txIndex);

        vm.prank(owner1);
        vm.expectEmit(true, false, false, false);
        emit OwnerRemoved(oldOwner);
        multiSigWallet.executeTransaction(txIndex);

        assertEq(multiSigWallet.numOwners(), numOwnersBeforeTx - 1);
        assertEq(multiSigWallet.isOwner(oldOwner), false);

        (,,, bool executed, ) = multiSigWallet.transactions(txIndex);
        assertEq(executed, true);
    }

    function test_AddOwnerTx() public {
        address owner = owners[0];
        address newOwner = address(0x4);
        uint256 txIndex = 0;
        bytes memory _data = abi.encodeWithSelector(MultiSigWallet.submitAddOwner.selector, newOwner);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner, txIndex, address(multiSigWallet), 0, _data);
        multiSigWallet.submitAddOwner(newOwner);

        (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations) = multiSigWallet.transactions(txIndex);
        assertEq(to, address(multiSigWallet));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(executed, false);
        assertEq(numConfirmations, 0);
    }

    function testRevert_AddOwnerTxWithInvalidOwnerAddress() public {
        address owner = owners[0];
        address newOwner = address(0x0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_InvalidOwnerAddress.selector));
        multiSigWallet.submitAddOwner(newOwner);
    }

    function testRevert_AddOwnerTxWithDuplicateOwner() public {
        address owner = owners[0];
        address newOwner = owners[1];
        
        vm.prank(owner);
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
        address owner = owners[0];
        address newOwner = address(0x4);
        uint256 txIndex = 0;
        
        vm.prank(owner);
        multiSigWallet.submitAddOwner(newOwner);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotEnoughConfirmations.selector));
        multiSigWallet.executeTransaction(txIndex);
    }
    
    function testRevert_RemoveOwnerTxWithInsufficientConfirmations() public {
        address owner = owners[0];
        address oldOwner = owners[1];
        uint256 txIndex = 0;
        
        vm.prank(owner);
        multiSigWallet.submitRemoveOwner(oldOwner);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotEnoughConfirmations.selector));
        multiSigWallet.executeTransaction(txIndex);
    }
    
    function testRevert_RemoveOwnerTxWithInvalidOwnerAddress() public {
        address owner = owners[0];
        address oldOwner = address(0xDe);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_OldOwnerInvalid.selector));
        multiSigWallet.submitRemoveOwner(oldOwner);
    }
    
    function testRevert_RemoveOwnerTxWithConfirmationsExceedOwnersCount() public {
        address owner = owners[0]; // 0x1
        address oldOwner = owners[1]; // 0x2

        owners.pop(); // owners.length = 2 && requireConfirmations = 2
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);

        vm.prank(owner);
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
        address owner = owners[0];
        address oldOwner = owners[1];
        uint256 txIndex = 0;
        bytes memory _data = abi.encodeWithSelector(MultiSigWallet.submitRemoveOwner.selector, oldOwner);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner, txIndex, address(multiSigWallet), 0, _data);
        multiSigWallet.submitRemoveOwner(oldOwner);

        (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations) = multiSigWallet.transactions(txIndex);
        assertEq(to, address(multiSigWallet));
        assertEq(value, 0);
        assertEq(data, _data);
        assertEq(executed, false);
        assertEq(numConfirmations, 0);
    }

    function testRevert_UnsigningNonExistentTx() public {
        address owner = owners[0];
        uint256 txIndex = 0;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxDoesNotExist.selector));
        multiSigWallet.unsignTransaction(txIndex);
    }

    function testRevert_UnsigningExecutedTx() public {
        address owner = owners[0];
        uint256 txIndex = 0;

        setupTxWithTwoSignatures(); // Set the first transaction with 0 index
        vm.deal(address(multiSigWallet), 1 ether);
        vm.prank(owner);
        multiSigWallet.executeTransaction(txIndex);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxAlreadyExecuted.selector));
        multiSigWallet.unsignTransaction(txIndex);
    }

    function testRevert_UnsigningNotSignedTx() public {
        address owner = owners[0];
        uint256 txIndex = 0;

        // Create transaction but don't sign it
        vm.prank(owner);
        multiSigWallet.setTransaction(address(0x1234), 1 wei, "");

        // Try to unsign without signing first
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_TxNotSigned.selector));
        multiSigWallet.unsignTransaction(txIndex);
    }

    function testRevert_NonOwnerUnsigningTx() public {
        address nonOwner = address(0x1234);
        uint256 txIndex = 0;

        setupTxWithTwoSignatures(); // Set the first transaction with 0 index

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.MSW_NotOwner.selector));
        multiSigWallet.unsignTransaction(txIndex);
    }

    function test_UnsigningTx() public {
        address owner1 = owners[0];
        uint256 txIndex = 0;

        setupTxWithTwoSignatures(); // Set the first transaction with 0 index

        // Owner1 has signed transactions[0] before in setupTxWithTwoSignatures() function
        vm.prank(owner1);
        multiSigWallet.unsignTransaction(txIndex);

        bool isConfirmed = multiSigWallet.isConfirmed(owner1, txIndex);
        assertEq(isConfirmed, false);

        (,,,, uint256 numConfirmations) = multiSigWallet.transactions(0);
        assertEq(numConfirmations, 1); // Before unsigning, this Tx had 2 signs and now have 1
    }

    function testEmit_SubmitTransaction() public {
        address owner = owners[0];
        uint256 txIndex = 0;
        address target = address(0x1234);
        uint256 value = 1 wei;
        bytes memory data = "0x123";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner, txIndex, target, value, data);
        multiSigWallet.setTransaction(target, value, data);
    }

    function testEmit_ConfirmTransaction() public {
        address owner = owners[0];
        uint256 txIndex = 0;
        address target = address(0x1234);
        uint256 value = 1 wei;
        bytes memory data = "0x123";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmited(owner, txIndex, target, value, data);
        multiSigWallet.setTransaction(target, value, data);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit TransactionConfirmed(owner, txIndex);
        multiSigWallet.signTransaction(txIndex);
    }

    function testEmit_RevokeConfirmation() public {
        address owner = owners[0];
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit ConfirmationRevoked(owner, txIndex);
        multiSigWallet.unsignTransaction(txIndex);
    }

    function testEmit_ExecuteTransaction() public {
        address owner = owners[0];
        uint256 txIndex = 0;

        setupTxWithTwoSignatures();
        vm.deal(address(multiSigWallet), 1 ether);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit TransactionExecuted(owner, txIndex);
        multiSigWallet.executeTransaction(txIndex);
    }
}
