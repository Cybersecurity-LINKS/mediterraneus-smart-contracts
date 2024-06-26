// SPDX-FileCopyrightText: 2024 Fondazione LINKS
//
// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Identity is Ownable {
    
    struct VCStatus {
        address credentialOwner; // EOA/address of the user
        uint256 issuanceDate;
        uint256 expirationDate;
        bool revoked;
    }

    uint256 private _free_vc_id = 1;
    // credential id to VCStatus mapping
    mapping(uint256 => VCStatus) private _vcStatuses;
    // address to credential id (assume 1 vc for each address)
    mapping(address => uint256) private _ids;

    event VC_added(uint256 vc_id, address extracted, uint256 expiration, uint256 block);
    event VC_Revoked(uint256 vc_id);

    constructor() {}

    function getFreeVCid() external view onlyOwner returns(uint256) {
       return _free_vc_id;
    }

    function addUser (
        uint256 _vc_id,
        uint256 _expirationDate,
        uint256 _issuanceDate,
        bytes calldata _walletSignature,
        bytes calldata _challenge
    ) external onlyOwner {
        require(_vc_id >= 0, "VC identitifier must be greater than 0");
        require(_vc_id <= _free_vc_id, "Received VC id is invalid");
        require(_vcStatuses[_vc_id].credentialOwner == address(0), "VC has already a VC owner: request already stored, remember to activate it");
        // If 'now' > expiration ==> expired
        require(block.timestamp < _expirationDate, "Got invalid/expired expiration date");
        require(_issuanceDate <= block.timestamp, "Issuance date is in the future");

        address extractedAddress = extractSourceFromSignature(_challenge, _walletSignature);
        require(extractedAddress != address(0), "Invalid Extracted address");
        uint256 id = _ids[extractedAddress];
        if(id != 0 && !_vcStatuses[id].revoked) { // holder already has a vc
            // let the same holder have a second VC only if its previous VC is revoked.
            revert("Trying to issue a second VC to the same holder having the first VC still not revoked");
        }

        // Initially the VC is not enabled ==> status == false.
        _vcStatuses[_vc_id] = VCStatus(extractedAddress, _issuanceDate, _expirationDate, false);

        // update free vc id
        _free_vc_id+=1;
        // update addr to vcid mapping, in case it substitues the old value of ID if the holder has a revoked VC and tries to have a new valid VC
        _ids[extractedAddress] = _vc_id;

        emit VC_added(_vc_id, _vcStatuses[_vc_id].credentialOwner, _vcStatuses[_vc_id].expirationDate, block.timestamp);
    }

    function revokeVC(uint256 _vc_id) public onlyOwner {
        VCStatus storage vc = _vcStatuses[_vc_id];
        require(vc.credentialOwner != address(0), "Revoke: VC associated to the given vc_id does not exist/is invalid");
        require(!_isRevoked(_vc_id), "VC is already revoked");
        vc.revoked = true;
        emit VC_Revoked(_vc_id);
    }

    // TODO: define this in a library Smart Contract (almost common to ERC721Base.sol)
    function extractSourceFromSignature(bytes calldata _challenge, bytes calldata _signature) internal pure returns(address) {
        bytes32 signedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", 
            Strings.toString(_challenge.length), 
            _challenge)
        );
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(signedHash, v, r, s);
    }

    // TODO: define this in a library Smart Contract (almost common to ERC721Base.sol)
    // https://solidity-by-example.org/signature/
    function splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature
            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature
            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
    }

    
    function _hasExpired(uint256 _credentialId) internal view returns(bool) {
        require(_credentialId > 0, "Credential id not valid");
        // returns true if expired
        return block.timestamp > _vcStatuses[_credentialId].expirationDate;
    }

    function _isRevoked(uint256 _credentialId) internal view returns(bool) {
        require(_credentialId > 0, "Credential id not valid");
        return _vcStatuses[_credentialId].revoked;
    }
    
    function isRevoked(uint256 _credentialId) external view returns(bool) {
        require(_credentialId > 0, "Credential id not valid");
        return _vcStatuses[_credentialId].revoked;
    }

    function isRevokedByAddr(address credentialHolder) external view returns(bool) {
        require(_ids[credentialHolder] > 0, "Holder does not own a credential");
        return _isRevoked(_ids[credentialHolder]);
    }
    
    function hasValidStatus(address credentialHolder) external view returns(bool) {
        require(_ids[credentialHolder] > 0, "Holder does not own a credential");
        require(!_hasExpired(_ids[credentialHolder]), "Credential has expired");
        require(!_isRevoked(_ids[credentialHolder]), "Credential is revoked");
        return true;
    }   

}