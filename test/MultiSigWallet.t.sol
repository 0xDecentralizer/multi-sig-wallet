// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

contract MultiSigWalletTest is Test {
    address[] owners = [address(0x1), address(0x2), address(0x3)];

    function setUp() public {
        MultiSigWallet multiSigWallet = new MultiSigWallet(
            owners,
            2
        );
        
    }

    function test_ownersPassed() public view {
        assertEq(owners.length, 3);
    }

    
}