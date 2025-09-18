// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/KairosFaucet.sol";

/// @notice Minimal ERC20 for tests
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

/// @notice Token that burns a percentage on transfer (fee-on-transfer)
contract FeeOnTransferToken is MockERC20 {
    uint256 public feeBasisPoints; // e.g. 100 = 1%

    constructor(string memory _name, string memory _symbol, uint256 _feeBasisPoints) MockERC20(_name, _symbol) {
        feeBasisPoints = _feeBasisPoints;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual override {
        require(balanceOf[from] >= amount, "ERC20: transfer amount exceeds balance");
        uint256 fee = (amount * feeBasisPoints) / 10000;
        uint256 afterAmount = amount - fee;
        balanceOf[from] -= amount;
        balanceOf[to] += afterAmount;
        totalSupply -= fee; // burn fee
        emit Transfer(from, to, afterAmount);
        if (fee > 0) {
            emit Transfer(from, address(0), fee);
        }
    }
}

/// @notice Malicious token that calls a hook on recipient contract during transfer to attempt reentrancy
contract MaliciousToken is MockERC20 {
    constructor() MockERC20("Malicious", "MAL") {}

    // If recipient is a contract and implements onTokenReceived(), call it
    function _transfer(address from, address to, uint256 amount) internal virtual override {
        require(balanceOf[from] >= amount, "ERC20: transfer amount exceeds balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);

        uint256 size;
        assembly {
            size := extcodesize(to)
        }
        if (size > 0) {
            // call onTokenReceived() if exists, ignore failures
            (bool ok,) = to.call(abi.encodeWithSignature("onTokenReceived()"));
            if (!ok) {
                // ignore
            }
        }
    }
}

/// @notice Attacker contract that will call back into faucet when receiving token
contract Attacker {
    KairosFaucet public faucet;
    address public owner;

    constructor(address _faucet) {
        faucet = KairosFaucet(payable(_faucet));
        owner = msg.sender;
    }

    // called by MaliciousToken during transfer
    function onTokenReceived() external {
        // attempt to call claim() again (reentrant)
        // ignore revert; we'll test revert behavior in test
        try faucet.claim() {} catch {}
    }

    // fallback to receive ETH and attempt reentrancy for ETH claim
    receive() external payable {
        try faucet.claimETH() {} catch {}
    }

    function callClaim() external {
        faucet.claim();
    }

    function callClaimETH() external {
        faucet.claimETH();
    }
}

/// @notice Foundry test suite for KairosFaucet
contract KairosFaucetTest is Test {
    KairosFaucet faucet;
    MockERC20 token;
    FeeOnTransferToken feeToken;
    MaliciousToken malToken;
    Attacker attacker;

    address deployer = address(0xABCD);
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    uint256 drip = 1 ether;

    function setUp() public {
        vm.prank(deployer);
        // Deploy basic token and mint faucet funds
        token = new MockERC20("TestToken", "TST");
        token.mint(deployer, 1000 ether);
        // Deploy faucet with token and drip
        vm.prank(deployer);
        faucet = new KairosFaucet(address(token), drip);

        // Transfer tokens to faucet so claims succeed
        vm.prank(deployer);
        token.transfer(address(faucet), 100 ether);

        // Deploy fee-on-transfer token
        feeToken = new FeeOnTransferToken("Fee", "FEE", 100); // 1% fee
        feeToken.mint(deployer, 1000 ether);

        // Deploy malicious token and attacker
        malToken = new MaliciousToken();
        malToken.mint(address(this), 1000 ether); // mint to test runner
    }

    /* --------------------
       Basic state tests
       -------------------- */

    function test_initial_state() public {
        assertEq(address(faucet.token()), address(token));
        assertEq(faucet.dripAmount(), drip);
        assertEq(faucet.owner(), deployer);
    }

    /* --------------------
       Token claim flow
       -------------------- */

    function test_claim_token_success() public {
        vm.prank(alice);
        // alice has no tokens but faucet has tokens
        vm.expectEmit(true, true, false, true);
        emit Claimed(alice, drip);
        faucet.claim();
        assertTrue(faucet.hasClaimed(alice));
        assertEq(token.balanceOf(alice), drip);
        assertEq(token.balanceOf(address(faucet)), 100 ether - drip);
    }

    // match event emitted by the contract
    event Claimed(address indexed account, uint256 amount);

    function test_claim_reverts_if_already_claimed() public {
        vm.prank(bob);
        faucet.claim(); // first claim

        vm.prank(bob);
        vm.expectRevert(); // custom error KairosFaucet__AddressAlreadyClaimed
        faucet.claim();
    }

    function test_claim_reverts_when_token_not_set() public {
        // Deploy a faucet with token == address(0)
        vm.prank(deployer);
        KairosFaucet noTokenFaucet = new KairosFaucet(address(0), drip);

        vm.prank(alice);
        vm.expectRevert(); // KairosFaucet__TokenAddressIsNotSet
        noTokenFaucet.claim();
    }

    function test_claim_reverts_if_insufficient_balance() public {
        // new faucet with high drip relative to balance
        vm.prank(deployer);
        MockERC20 smallToken = new MockERC20("Small", "SML");
        smallToken.mint(deployer, 5 ether);

        vm.prank(deployer);
        KairosFaucet smallFaucet = new KairosFaucet(address(smallToken), 10 ether);
        // no tokens transferred to faucet

        vm.prank(alice);
        vm.expectRevert(); // KairosFaucet__InsufficientFaucetBalance
        smallFaucet.claim();
    }

    /* --------------------
       ETH claim flow
       -------------------- */

    function test_claimETH_success() public {
        // Deploy faucet with token = 0 and top up ETH
        vm.prank(deployer);
        KairosFaucet ethFaucet = new KairosFaucet(address(0), 0.5 ether);
        // fund faucet with ETH
        vm.deal(address(deployer), 1 ether);
        vm.prank(deployer);
        (bool ok,) = address(ethFaucet).call{value: 1 ether}("");
        require(ok);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Claimed(alice, 0.5 ether);
        ethFaucet.claimETH();
        assertTrue(ethFaucet.hasClaimed(alice));
        assertEq(address(alice).balance, 0.5 ether);
    }

    function test_claimETH_reverts_if_insufficient_balance() public {
        vm.prank(deployer);
        KairosFaucet ethFaucet = new KairosFaucet(address(0), 2 ether);
        // no ETH funded
        vm.prank(alice);
        vm.expectRevert(); // Insufficient
        ethFaucet.claimETH();
    }

    /* --------------------
       Pause / unpause
       -------------------- */

    function test_pause_blocks_claims() public {
        vm.prank(deployer);
        faucet.pause();

        vm.prank(alice);
        vm.expectRevert(); // Pausable: paused
        faucet.claim();
    }

    function test_unpause_allows_claims() public {
        vm.prank(deployer);
        faucet.pause();
        vm.prank(deployer);
        faucet.unpause();

        vm.prank(alice);
        faucet.claim();
        assertTrue(faucet.hasClaimed(alice));
    }

    /* --------------------
       Admin functions and access control
       -------------------- */

    function test_resetClaim_owner_can_reset() public {
        vm.prank(bob);
        faucet.claim();
        assertTrue(faucet.hasClaimed(bob));

        vm.prank(deployer);
        faucet.resetClaim(bob);
        assertFalse(faucet.hasClaimed(bob));
    }

    function test_resetClaim_non_owner_reverts() public {
        vm.prank(bob);
        faucet.claim();
        vm.prank(charlie);
        vm.expectRevert(); // onlyOwner
        faucet.resetClaim(bob);
    }

    function test_updateToken_and_updateDripAmount_and_access_control() public {
        // non-owner cannot update
        vm.prank(alice);
        vm.expectRevert();
        faucet.updateToken(IERC20(address(feeToken)));

        vm.prank(deployer);
        faucet.updateToken(IERC20(address(feeToken)));
        assertEq(address(faucet.token()), address(feeToken));

        vm.prank(deployer);
        faucet.updateDripAmount(2 ether);
        assertEq(faucet.dripAmount(), 2 ether);
    }

    function test_withdrawERC20_and_ETH_owner_only() public {
        // deploy a faucet with token set and balance from setUp
        // non-owner withdraw attempt
        vm.prank(alice);
        vm.expectRevert();
        faucet.withdrawERC20(IERC20(address(token)), alice, 1 ether);

        // owner withdraw works
        vm.prank(deployer);
        faucet.withdrawERC20(IERC20(address(token)), alice, 1 ether);
        assertEq(token.balanceOf(alice), 1 ether);

        // ETH withdraw
        // fund faucet with ETH
        vm.deal(address(faucet), 5 ether);
        vm.prank(deployer);
        faucet.withdrawETH(payable(bob), 2 ether);
        assertEq(address(bob).balance, 2 ether);
    }

    /* --------------------
       Reentrancy tests using malicious token + attacker contract
       -------------------- */

    function test_reentrancy_attempt_via_malicious_token_and_attacker() public {
        // deploy a faucet with malToken
        vm.prank(deployer);
        KairosFaucet malFaucet = new KairosFaucet(address(malToken), drip);

        // mint tokens to deployer then transfer to faucet
        malToken.mint(address(this), 10 ether);
        malToken.transfer(address(malFaucet), 5 ether);

        // deploy attacker contract and mint tokens to attacker
        attacker = new Attacker(address(malFaucet));
        malToken.mint(address(attacker), 10 ether);

        // attacker calls claim through attacker contract (prank as attacker owner)
        vm.prank(address(attacker));
        // The malicious token swallows inner reverts, so the outer call does not revert.
        // We ensure no unintended state corruption happens and the attacker is marked as claimed.
        attacker.callClaim();

        // ensure faucet recording consistent: attacker should either be marked as claimed or not.
        // Because faucet sets hasClaimed before transfer, the reentrant call should revert with AddressAlreadyClaimed
        bool claimed = malFaucet.hasClaimed(address(attacker));
        assertTrue(claimed);
    }

    /* --------------------
       Fee-on-transfer token behavior
       -------------------- */

    function test_fee_on_transfer_token_claim() public {
        // owner updates token to feeToken and funds faucet
        vm.prank(deployer);
        faucet.updateToken(IERC20(address(feeToken)));

        vm.prank(deployer);
        feeToken.transfer(address(faucet), 100 ether);

        // check faucet balance sufficient
        assertGe(feeToken.balanceOf(address(faucet)), drip);

        // alice claims
        vm.prank(alice);
        faucet.claim();

        // because fee is burned, alice receives slightly less
        uint256 expectedReceived = drip - (drip * 100 / 10000); // 1% fee
        assertEq(feeToken.balanceOf(alice), expectedReceived);
    }

    /* --------------------
       Edge and invariants
       -------------------- */

    function test_owner_is_set_correctly() public {
        assertEq(faucet.owner(), deployer);
    }

    // helper: ensure revert types are caught where appropriate
    function test_onlyOwner_modifiers() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.pause();

        vm.prank(deployer);
        faucet.pause();
        assertTrue(faucet.paused());
    }
}
