// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title KairosFaucet
 * @notice Minimal faucet for Kairos smart-wallets (ERC-4337). One-time claim per account.
 * Owner can pause, reset claims, update token/drip amount and withdraw funds.
 */
contract KairosFaucet is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/
    IERC20 public token; // ERC20 token distributed by faucet. May be address(0) for ETH-only.
    uint256 public dripAmount; // amount (token units or wei) per claim
    mapping(address => bool) public hasClaimed;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Claimed(address indexed account, uint256 amount);
    event ResetClaim(address indexed account);
    event TokenUpdated(address indexed token);
    event DripAmountUpdated(uint256 amount);
    event ERC20Withdrawn(IERC20 indexed token, address indexed to, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error KairosFaucet__AddressAlreadyClaimed();
    error KairosFaucet__InsufficientFaucetBalance();
    error KairosFaucet__TokenAddressIsNotSet();
    error KairosFaucet__ZeroAddress();
    error KairosFaucet__TransferFailed();

    /**
     * @param _token ERC20 token used by faucet. Pass IERC20(address(0)) to disable ERC20 claims.
     * @param _dripAmount amount per claim (token decimals or wei)
     */
    constructor(address _token, uint256 _dripAmount) Ownable(msg.sender) {
        token = IERC20(_token);
        dripAmount = _dripAmount;
    }

    /*//////////////////////////////////////////////////////////////
                               CLAIM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim ERC20 drip. One-time per address.
    function claim() external nonReentrant whenNotPaused {
        if (hasClaimed[msg.sender]) revert KairosFaucet__AddressAlreadyClaimed();
        if (address(token) == address(0)) revert KairosFaucet__TokenAddressIsNotSet();

        uint256 balance = token.balanceOf(address(this));
        if (dripAmount > balance) revert KairosFaucet__InsufficientFaucetBalance();

        // Mark before transfer to protect against reentrancy callback patterns (ERC777 etc.)
        hasClaimed[msg.sender] = true;

        token.safeTransfer(msg.sender, dripAmount);

        emit Claimed(msg.sender, dripAmount);
    }

    /// @notice Claim ETH drip. One-time per address.
    function claimETH() external nonReentrant whenNotPaused {
        if (hasClaimed[msg.sender]) revert KairosFaucet__AddressAlreadyClaimed();

        uint256 balance = address(this).balance;
        if (dripAmount > balance) revert KairosFaucet__InsufficientFaucetBalance();

        hasClaimed[msg.sender] = true;

        (bool success,) = msg.sender.call{value: dripAmount}("");
        if (!success) revert KairosFaucet__TransferFailed();

        emit Claimed(msg.sender, dripAmount);
    }

    function checkClaimStatus(address account) external view returns (bool) {
        return hasClaimed[account];
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reset claim flag for an account. Owner only.
    function resetClaim(address account) external onlyOwner {
        if (account == address(0)) revert KairosFaucet__ZeroAddress();
        if (hasClaimed[account]) {
            hasClaimed[account] = false;
            emit ResetClaim(account);
        }
    }

    /// @notice Update the ERC20 token used by faucet. Disallow zero address to avoid accidental disable.
    function updateToken(IERC20 _token) external onlyOwner {
        if (address(_token) == address(0)) revert KairosFaucet__ZeroAddress();
        token = _token;
        emit TokenUpdated(address(_token));
    }

    /// @notice Update the drip amount. Allow zero if owner explicitly wants to set to 0.
    function updateDripAmount(uint256 _amount) external onlyOwner {
        dripAmount = _amount;
        emit DripAmountUpdated(_amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Withdraw ERC20 from contract to `to`. Owner only.
    function withdrawERC20(IERC20 _token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert KairosFaucet__ZeroAddress();
        _token.safeTransfer(to, amount);
        emit ERC20Withdrawn(_token, to, amount);
    }

    /// @notice Withdraw ETH from contract to `to`. Owner only. Uses call to forward gas.
    function withdrawETH(address payable to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert KairosFaucet__ZeroAddress();
        (bool success,) = to.call{value: amount}("");
        if (!success) revert KairosFaucet__TransferFailed();
        emit ETHWithdrawn(to, amount);
    }

    receive() external payable {}

    fallback() external payable {}
}
