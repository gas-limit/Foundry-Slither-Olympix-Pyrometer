// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AuthorizedCounter is Ownable {
    uint256 private count;

    event CountChanged(uint256 newCount);

    constructor() Ownable(msg.sender) {
        count = 0;
    }

    function increment() public onlyOwner {
        count += 1;
        emit CountChanged(count);
    }

    function decrement() public onlyOwner {
        count -= 1;
        emit CountChanged(count);
    }

    function getCount() public view returns (uint) {
        return count;
    }
}
