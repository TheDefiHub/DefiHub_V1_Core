// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;


interface ITokenAsAServiceV1Factory {
    function createNewToken(
        address _tokenOwner,
        address _factory,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint _initialSupply,
        uint _initialOwnerShare,
        bool _initialSupplyIsMaxSupply
    ) external returns (address);
}