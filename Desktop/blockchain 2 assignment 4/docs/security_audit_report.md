# Security Audit Report — DAO Governance System

**Project:** DAO & On-chain Governance System (Assignment 4)  
**Contracts audited:** GovernanceToken.sol, TokenVesting.sol, MyGovernor.sol, Treasury.sol, Box.sol  
**Solidity version:** 0.8.28  
**Framework:** OpenZeppelin Contracts v5  
**Date:** May 2026  
**Auditor:** Nurzhan Zhumabekov  

---

## 1. Executive Summary

The DAO governance system is built on OpenZeppelin's battle-tested Governor framework. The overall security posture is **good** — no critical vulnerabilities were identified. Three medium-severity findings and several informational observations are documented below.

---

## 2. Slither Analysis Results

Slither was run with default detectors. Key findings:

| Severity | Detector | Contract | Finding |
|----------|----------|----------|---------|
| Medium | `reentrancy-eth` | Treasury.sol | `transferETH` makes an external call before emitting the event. |
| Low | `events-access` | TokenVesting.sol | `release()` emits event after external transfer (reentrancy guard present). |
| Informational | `dead-code` | GovernanceToken.sol | Inherited functions not overridden at source level (expected). |
| Informational | `solc-version` | All | Using 0.8.28 — not yet fully supported by Hardhat stack traces. |
| Informational | `missing-zero-check` | MyGovernor.sol | Constructor parameters come from OpenZeppelin — validated upstream. |

**Slither command used:**
```
slither . --exclude-informational
```

### Finding AUDIT-001 (Medium): Treasury ETH transfer event ordering

**Location:** `Treasury.sol:transferETH()`  
**Description:** The `ETHTransferred` event is emitted after the low-level `.call`. This violates the Check-Effects-Interactions (CEI) pattern; however, `onlyOwner` restricts the caller to the TimelockController, which is not a smart-contract attack vector.  
**Recommendation:** Emit events before external calls.  
**Fixed version:**
```solidity
function transferETH(address payable to, uint256 amount) external onlyOwner {
    require(address(this).balance >= amount, "Insufficient ETH");
    emit ETHTransferred(to, amount);   // emit first
    (bool ok,) = to.call{value: amount}("");
    require(ok, "ETH transfer failed");
}
```

### Finding AUDIT-002 (Low): TokenVesting has no emergency stop

**Location:** `TokenVesting.sol`  
**Description:** If the beneficiary wallet is compromised, there is no way to pause vesting. This is a design choice (no admin), but worth documenting.  
**Recommendation:** For production, consider a guardian role that can pause releases without being able to redirect them.

### Finding AUDIT-003 (Low): Treasury lacks token enumeration

**Location:** `Treasury.sol`  
**Description:** There is no record of which ERC-20 tokens are held. An off-chain indexer or event parsing is required to know the treasury's full token holdings.  
**Recommendation:** Add a `TokenRegistered` event or a token registry mapping.

---

## 3. Manual Code Review

### 3.1 GovernanceToken

- Inherits `ERC20`, `ERC20Votes`, `ERC20Permit` — all from OpenZeppelin v5.
- `_update` and `nonces` overrides correctly resolve the multiple-inheritance diamond.
- Initial distribution happens in the constructor; tokens cannot be re-minted (no `mint` function exposed).
- **No centralization risk** post-deployment — `Ownable` is set to deployer but minting only happens in constructor.

### 3.2 MyGovernor

- Voting delay: 7,200 blocks (~1 day at 12 s/block). Ensures proposers cannot front-run their own proposals.
- Voting period: 50,400 blocks (~1 week). Sufficient for broad participation.
- Proposal threshold: 10,000 GOV (1% of supply). Prevents spam but allows mid-sized holders to propose.
- Quorum: 4% of circulating supply. Reasonable for a starting DAO; can be raised via governance.
- **No upgradeability** — the governor is immutable once deployed. A new governor would need to be voted in via the timelock.

### 3.3 TimelockController

- 2-day delay between queue and execute provides a reaction window for token holders.
- `EXECUTOR_ROLE` granted to `address(0)` — anyone can trigger execution after the delay. This is the OpenZeppelin recommended pattern and does not introduce risk because the payload is already committed.
- Deployer's `DEFAULT_ADMIN_ROLE` is **revoked** immediately after setup — no backdoor admin.

### 3.4 Treasury

- `onlyOwner` modifier restricts all fund operations to the TimelockController (transferred in constructor).
- ETH received via `receive()` is safe.
- ERC-20 transfers use OpenZeppelin `SafeERC20` — no silent failure risk.

### 3.5 Box

- Trivially simple. The `onlyOwner` guard ensures only governance can call `store()`.

---

## 4. Governance Attack Analysis

### 4.1 Whale Attack (>50% token holdings)

**Scenario:** An attacker accumulates more than 50% of the total token supply.

