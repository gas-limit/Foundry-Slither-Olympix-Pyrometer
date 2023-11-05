// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {AuthorizedCounter} from "../src/AuthorizedCounter.sol";

contract LibraryTest is Test {
    AuthorizedCounter public AuthorizedCounter_;

    function setUp() public {
        AuthorizedCounter_ = new AuthorizedCounter();
    }

    function test_StorageSpoof() public {
        vm.store(
            address(AuthorizedCounter_),
            bytes32(uint256(1)),
            bytes32(uint256(100))
        );
        console2.log(AuthorizedCounter_.getCount());
        assertEq((AuthorizedCounter_.getCount()), uint256(100));
    }

}