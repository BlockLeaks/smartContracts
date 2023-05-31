// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "sismo-connect-solidity/SismoLib.sol";

struct Leak {
    Status status;
    uint8 minimumRank;
    uint32 criticalRatioX10;
    uint32 timestamp;
    int64 trustIndex;
    address messageOwner;
    string title;
    string description;
    string uri;
    bytes16 groupId;
    uint128 stakedAmount;
    bytes32 messageId;
}

enum Status {
    UNEVALUATED,
    UNVERIFIED,
    VALIDATED,
    FAKE_LEAK
}

interface BlockLeaksVault {
    function mint(address account, uint256 amount) external;
}

contract BlockLeaks is
    ReentrancyGuard // is SismoConnect {
{
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using SafeERC20 for IERC20;

    bytes16 public constant APP_ID = 0x3c0e4da0cf926dfbf5e31aa66f77199b;

    EnumerableSet.Bytes32Set private groupIds;

    address payable public multisig;
    uint256 public messageCount;
    uint256 public minStakePrice;
    BlockLeaksVault public grantVault;

    mapping(bytes32 => Leak) private messages;
    mapping(address => int64) public trustScore;
    mapping(address => uint256) public creditNote;
    mapping(bytes16 => EnumerableSet.Bytes32Set) private messagesByGroupId;
    mapping(address => EnumerableSet.Bytes32Set) private messageBySender;

    event LeaksAdded(uint256 indexed id, bytes32 indexed groupId, string title, uint256 no);
    event LeaksCancelled(Leak);

    modifier onlyMultisig() {
        require(msg.sender == multisig, "Not multisig");
        _;
    }

    receive() external payable {
        multisig.transfer(msg.value);
    }

    constructor(
        address payable _multisig,
        address _grantVault // SismoConnect(APP_ID)
    ) {
        multisig = _multisig;
        grantVault = BlockLeaksVault(_grantVault);
    }

    function changeMultisig(address payable _newMultisig) public onlyMultisig {
        multisig = _newMultisig;
    }

    function newminStakePrice(uint256 _newStake) public onlyMultisig {
        minStakePrice = _newStake;
    }

    function withdrawERC20(IERC20 token) external onlyMultisig {
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    function withdrawToMsgOwner(bytes32[] memory _msgIds) public onlyMultisig {
        unchecked {
            for (uint256 i = 0; i < _msgIds.length; i++) {
                withdrawToMsgOwner(_msgIds[i]);
            }
        }
    }

    function encodeLeak(string calldata title, string calldata content, string calldata uri)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(title, content, uri));
    }

    function withdrawSomeToMultisig(bytes32[] memory _msgIds) public onlyMultisig {
        unchecked {
            for (uint256 i = 0; i < _msgIds.length; i++) {
                withdrawToMultisig(_msgIds[i]);
            }
        }
    }

    function withdrawToMsgOwner(bytes32 _msgId) public onlyMultisig {
        Leak memory _msgInfo = messages[_msgId];
        require(_msgInfo.status == Status.UNVERIFIED, "Already withdrawn");
        _msgInfo.status = Status.VALIDATED;

        grantVault.mint(
            _msgInfo.messageOwner, _msgInfo.criticalRatioX10 * _msgInfo.stakedAmount / 10 - _msgInfo.stakedAmount
        );

        (bool success,) = payable(_msgInfo.messageOwner).call{value: _msgInfo.stakedAmount}("");
        require(success, "Transfer Error");

        trustScore[_msgInfo.messageOwner] += int64(uint64(_msgInfo.criticalRatioX10));
    }

    function withdrawToMultisig(bytes32 _msgId) public onlyMultisig {
        Leak memory _msgInfo = messages[_msgId];

        require(_msgInfo.status == Status.UNVERIFIED, "Already withdrawn");
        _msgInfo.status = Status.FAKE_LEAK;
        (bool success,) = payable(multisig).call{value: _msgInfo.stakedAmount}("");
        require(success, "Transfer Error");
        trustScore[_msgInfo.messageOwner] -= int64(uint64(_msgInfo.criticalRatioX10));
    }

    function setCreditNote(int256 amount, address creditor) public onlyMultisig {
        // require()
        uint256 note = creditNote[creditor];
        creditNote[creditor] = amount < 0 ? note - uint256(-amount) : note + uint256(amount); // OverFloaw already handled by sol 8^;
    }

    function evaluateLeak(uint32[] calldata ratios, bytes32[] calldata messagesId) external onlyMultisig {
        uint256 len = ratios.length;
        require(messagesId.length == len, "len mismatching");
        unchecked {
            for (uint256 i = 0; i < len;) {
                Leak memory msg_ = messages[messagesId[i]];
                uint256 status = uint256(msg_.status);
                require(status <= uint256(Status.UNVERIFIED), "Not now");
                if (status == uint256(Status.UNEVALUATED)) msg_.status = Status.UNVERIFIED;
                msg_.criticalRatioX10 = ratios[i];
                messages[messagesId[i]] = msg_;
                ++i;
            }
        }
    }

    function writeLeak(
        // bytes memory response,
        bytes16 _groupId,
        uint8 _value,
        string calldata _title,
        string calldata _description,
        string calldata _uri
    ) public payable returns (bytes32 id) {
        require(minStakePrice <= msg.value, "Need to stake more");
        uint32 actualCount = uint32(messageCount);
        id = encodeLeak(_title, _description, _uri);
        require(messages[id].messageId == 0, "Leak already exists");
        // verify({
        //     responseBytes: response,
        //     claim: buildClaim({groupId: _groupId, value: _value}),
        //     signature: buildSignature({message: abi.encode(msg.sender)})
        // });

        Leak memory message_ = Leak(
            Status.UNEVALUATED,
            _value,
            10,
            uint32(block.timestamp),
            trustScore[msg.sender],
            msg.sender,
            _title,
            _description,
            _uri,
            _groupId,
            uint128(msg.value),
            id
        );
        messages[id] = message_;
        if (!groupIds.contains(_groupId)) addrGroup(_groupId);

        addLeak(id, _groupId, msg.sender);

        emit LeaksAdded(actualCount, _groupId, _title, messageCount);
    }

    function addrGroup(bytes16 _groupId) internal {
        groupIds.add(_groupId);
    }

    function cancelLeak(bytes16 _groupId, bytes32 leakId, address to) public {
        Leak memory leak = messages[leakId];
        require(uint256(leak.status) <= uint256(Status.UNVERIFIED), "Not authorized : unverified");
        require(leak.messageOwner == msg.sender, "Not authorized : not owner");
        (bool success,) = payable(to).call{value: leak.stakedAmount}("");
        require(success, "Error in call function");
        deleteLeak(leakId, _groupId, msg.sender);
        emit LeaksCancelled(leak);
    }

    function deleteLeak(bytes32 leakId, bytes16 _groupId, address sender) internal {
        messagesByGroupId[_groupId].remove(leakId);
        messageBySender[sender].remove(leakId);
        --messageCount;
    }

    function addLeak(bytes32 leakId, bytes16 _groupId, address sender) internal {
        messagesByGroupId[_groupId].add(leakId);
        messageBySender[sender].add(leakId);
        ++messageCount;
    }

    function getGroupIds() public view returns (bytes16[] memory) {
        uint256 count = groupIds.length();
        bytes16[] memory ids = new bytes16[](count);
        for (uint256 i = 0; i < count; i++) {
            ids[i] = bytes16(groupIds.at(i));
        }
        return ids;
    }

    function getLeaksIDByGroupId(bytes16 _groupId) external view returns (bytes32[] memory) {
        return messagesByGroupId[_groupId].values();
    }

    function getLeaksIDBySender(address sender) external view returns (bytes32[] memory) {
        return messageBySender[sender].values();
    }

    function getLeak(bytes32 id) external view returns (Leak memory) {
        return messages[id];
    }

    function getLeaks(bytes32[] calldata ids) external view returns (Leak[] memory) {
        uint256 len = ids.length;
        Leak[] memory messages_ = new Leak[](len);
        unchecked {
            for (uint256 i = 0; i < len;) {
                messages_[i] = messages[ids[i]];
                ++i;
            }
        }
        return messages_;
    }

    function getAllLeaksId() public view returns (bytes32[] memory total) {
        total = new bytes32[](messageCount);
        bytes32[] memory groups = groupIds.values();
        uint256 numberOfGroups = groups.length;
        uint256 k;
        for (uint256 i = 0; i < numberOfGroups;) {
            bytes32[] memory batchleak = messagesByGroupId[bytes16(groups[i])].values();
            uint256 groupLen = batchleak.length;
            for (uint256 j = 0; j < groupLen;) {
                total[k++] = batchleak[j];
                ++j;
            }
            ++i;
        }
    }
}