**Impact:** With >50% of votes, an attacker can pass any proposal after the voting period.

**Safeguards in this system:**
1. **Timelock delay (2 days):** Even if a malicious proposal passes, token holders have 2 days to observe it and sell/exit before it executes. This is the primary protection.
2. **Voting delay (1 day):** Snapshot is taken before voting starts. A flash-loan or just-acquired position at proposal-time does not count — the attacker must have held tokens at the snapshot block.
3. **Proposal threshold (1%):** The whale must already control 10,000 GOV before they can even propose.
4. **Social coordination:** Large token holders and the community can mobilize to vote against hostile proposals.

**Recommendation:** Consider implementing a veToken (vote-escrowed) model where long-term committed tokens get amplified voting power, making flash-acquisition attacks more expensive.

### 4.2 Flash Loan Governance Attacks

**Scenario:** An attacker borrows a large number of tokens in a single transaction, votes on a governance proposal, and returns them — all in one block.

**How ERC20Votes prevents this:**
- `ERC20Votes` uses checkpoints to record voting power **at a past block** (the `proposalSnapshot`).
- When you call `castVote`, the governor queries `token.getPastVotes(voter, snapshotBlock)`.
- Flash loans acquire and return tokens within the same block. Even if the attacker acquires tokens *after* the snapshot block, `getPastVotes(snapshotBlock)` returns zero.
- The attacker would need to hold tokens *before* the proposal was created and the snapshot was recorded — defeating the purpose of a flash loan.

**Conclusion:** Flash loan governance attacks are **not possible** against this system because of the block-based snapshot mechanism.

---

## 5. Deployment Checklist

### Pre-Deployment
- [ ] Contracts compiled without warnings on Solidity 0.8.28 + cancun EVM
- [ ] All 28 tests pass
- [ ] Environment variables set: `PRIVATE_KEY`, `SEPOLIA_RPC_URL`, `ETHERSCAN_API_KEY`
- [ ] Reviewed token distribution addresses are correct

### Deployment Order
1. TimelockController (min delay = 172800 seconds)
2. GovernanceToken → addresses for team/treasury/community/liquidity
3. TokenVesting → GovernanceToken address + team beneficiary
4. Transfer team tokens: team wallet → vesting contract
5. MyGovernor → GovernanceToken + TimelockController
6. Box → TimelockController
7. Treasury → TimelockController
8. `timelock.grantRole(PROPOSER_ROLE, governor)`
9. `timelock.grantRole(EXECUTOR_ROLE, address(0))`
10. `timelock.revokeRole(DEFAULT_ADMIN_ROLE, deployer)`

### Post-Deployment Verification
```
token.totalSupply()          == 1,000,000 * 10^18
token.balanceOf(timelock)    == 300,000 * 10^18  (treasury share)
timelock.getMinDelay()       == 172800
governor.votingDelay()       == 7200
governor.votingPeriod()      == 50400
governor.proposalThreshold() == 10,000 * 10^18
box.owner()                  == timelock.address
treasury.owner()             == timelock.address
timelock.hasRole(PROPOSER)   == governor.address only
timelock.hasRole(ADMIN)      == false (no one)
```

### Etherscan Verification
```bash
npx hardhat verify --network sepolia <GovernanceToken> <team> <timelock> <community> <liquidity>
npx hardhat verify --network sepolia <TokenVesting> <token> <teamWallet>
npx hardhat verify --network sepolia <MyGovernor> <token> <timelock>
npx hardhat verify --network sepolia <Box> <timelock>
npx hardhat verify --network sepolia <Treasury> <timelock>
```

---

## 6. Monitoring Plan

### Events to Watch

| Contract | Event | Action |
|----------|-------|--------|
| MyGovernor | `ProposalCreated` | Alert community; start 1-day countdown |
| MyGovernor | `VoteCast` | Track voting progress in real-time |
| MyGovernor | `ProposalQueued` | Notify 2-day timelock window started |
| MyGovernor | `ProposalExecuted` | Verify on-chain state changed correctly |
| TimelockController | `CallScheduled` | Double-check calldata |
| Treasury | `ETHTransferred` | Alert if large outflow |
| Treasury | `ERC20Transferred` | Alert on any token movement |
| GovernanceToken | large `Transfer` | Watch for accumulation (whale alerts) |

### Metrics to Track
- Proposal participation rate (unique voters / eligible voters)
- Average voting power per voter (Gini coefficient)
- Quorum achievement rate
- Time-to-execute after proposal passes

---

## 7. Conclusion

The DAO governance contracts are well-structured and leverage OpenZeppelin's audited implementation. The two-day timelock is the most critical security control, giving the community time to respond to malicious governance. The ERC20Votes snapshot mechanism effectively prevents flash loan attacks. The identified medium finding (event ordering) should be fixed before mainnet deployment; the low findings are acceptable for testnet/initial deployment.
