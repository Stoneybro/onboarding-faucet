// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/KairosFaucet.sol";

contract Rejector {
    // revert on any ETH receive
    receive() external payable {
        revert("reject");
    }
    fallback() external payable {
        revert("reject");
    }
}

contract KairosFaucetExtrasTest is Test {
    address deployer = address(0xABCD);

    function test_resetClaim_zero_address_reverts() public {
    vm.prank(deployer);
    KairosFaucet f = new KairosFaucet(address(0), 1 ether);

        vm.prank(deployer);
        vm.expectRevert(); // KairosFaucet__ZeroAddress
        f.resetClaim(address(0));
    }

    function test_updateToken_zero_address_reverts() public {
    vm.prank(deployer);
    KairosFaucet f = new KairosFaucet(address(0), 1 ether);

        vm.prank(deployer);
        vm.expectRevert(); // KairosFaucet__ZeroAddress
        f.updateToken(IERC20(address(0)));
    }

    function test_withdrawERC20_to_zero_reverts() public {
        // deploy a faucet with a dummy token
        vm.prank(deployer);
        MockERC20 token = new MockERC20("T", "T");
        token.mint(deployer, 10 ether);

    vm.prank(deployer);
    KairosFaucet f = new KairosFaucet(address(token), 1 ether);

        vm.prank(deployer);
        vm.expectRevert(); // ZeroAddress
        f.withdrawERC20(IERC20(address(token)), address(0), 1 ether);
    }

    function test_withdrawETH_to_zero_reverts() public {
    vm.prank(deployer);
    KairosFaucet f = new KairosFaucet(address(0), 1 ether);

        vm.prank(deployer);
        vm.expectRevert(); // ZeroAddress
        f.withdrawETH(payable(address(0)), 1 ether);
    }

    function test_claimETH_transfer_failure_reverts() public {
        // deploy eth faucet and fund it
    vm.prank(deployer);
    KairosFaucet f = new KairosFaucet(address(0), 0.1 ether);
        vm.deal(address(f), 1 ether);

        // create contract that rejects ETH
        Rejector r = new Rejector();

        // act as the rejector contract and attempt to claimETH - the transfer to msg.sender will revert
        vm.prank(address(r));
        vm.expectRevert(); // KairosFaucet__TransferFailed
        f.claimETH();
    }

    function test_withdrawETH_transfer_failure_reverts() public {
    vm.prank(deployer);
    KairosFaucet f = new KairosFaucet(address(0), 1 ether);
        // fund faucet
        vm.deal(address(f), 5 ether);

        Rejector r = new Rejector();

        vm.prank(deployer);
        vm.expectRevert(); // KairosFaucet__TransferFailed
        f.withdrawETH(payable(address(r)), 1 ether);
    }

    function test_deploy_behavior_matches_script() public {
        // simulate the script: deploy a faucet with token = 0 and drip = 0.1 ether
    vm.prank(deployer);
    KairosFaucet f = new KairosFaucet(address(0), 0.1 ether);

        assertEq(f.owner(), deployer);
        assertEq(f.dripAmount(), 0.1 ether);
        assertEq(address(f.token()), address(0));
    }
}

// Minimal ERC20 used by these tests (copied from the main test file)
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(balanceOf[from] >= amount, "ERC20: transfer amount exceeds balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

}
