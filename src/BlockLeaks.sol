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

    EnumerableSet.Bytes32Set private groupsIdBytes32;

    address public multisig;
    uint256 public leaksAmount;
    uint256 public minStakePrice;
    BlockLeaksVault public grantVault;

    mapping(bytes32 => Leak) private messages;
    mapping(address => int64) public trustScore;
    mapping(bytes16 => EnumerableSet.Bytes32Set) private messagesByGroupId;
    mapping(address => EnumerableSet.Bytes32Set) private messageBySender;

    event LeakAdded(uint256 indexed id, bytes32 indexed groupId, string title, uint256 no);
    event LeakCancelled(Leak);

    error NotAuthorised(address sender, address admin);
    error ArraysLengthDiffers(uint256 x, uint256 y);
    error LeaksAlreadyExist();
    error BelowMinimumStake(uint256 value, uint256 minStakePrice);
    error WrongLeakStatus(Status current);
    error TransferError();
    error NotAContract(address sender);

    modifier onlyMultisig() {
        if (msg.sender != multisig) revert NotAuthorised(msg.sender, multisig);
        _;
    }

    constructor(
        address payable _multisig,
        address _grantVault // SismoConnect(APP_ID)
    ) {
        multisig = _multisig;
        grantVault = BlockLeaksVault(_grantVault);
    }

    receive() external payable {
        transfer(msg.value, multisig);
    }

    event MultisigUpdated(address oldMultisig, address newMultisig);
    event MinimumStakeAmountUpdated(uint256 oldMinimumStake, uint256 newMinimumStake);

    function changeMultisig(address _newMultisig) external onlyMultisig {
        if (_newMultisig.code.length == 0) revert NotAContract(_newMultisig);

        emit MultisigUpdated(multisig, _newMultisig);

        multisig = _newMultisig;
    }

    function setMinimumStakeAmount(uint256 _newStake) external onlyMultisig {
        emit MinimumStakeAmountUpdated(minStakePrice, _newStake);

        minStakePrice = _newStake;
    }

    function withdrawERC20(IERC20 token) external onlyMultisig {
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    function verifyLeaks(bytes32[] memory _msgIds, bool[] calldata isLeakValid) external onlyMultisig {
        unchecked {
            for (uint256 i = 0; i < _msgIds.length; i++) {
                if (isLeakValid[i]) withdrawToMsgOwner(_msgIds[i]);
                else withdrawToMultisig(_msgIds[i]);
            }
        }
    }

    function verifyLeak(bytes32 _msgIds, bool isLeakValid) external onlyMultisig {
        if (isLeakValid) withdrawToMsgOwner(_msgIds);
        else withdrawToMultisig(_msgIds);
    }

    function evaluateLeak(uint32[] calldata ratios, bytes32[] calldata messagesId) external onlyMultisig {
        uint256 len = ratios.length;
        if (messagesId.length != len) revert ArraysLengthDiffers(messagesId.length, len);
        unchecked {
            for (uint256 i = 0; i < len;) {
                Leak memory msg_ = messages[messagesId[i]];
                uint256 status = uint256(msg_.status);

                if (status > uint256(Status.UNVERIFIED)) revert WrongLeakStatus(Status(status));
                if (status == uint256(Status.UNEVALUATED)) msg_.status = Status.UNVERIFIED;

                msg_.criticalRatioX10 = ratios[i];
                messages[messagesId[i]] = msg_;
                ++i;
            }
        }
    }

    function cancelLeak(bytes16 _groupId, bytes32 leakId) external {
        Leak memory leak = messages[leakId];

        if (uint256(leak.status) > uint256(Status.UNVERIFIED)) revert WrongLeakStatus(leak.status);
        if (leak.messageOwner != msg.sender) revert NotAuthorised(msg.sender, leak.messageOwner);

        transfer(leak.stakedAmount, leak.messageOwner);

        deleteLeak(leakId, _groupId, msg.sender);

        emit LeakCancelled(leak);
    }

    function writeLeak(
        bytes memory response,
        bytes16 _groupId,
        uint8 _value,
        string calldata _title,
        string calldata _description,
        string calldata _uri
    ) external payable returns (bytes32 id) {
        if (minStakePrice > msg.value) revert BelowMinimumStake(msg.value, minStakePrice);
        uint32 actualCount = uint32(leaksAmount);
        id = encodeLeak(_title, _description, _uri);
        if (messages[id].messageId != 0) revert LeaksAlreadyExist();
        verify({
            responseBytes: response,
            claim: buildClaim({groupId: _groupId, value: _value}),
            signature: buildSignature({message: abi.encode(msg.sender)})
        });

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
        if (!groupsIdBytes32.contains(_groupId)) addrGroup(_groupId);

        addLeak(id, _groupId, msg.sender);

        emit LeakAdded(actualCount, _groupId, _title, leaksAmount);
    }

    function getGroupsId() external view returns (bytes16[] memory groupsId) {
        bytes32[] memory groups = groupsIdBytes32.values();
        uint256 groupsLen = groups.length;
        groupsId = new bytes16[](groupsLen);
        unchecked {
            for (uint256 i = 0; i < groupsLen;) {
                groupsId[i] = bytes16(groups[i]);
                ++i;
            }
        }
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

    function getAllLeaksId() external view returns (bytes32[] memory total) {
        total = new bytes32[](leaksAmount);
        bytes32[] memory groups = groupsIdBytes32.values();
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

    function encodeLeak(string calldata title, string calldata content, string calldata uri)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(title, content, uri));
    }

    function withdrawToMsgOwner(bytes32 _msgId) internal {
        Leak memory _msgInfo = messages[_msgId];
        if (_msgInfo.status != Status.UNVERIFIED) revert WrongLeakStatus(_msgInfo.status);
        _msgInfo.status = Status.VALIDATED;

        grantVault.mint(
            _msgInfo.messageOwner, _msgInfo.criticalRatioX10 * _msgInfo.stakedAmount / 10 - _msgInfo.stakedAmount
        );
        transfer(_msgInfo.stakedAmount, _msgInfo.messageOwner);

        trustScore[_msgInfo.messageOwner] += int64(uint64(_msgInfo.criticalRatioX10));
    }

    function transfer(uint256 amount, address receiver) internal {
        (bool success,) = payable(receiver).call{value: amount}("");
        if (!success) revert TransferError();
    }

    function withdrawToMultisig(bytes32 _msgId) internal {
        Leak memory _msgInfo = messages[_msgId];

        if (_msgInfo.status != Status.UNVERIFIED) revert WrongLeakStatus(_msgInfo.status);
        _msgInfo.status = Status.FAKE_LEAK;

        transfer(_msgInfo.stakedAmount, multisig);
        trustScore[_msgInfo.messageOwner] -= int64(uint64(_msgInfo.criticalRatioX10));
    }

    function addrGroup(bytes16 _groupId) internal {
        groupsIdBytes32.add(_groupId);
    }

    function deleteLeak(bytes32 leakId, bytes16 _groupId, address sender) internal {
        messagesByGroupId[_groupId].remove(leakId);
        messageBySender[sender].remove(leakId);
        --leaksAmount;
    }

    function addLeak(bytes32 leakId, bytes16 _groupId, address sender) internal {
        messagesByGroupId[_groupId].add(leakId);
        messageBySender[sender].add(leakId);
        ++leaksAmount;
    }
}
