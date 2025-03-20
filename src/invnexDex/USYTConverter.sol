// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { USYT } from "../Invnex_token/USYT.sol";

contract USYTConverter is Pausable, Ownable, ReentrancyGuard {
    IERC20 public immutable usdc;
    USYT public immutable usyt;

    uint256 private constant SCALE_FACTOR = 10**12;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event OwnerWithdrawn(address indexed owner, uint256 amount);

    constructor(address _usdc, address _usyt) Ownable(msg.sender) {
        require(_usdc != address(0) && _usyt != address(0), "Invalid address");
        usdc = IERC20(_usdc);
        usyt = USYT(_usyt);
    }

    // Deposit USDC and receive equivalent USYT (scaled by 10**12)
    function deposit(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "zero amount");

        uint256 balanceBefore = usdc.balanceOf(address(this));
        require(usdc.transferFrom(msg.sender, address(this), amount), "USDC transfer failed");
        uint256 balanceAfter = usdc.balanceOf(address(this));
        require(balanceAfter - balanceBefore == amount, "Incorrect USDC amount received");

        uint256 usytAmount = amount * SCALE_FACTOR;
        usyt.mint(msg.sender, usytAmount);

        emit Deposited(msg.sender, amount);
    }

    // Burn USYT and withdraw equivalent USDC (scaled down by 10**12)
    function burnAndWithdraw(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "zero amount");

        uint256 usdcAmount = amount / SCALE_FACTOR;
        require(usdc.transfer(msg.sender, usdcAmount), "USDC transfer failed");
        usyt.burn(msg.sender, amount);

        emit Withdrawn(msg.sender, usdcAmount);
    }

    // Owner can withdraw deposited USDC
    function ownerWithdrawUSDC(uint256 amount) external onlyOwner {
        require(amount > 0, "zero amount");
        require(usdc.transfer(owner(), amount), "USDC transfer failed");
        emit OwnerWithdrawn(owner(), amount);
    }

    // Pause withdrawals in case of emergency
    function pause() external onlyOwner {
        _pause();
    }

    // Resume withdrawals
    function unpause() external onlyOwner {
        _unpause();
    }
}
