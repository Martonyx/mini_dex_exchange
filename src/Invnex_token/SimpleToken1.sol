// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SimpleCoin1 is ERC20 {

    constructor() ERC20("SimpleCoin", "SCN") {}

    function mint(address to, uint amount) public {
        _mint(to, amount);
    }
}