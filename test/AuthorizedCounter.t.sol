// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {AuthorizedCounter} from "../src/AuthorizedCounter.sol";

contract AuthorizedCounterTest is Test {
    AuthorizedCounter public counter;
    event CountChanged(uint256 newCount);

    function setUp() public {
        counter = new AuthorizedCounter();
    }

    // called by owner
    function test_OwnerIncrement() public {
        counter.increment();
    }

    // called by non-owner
    function testFail_NonOwnerIncrement() public {
        vm.prank(address(0));
        counter.increment();
    }
    
    // test for correct event emission
    function test_ExpectEmittedEvent() public {
        vm.expectEmit(true, false, false, false);
        uint256 count = counter.getCount();
        emit CountChanged(count);
        counter.increment();
    }

}