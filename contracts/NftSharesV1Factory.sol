// SPDX-License-Identifier: MIT

pragma solidity ^0.7.1;

import "./NftSharesV1.sol";

contract NftSharesV1Factory {
    function createNewNftSharesSale(
        string memory _shareName, 
        string memory _shareSymbol, 
        uint _nftId,
        address _nftTokenAddress, 
        address _tokenToBuyWith,
        uint _initialSharePrice,
        uint _totalAmountOfNftShares,
        uint _durationInDays
    ) external returns (NftSharesV1) {
        return new NftSharesV1(
            _shareName, 
            _shareSymbol, 
            _nftId, 
            _nftTokenAddress, 
            _tokenToBuyWith, 
            _initialSharePrice, 
            _totalAmountOfNftShares, 
            _durationInDays,
            msg.sender
        );
    }
}