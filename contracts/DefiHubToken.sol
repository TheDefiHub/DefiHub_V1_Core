// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import '@openzeppelin/contracts/utils/Address.sol';
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

contract DefiHubToken is ERC20, ERC20Detailed {
    using Address for address;

    address public governance;
    uint maxSupply = 10000000 // 10 Million max supply

    constructor () public ERC20Detailed("DefiHub", "DFH", 18) {
        governance = msg.sender;
        minters[msg.sender] = true;
    }

    function mint(address account, uint amount) public {
        require(minters[msg.sender], "!minter");
        require(totalSupply() <= maxSupply, "!minter");
        _mint(account, amount);
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function addMinter(address _minter) public {
        require(msg.sender == governance, "!governance");
        minters[_minter] = true;
    }

    function removeMinter(address _minter) public {
        require(msg.sender == governance, "!governance");
        minters[_minter] = false;
    }
}