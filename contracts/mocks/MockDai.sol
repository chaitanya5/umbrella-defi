//SPDX-License-Identifier: MIT

pragma solidity ^0.7.5;

import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDai is ERC20 {
    constructor () ERC20('MockDai', 'MDAI') {}

    // For mocking purposes
    function faucet(uint256 _amount) external {
        _mint(msg.sender, _amount);
    }
}