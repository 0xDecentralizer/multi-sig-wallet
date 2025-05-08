// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library BytesUtils {
    error MSW_InvalidSliceStart();

    function sliceBytes(bytes memory data, uint256 start) internal pure returns (bytes memory) {
        if (start > data.length) revert MSW_InvalidSliceStart();

        bytes memory result = new bytes(data.length - start);
        for (uint256 i = start; i < data.length; i++) {
            result[i - start] = data[i];
        }
        return result;
    }
}
