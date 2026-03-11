// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockStablecoin} from "../src/mocks/MockStablecoin.sol";

contract MockStablecoinCoverageTest is Test {
    function testDecimalsAndMint() public {
        MockStablecoin token = new MockStablecoin("Mock USD", "mUSD", 6);

        assertEq(token.decimals(), 6);

        token.mint(address(this), 123_456_789);
        assertEq(token.balanceOf(address(this)), 123_456_789);
    }
}
