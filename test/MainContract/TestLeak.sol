// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../BlockLeaks.t.sol";

contract TestLeak is BlockLeaksTest {
    string title = "TitleTest";
    string content = "ContentTest";
    string link = "ipfs://TestLink";

    function testAddingLeak() public {
        uint256 balBefor = LEAKER.balance;
        vm.prank(LEAKER);
        bl.writeLeak{value: 1 ether}(GROUP_ID, title, content, link);
        require(bl.messageCount() == 1, "Leak not counted  in messageCount");
        uint256 balAfter = LEAKER.balance;
        require(balBefor - balAfter == 1 ether, "Stake amount not counted");
    }

    function testCancelLeak() public {
        testAddingLeak();
        uint256 balBefor = LEAKER.balance;
        bytes32 leakId = bl.getLeaksIDBySender(LEAKER)[0];
        vm.prank(LEAKER);
        bl.cancelLeak(GROUP_ID, leakId, LEAKER);
        uint256 balAfter = LEAKER.balance;

        require(bl.messageCount() == 0, "Cancel Leak not counted in messageCount");
        require(balAfter - balBefor == 1 ether, "Stake amount not returned");
    }

    function testEvaluateLeak() public {
        testAddingLeak();
        uint32[] memory ratios = new uint32[](1);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bl.getLeaksIDBySender(LEAKER)[0];
        ratios[0] = 20;
        vm.prank(MULTISIG);
        bl.evaluateLeak(ratios, ids);
        Leak memory leak_ = bl.getLeak(ids[0]);
        require(leak_.criticalRatioX10 == 20, "CriticalRatio not well set");
        require(leak_.status == Status.UNVERIFIED, "Leak status not well set");
    }

    function testLeakVerified() public {
        testEvaluateLeak();
        uint256 balOwnerMsgBefore = LEAKER.balance;
        vm.startPrank(MULTISIG);
        bl.withdrawToMsgOwner(bl.getLeaksIDBySender(LEAKER)[0]);

        uint256 balOwnerMsgAfter = LEAKER.balance;
        require(balOwnerMsgAfter - balOwnerMsgBefore == 1 ether, "Withdrawn value error");
        require(bl.creditNote(LEAKER) == 1 ether, "Credit note not well set");
        require(bl.trustScore(LEAKER) == 20, "TrustScore not well set");
        vm.stopPrank();
    }

    function testFakeLeak() public {
        testEvaluateLeak();
        uint256 balOwnerMsgBefore = LEAKER.balance;
        uint256 balMsigMsgBefore = MULTISIG.balance;
        vm.startPrank(MULTISIG);
        bl.withdrawToMultisig(bl.getLeaksIDBySender(LEAKER)[0]);

        uint256 balOwnerMsgAfter = LEAKER.balance;
        uint256 balMsigMsgAfter = MULTISIG.balance;
        require(balMsigMsgAfter - balMsigMsgBefore == 1 ether, "Withdrawn value error to msig");
        require(balOwnerMsgAfter == balOwnerMsgBefore, "Withdrawn value error to msig");
        require(bl.creditNote(LEAKER) == 0, "Credit note not well set");
        require(bl.trustScore(LEAKER) == -20, "TrustScore not well set");
        vm.stopPrank();
    }
}
