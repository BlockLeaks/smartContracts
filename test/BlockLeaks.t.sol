// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/BlockLeaks.sol";

bytes16 constant GROUP_ID = 0x3c0e4da0cf926dfbf5e31aa66f77199b;
bytes16 constant GROUP_ID_2 = 0x3c0e4da0cf926dfbf5e31aa66f77199c;

interface IBlockLeaks {
    function messageCount() external view returns (uint256);
    function APP_ID() external view returns (bytes16);
}

contract BlockLeaksTest is Test {
    address MULTISIG = vm.addr(1);
    address LEAKER = vm.addr(2);
    address TREASURY = vm.addr(3);

    BlockLeaks bl = new BlockLeaks(payable(MULTISIG));

    function setUp() public {
        vm.deal(LEAKER, 1 ether);
    }

    function testSetup() public view {
        uint256 msgCount = bl.messageCount();

        require(msgCount == 0, " Message not initiated");
        require(bl.APP_ID() == bytes16(0x3c0e4da0cf926dfbf5e31aa66f77199b), " Noot good APP_ID");
    }
}
