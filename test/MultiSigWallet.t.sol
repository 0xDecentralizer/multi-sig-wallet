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
        vm.expectRevert("Onwers not uniqe!");
        multiSigWallet = new MultiSigWallet(owners, requireConfirmations);

    }
}