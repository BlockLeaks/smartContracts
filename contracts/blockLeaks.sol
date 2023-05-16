// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@sismo-core/sismo-connect-solidity/contracts/libs/SismoLib.sol";

contract BlockLeaks is SismoConnect {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct Message {
        uint id;
        address messageOwner;
        uint timestamp;
        bytes32 groupId;
        string title;
        string description;
        string cid;
        uint stakeAmount;
        bool approved;
        bool withdrawn;
    }

    bytes16 public constant APP_ID = 0x3c0e4da0cf926dfbf5e31aa66f77199b;
    uint public messageCount;
    mapping(uint => Message) public messages;
    EnumerableSet.Bytes32Set private groupIds;
    address public multisig;
    uint public stakePrice;
    
    event MessageWritten(uint indexed id, bytes32 indexed groupId, string title);

    modifier onlyMultisig() {
        require(msg.sender == multisig, "Not multisig");
        _;
    }

    constructor(address _multisig) SismoConnect(APP_ID) {
        multisig = _multisig;
    }

    function newMultisig(address _newMultisig) public onlyMultisig {
        multisig = _newMultisig;
    }

    function newStakePrice(uint _newStake) public onlyMultisig {
        stakePrice = _newStake;
    }

    function withdrawToMsgOwners(uint[] memory _msgIds) public onlyMultisig {
        for (uint i = 0; i < _msgIds.length; i++) {
            withdrawToMsgOwner(_msgIds[i]);
        }
    }

    function withdrawSomeToMultisig(uint[] memory _msgIds) public onlyMultisig {
        for (uint i = 0; i < _msgIds.length; i++) {
            withdrawToMultisig(_msgIds[i]);
        }
    }

    function withdrawToMsgOwner(uint _msgId) public onlyMultisig {
        bool success;
        require(messages[_msgId].withdrawn == false, "Already withdrawn");
        messages[_msgId].withdrawn = true;
        messages[_msgId].approved = true;
        (success, ) = messages[_msgId].messageOwner.call{value: messages[_msgId].stakeAmount}("");
        require(success, "Transfer Error");
    }

    function withdrawToMultisig(uint _msgId) public onlyMultisig {
        bool success;
        require(messages[_msgId].withdrawn == false, "Already withdrawn");
        messages[_msgId].withdrawn = true;
        messages[_msgId].approved = false;
        (success, ) = multisig.call{value: messages[_msgId].stakeAmount}("");
        require(success, "Transfer Error");
    }

    function writeMessage(bytes memory response, bytes16 _groupId, string memory _title, string memory _description, string memory _cid) public payable {
        require(stakePrice <= msg.value, "Need to stake more");
        uint actualCount = messageCount;
        messageCount++;
        uint timestamp = block.timestamp;

        verify({
            responseBytes: response,
            claim: buildClaim({groupId: _groupId}),
            signature: buildSignature({message: abi.encode(msg.sender)})
        });

        messages[actualCount] = Message(actualCount, msg.sender, timestamp, _groupId, _title, _description, _cid, msg.value, false, false);

        groupIds.add(_groupId);

        emit MessageWritten(actualCount, _groupId, _title);
    }

    function getGroupIds() public view returns (bytes16[] memory) {
        uint count = groupIds.length();
        bytes16[] memory ids = new bytes16[](count);
        for (uint i = 0; i < count; i++) {
            ids[i] = bytes16(groupIds.at(i));
        }
        return ids;
    }

    function getMessagesByGroupId(bytes16 _groupId) public view returns (Message[] memory) {
        uint count = messageCount;
        uint matchingCount = 0;

        for (uint i = 0; i < count; i++) {
            if (messages[i].groupId == _groupId) {
                matchingCount++;
            }
        }

        Message[] memory matchingMessages = new Message[](matchingCount);
        uint index = 0;

        for (uint i = 0; i < count; i++) {
            if (messages[i].groupId == _groupId) {
                matchingMessages[index] = messages[i];
                index++;
            }
        }

        return matchingMessages;
    }

    function getAllMessages() public view returns (Message[] memory) {
        Message[] memory AllMessages = new Message[](messageCount);
        for (uint i = 0; i < messageCount; i++) {
            AllMessages[i] = messages[i];
        }
        return AllMessages;
    }

}


