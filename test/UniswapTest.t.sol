// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "../src/UniswapV2Liquidity.sol";

contract UniswapTest is Test {
    UniswapV2AddLiquidity public UniswapV2AddLiquidity_;
    

    IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 PAIR = IERC20(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852);

    uint256 USDTAmount = 156091 ether;
    uint256 WETHAmount = 100 ether;

    using SafeERC20 for IERC20;

    function setUp() public {
        // instantiate
        UniswapV2AddLiquidity_ = new UniswapV2AddLiquidity();

        // give tokens to this test contract using 'deal' cheatcode
        deal(address(USDT), address(this), USDTAmount);
        deal(address(WETH), address(this), WETHAmount);

    }

    function test_Deposit() public {
        // approve this test contract to deposit into 
        // UniswapV2AddLiquidity
        USDT.safeIncreaseAllowance(address(UniswapV2AddLiquidity_), USDTAmount);
        WETH.safeIncreaseAllowance(address(UniswapV2AddLiquidity_), WETHAmount);

        UniswapV2AddLiquidity_.addLiquidity(address(USDT), address(WETH), USDTAmount, WETHAmount);

        // get balance of LP tokens
        // console2.log(PAIR.balanceOf(address(this)));
    }

}