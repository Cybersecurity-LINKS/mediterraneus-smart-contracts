// SPDX-FileCopyrightText: 2024 Fondazione LINKS
//
// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.18;

/**
 * @dev Required interface of an ERC20 compliant contract.
 */
interface IAccessTokenBase {

    function initialize(
        string memory name_,
        string memory symbol_,
        address owner_, // minter = DT owner = NFT owner
        address erc721address_,
        address router_,
        address factory_,
        uint256 maxSupply_
    ) external returns (bool);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function isMinter(address isminter) external view returns(bool);
    function mint(address to, uint256 amount) external;
    function balanceOf(address caller) external view returns(uint256);
    function allowance(address owner, address spender) external view returns(uint256);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    
    function createFixedRate(
        address fixedRateAddress_,
        uint256 fixedrate_,
        uint256 giveMintPerm_toExchange
    ) external returns (bytes32 exchangeID);

    function allInOne_approve(
        address owner, 
        address spender, 
        uint256 amount
    ) external;

    function setAccess(address accessAddress) external;
    function canAccess(address owner, address accessAddress) external view returns(bool);
}