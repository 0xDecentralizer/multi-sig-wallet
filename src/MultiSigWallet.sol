// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract MultiSigWallet {
    
    address[] private owners;
    uint8 requireVerifications;
    
    mapping(address => bool) isOwner;

    constructor(address [] memory _owners, uint8 _requireVerifications) {
        require(_owners.length != 0, "Owners list can't be empty!");
        require(
            _owners.length >= _requireVerifications,
            "Verifications can't be greater than number of owners"
        );
        for (uint i = 0; i < _owners.length; i++) {
            for (uint j = 1; j < _owners.length; j++) {
                if(_owners[i] == _owners[j]) {
                    revert("Onwers not uniqe!");
                }
            }
        }

        owners = _owners;
        requireVerifications = _requireVerifications;
    }
}