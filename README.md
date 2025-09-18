# Minimal Faucet

A simple faucet contract that allows one-time claims per address. Supports ERC20 tokens and ETH. Owner can pause the contract, reset claims, update drip amount, and withdraw funds.

---

## Summary

* Contract: `MinimalFaucet.sol`
* Solidity: `^0.8.19`
* License: `MIT`
* Dependencies: OpenZeppelin `IERC20`, `SafeERC20`, `Ownable`, `ReentrancyGuard`, `Pausable`

Purpose: provide a fixed `dripAmount` to each account exactly once. Suitable for testnets or onboarding flows.

---

## High-level behavior

* `claim()` — ERC20 claim. One-time per address.
* `claimETH()` — ETH claim. One-time per address.
* `hasClaimed` mapping prevents repeated claims.
* Owner can update token, drip size, pause/unpause, reset claims, and withdraw funds.
* Contract can receive ETH.

---

## Constructor

```solidity
constructor(address _token, uint256 _dripAmount) Ownable(msg.sender) {
    token = IERC20(_token);
    dripAmount = _dripAmount;
}
```

* Passing `address(0)` disables ERC20 claims.
* `dripAmount` is in token units or wei for ETH.

---

## Deployment example (ethers.js)

```js
const MinimalFaucet = await ethers.getContractFactory('MinimalFaucet');
const faucet = await MinimalFaucet.deploy(tokenAddress, dripAmount);
await faucet.deployed();

await faucet.claim(); // user
await faucet.updateDripAmount(newAmount); // owner
await faucet.withdrawERC20(tokenAddress, ownerAddr, amount); // owner
```

---

## Testing checklist

* ERC20 claim success and duplicate prevention.
* ETH claim success and failure paths.
* Owner resetClaim allows re-claim.
* Pause/unpause behavior.
* Withdraw flows.

---

## Notes

* Simple, one-time claim design suitable for small-scale distributions.
* For large distributions consider Merkle airdrops to reduce storage costs.

---

## License

MIT
