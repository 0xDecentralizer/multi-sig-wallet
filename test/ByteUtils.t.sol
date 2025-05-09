// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BytesUtils.sol";

contract BytesUtilsTest is Test {
    using BytesUtils for bytes;

    function testSliceBytes() public pure {
        bytes memory original = hex"0102030405";
        bytes memory expected = hex"030405";

        bytes memory sliced = original.sliceBytes(2);
        assertEq(sliced, expected);
    }

    function testSliceStartAtZero() public pure {
        bytes memory original = hex"0a0b0c";
        bytes memory expected = hex"0a0b0c";

        bytes memory sliced = original.sliceBytes(0);
        assertEq(sliced, expected);
    }

    function testSliceFullLength() public pure {
        bytes memory original = hex"112233";
        bytes memory expected = "";

        bytes memory sliced = original.sliceBytes(3);
        assertEq(sliced, expected);
    }

    function testSliceOutOfBoundsReverts() public {
        bytes memory original = hex"0102";
        vm.expectRevert(BytesUtils.MSW_InvalidSliceStart.selector);
        this.callSliceOutOfBounds(original);
    }

    function callSliceOutOfBounds(bytes memory data) external pure {
        data.sliceBytes(3);
    }
}
