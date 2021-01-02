// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import '@openzeppelin/contracts/utils/Address.sol';
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DefiHubToken is ERC20 {
    using Address for address;

    address public governance;

    constructor (address _governance, uint _amount) ERC20("DefiHub", "DFH") {
        governance = _governance;
        _mint(_governance, _amount);
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
}