// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "sismo-connect-solidity/SismoLib.sol";

contract LeaksToken is ReentrancyGuard, ERC20Burnable {
    address payable public multisig;
    address public blockLeaksContract;

    mapping(address => uint256) contributed;

    constructor(address payable multisig_, address blockLeaksContract_) ERC20("BlockLeaks Token", "LEAKS") {
        multisig = multisig_;
        blockLeaksContract = blockLeaksContract_;
    }

    receive() external payable nonReentrant {
        uint256 diff = backingDifference();
        if (diff < msg.value) multisig.transfer(msg.value - diff);
    }

    function mint(address account, uint256 amount) external {
        require(_msgSender() == blockLeaksContract, "Only BlockLeaks Contract can mint token");
        _mint(account, amount);
    }

    function maxClaimable(address sender) public view returns (uint256 max) {
        return address(this).balance > balanceOf(sender) ? balanceOf(sender) : address(this).balance;
    }

    function claimDai(uint256 amount) external nonReentrant {
        address sender = _msgSender();
        require(maxClaimable(sender) >= amount, " Claim more than  possible");
        _burn(sender, amount);
        payable(sender).transfer(amount);
    }

    function claimMaxDai() external nonReentrant {
        address sender = _msgSender();
        uint256 maxClaim = maxClaimable(sender);
        require(maxClaim > 0, "Claim error");
        _burn(sender, maxClaim);
        payable(sender).transfer(maxClaim);
    }

    function isVaultFullfilled() external view returns (bool) {
        return address(this).balance < totalSupply();
    }

    function backingDifference() public view returns (uint256) {
        return totalSupply() - address(this).balance;
    }
}
