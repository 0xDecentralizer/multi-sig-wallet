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

    function setUp() public {
        owners = new address[](3);
        owners[0] = address(0x1);
        owners[1] = address(0x2);
        owners[2] = address(0x3);
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    function test_emptyOwners() public {
        owners = new address[](0);
        vm.expectRevert("Owners list can't be empty!");
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    function test_ownersPassed() public view {
        assertEq(owners.length, 3);
    }

    function test_requireConfirmations() public {
        owners.pop();
        owners.pop();
        vm.expectRevert("Confirmations can't be greater than number of owners");
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    function test_duplicatedOwners() public {
        owners.push(address(0x1));
        vm.expectRevert("Duplicate Owner not accepted");
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);

    }

    function testRevert_ownercannotBeZeroAddress() public {
        owners.push(address(0));
        vm.expectRevert("Owner can't be 0 address");
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);
    }

    function testRevert_NonOwnerCannotCallSetTransaction() public {
        address nonOwner = address (0xDe);
        vm.label(nonOwner, "NonOwner");

        vm.prank(nonOwner);
        vm.expectRevert("Not an owner!");

        multiSigWallet.setTransaction(address(0x111), 1, "");
    }

    function test_setTransactionByOwner() public {
        address target = address(0xDe);
        uint256 value = 1 ether;
        bytes32 data = "0x123";

        vm.prank(owners[0]);
        multiSigWallet.setTransaction(target, value, data);

        // Validate state
        (address to, uint256 txValue, bytes32 txData, bool executed, uint256 numConfirmations) = multiSigWallet.transactions(0);

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
            vm.expectRevert("There is no such TX!");
            multiSigWallet.signTransaction(txIndex);
        }

        // After implementig executeTransaction() function, we can rewrite this test =]
        function blob_testRevert_AnExecutedTxCannotBeSign() public {
            // Simulate a transaction
            address owner = owners[0];
            vm.prank(owner);
            multiSigWallet.setTransaction(address(0x1234), 1 wei, "");
            uint256 txIndex = 0;

            vm.prank(owner);
            // multiSigWallet.executeTransaction(txIndex);

            vm.label(owner, "Owner");

            vm.prank(owner);
            vm.expectRevert("This TX has been executed!");
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
            vm.expectRevert("You signed this TX before!");
            multiSigWallet.signTransaction(txIndex);

        }

        function test_signTransactionByOwdner() public {
            address owner = owners[0];
            uint256 txIndex = 0;

            vm.prank(owner);
            multiSigWallet.setTransaction(address(0x1234), 1 wei, "");

            vm.prank(owner);
            multiSigWallet.signTransaction(txIndex);

            (, , , , uint256 numConfirmations) = multiSigWallet.transactions(0);

            assertEq(numConfirmations, 1);
            
            bool isConfirmed = multiSigWallet.isConfirmed(owner, txIndex);
            assertEq(isConfirmed, true);
        }
}