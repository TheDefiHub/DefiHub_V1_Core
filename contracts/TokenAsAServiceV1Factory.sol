// SPDX-License-Identifier: MIT

pragma solidity ^0.7.1;

import "./TokenAsAServiceV1.sol";
import "./ITokenAsAServiceV1Factory.sol";

contract TokenAsAServiceV1Factory is ITokenAsAServiceV1Factory {
    function createNewToken(
        address _tokenOwner,
        address _factory,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint _initialSupply,
        uint _initialOwnerShare,
        bool _initialSupplyIsMaxSupply
    ) external override returns (address) {
        TokenAsAServiceV1 token = new TokenAsAServiceV1(
            _tokenOwner,
            _factory,
            _tokenName,
            _tokenSymbol,
            _initialSupply,
            _initialOwnerShare,
            _initialSupplyIsMaxSupply
        );

        return address(token);
    }
}