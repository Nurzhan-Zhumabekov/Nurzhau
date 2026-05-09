# DAO Governance Research
## Blockchain Technologies 2 — Assignment 4, Task 6

**Author:** Nurzhan Zhumabekov  
**Date:** May 2026  

---

## 1. Governance Models: Comparative Analysis

### 1.1 Token-Weighted Voting

**Mechanism:** Each token holder receives one vote per token held. The proposal passes if weighted for-votes exceed against-votes and quorum is met.

**Advantages:**
- Simple to implement and audit.
- Aligns incentives: large holders bear more economic risk from bad decisions.
- Highly sybil-resistant (buying power is expensive).
- Proven at scale: Uniswap, Compound, Aave all use this model.

**Disadvantages:**
- **Plutocratic:** Wealthy token holders dominate. A single VC fund with 10% supply can out-vote thousands of retail holders.
- **Low participation:** Many small holders don't bother voting because their impact is negligible.
- **Whale collusion risk:** A small number of large holders can collude off-chain to pass favorable proposals.

**Best for:** Protocols where token ownership correlates with economic stake and informed decision-making (e.g., DEXes, lending protocols).

---

### 1.2 Quadratic Voting

**Mechanism:** The cost of votes increases quadratically. If 1 vote costs 1 token, then 2 votes cost 4 tokens, 3 votes cost 9 tokens, etc. This means the *marginal cost* of additional influence rises steeply.

**Advantages:**
- **More democratic:** Reduces whale dominance. A holder with 100× more tokens gets only 10× more votes.
- **Expresses preference intensity:** Holders who care deeply about an issue can signal that by spending more.
- Theoretically optimal for social welfare aggregation (Glen Weyl's radical markets research).

**Disadvantages:**
- **Sybil vulnerability:** Without identity verification, an attacker can split holdings across many wallets and vote cheaply. Each wallet gets cheap votes with the same total tokens.
- Requires a Sybil-resistance layer (Proof of Humanity, Worldcoin, ENS) to work correctly.
- More complex to implement and explain to users.
- Gas costs scale with vote count.

**Best for:** DAOs with strong identity layers (e.g., Gitcoin Grants uses quadratic funding, not voting).

---

### 1.3 Conviction Voting

**Mechanism:** Voting power accumulates ("builds conviction") the longer a token is staked on a proposal. A proposal passes when its accumulated conviction exceeds a threshold that is proportional to the requested funds (larger requests need more conviction).

**Advantages:**
- **Continuous:** No discrete voting periods. Any proposal can pass at any time if enough conviction accumulates.
- **Signal of commitment:** Short-term speculators have less influence than long-term stakeholders.
- **Prevents governance attacks:** You can't flash-borrow tokens and instantly pass a proposal.
- No binary pass/fail — more nuanced.

**Disadvantages:**
- Hard to explain to non-technical users.
- Larger proposals are structurally disadvantaged (higher conviction threshold).
- Slow convergence — important decisions can take weeks.
- Not suitable for binary yes/no decisions that need fast resolution.

**Best for:** Community funding DAOs (e.g., 1Hive, Gardens framework).

---

### 1.4 Summary Comparison

| Dimension | Token-Weighted | Quadratic | Conviction |
|-----------|---------------|-----------|------------|
| Sybil resistance | High | Low (without identity) | Medium |
| Plutocracy risk | High | Low | Medium |
| Implementation complexity | Low | Medium | High |
| Speed of decision | Fast (fixed period) | Fast | Slow (continuous) |
| Flash loan resistance | Medium (with snapshots) | Low | High |
| Real-world adoption | Very High | Low | Low-Medium |

---

## 2. Real-World DAO Analysis

### 2.1 Uniswap Governance: Deploy Uniswap v3 to BNB Chain (2023)

**Proposal:** Uniswap Governance Proposal 20 — deploy Uniswap v3 to BNB Smart Chain using the Wormhole bridge.

**Background:** Multiple bridge providers (Layerzero, Wormhole, CELER, deBridge) competed to be the official bridge for Uniswap's cross-chain deployment to BNB Chain. The vote was contentious because a16z (a major Uniswap investor) opposed Wormhole and supported Layerzero.

**Voter Turnout:**
- Total votes cast: ~42 million UNI
- Total eligible supply: ~1 billion UNI
- Turnout: ~4.2% of circulating supply

**Outcome:** Wormhole won (despite a16z's opposition). The proposal passed with 66% For votes. The episode exposed the tension between VCs and broader community in DAO governance.

**Key Takeaway:** Even in a major protocol, voter turnout is very low. Large holders (a16z with ~15M UNI) have outsized influence, yet community coordination can still overcome whale opposition. The public controversy increased participation.

---

### 2.2 MakerDAO: Endgame Protocol Restructuring (2022-2023)

**Proposal:** The "Endgame Plan" — a radical restructuring of MakerDAO into a constellation of "SubDAOs," each with its own governance tokens (MetaDAOs). Proposed by founder Rune Christensen.

**What was proposed:**
- Create 5 SubDAOs (Spark, NewChain, etc.) each with specialized functions.
- Launch a new governance token (NewGovToken) to replace MKR over time.
- Implement "elixir" liquidity mechanisms.

**Voter Turnout:**
- MKR required for quorum: 40,000 MKR (~$28M at the time)
- Votes cast on initial core ratification: ~65,000 MKR across several polls
- Turnout: ~6.5% of circulating MKR

**Outcome:** Passed across multiple executive votes. The Endgame plan became MakerDAO's strategic direction. Later rebranded as "Sky" protocol in 2024.

**Key Takeaway:** Foundational protocol changes can pass with low turnout if the founder/core team mobilizes their holdings. This illustrates the tension between "decentralized governance" and practical founder control. The multi-poll structure (each element voted on separately) was innovative but created voter fatigue.

---

## 3. Governance Attacks

### 3.1 Beanstalk Protocol Flash Loan Attack (April 2022)

**What happened:**
Beanstalk was a decentralized credit-based stablecoin protocol on Ethereum. Its governance used a simple token-weighted voting model with no timelock delay and same-block voting.

An attacker used a flash loan to:
1. Borrow ~$1 billion in assets from Aave.
2. Acquire a supermajority of STALK governance tokens in a single transaction.
3. Submit and immediately pass a malicious governance proposal that drained the Beanstalk treasury into the attacker's wallet.
4. Repay the flash loan, keeping ~$182 million in profit.

**What went wrong:**
- **No timelock:** Governance actions executed immediately on vote passing, with no delay.
- **No snapshot mechanism:** Voting power was counted at the time of voting, not at a past snapshot block.
- **Flash loan vulnerability:** The two above conditions allowed flash-acquired voting power to be used.

**How to prevent:**
- Mandatory timelock delay (2+ days) between proposal passing and execution — gives community time to react.
- ERC20Votes snapshot mechanism — voting power is always measured at a past block, making flash loans useless.
- Emergency guardian multisig that can veto malicious proposals.

**Impact:** $182M lost, never recovered. Beanstalk relaunched with improved governance.

---

### 3.2 Build Finance DAO Hostile Takeover (February 2022)

**What happened:**
Build Finance DAO was a DeFi investment DAO. A single attacker gradually accumulated the majority of its BUILD governance tokens (the token had low market cap and liquidity). Once in control, the attacker used their supermajority to:
1. Pass a governance proposal minting new BUILD tokens to themselves.
2. Effectively take permanent control of all remaining DAO funds.

The attack was entirely on-chain and "legal" within the protocol rules.

**What went wrong:**
- **No supply cap or mint limits:** The governance contract could mint unlimited new tokens, which is self-defeating for governance security.
- **No quorum or participation threshold:** A single large holder could pass proposals with no opposition.
- **Token concentration:** With a small, illiquid token, concentration was easy and cheap.
- **No timelock:** The proposal executed immediately.

**How to prevent:**
- Fixed token supply — governance tokens should not be mintable post-deployment (or mint must itself require governance with high quorum).
- Meaningful quorum requirements (4%+ of supply must participate).
- Timelock delay that allows community to respond.
- Emergency veto mechanism (guardian multisig).
- Monitor large accumulation events and alert the community.

---

## 4. Legal Considerations

### 4.1 Wyoming DAO LLC

In 2021, Wyoming became the first US state to legally recognize DAOs as Limited Liability Companies (DAO LLCs). Under the Wyoming DAO LLC Act:

- A DAO can be registered as a Wyoming DAO LLC with legal personhood.
- Members receive limited liability protection (like a traditional LLC).
- The LLC can own property, enter contracts, and sue or be sued.
- Governance is conducted algorithmically via smart contracts, which are legally binding under Wyoming law.
- A DAO LLC can be "member-managed" (by token holders) or "algorithmically managed" (by smart contract rules).

**Implications:**
- DAOs that incorporate as Wyoming DAO LLCs gain legal recognition but also regulatory obligations (annual reports, registered agents, filing fees).
- Token holders in an unregistered DAO may have unlimited personal liability as "general partners."
- Other US states are considering similar legislation (Vermont, Tennessee).

### 4.2 EU MiCA Framework (Markets in Crypto-Assets Regulation)

MiCA entered into force in June 2023 and applies fully from December 2024. Relevant DAO provisions:

- **Governance tokens as crypto-assets:** If a DAO's governance token grants economic rights (e.g., fee revenue), it may be classified as an "asset-referenced token" or a "utility token," triggering registration and whitepaper requirements.
- **DAOs as crypto-asset service providers (CASPs):** If a DAO provides crypto services (trading, lending), it may need CASP authorization.
- **Liability:** MiCA does not have a clear liability framework for DAO participants. The issuer of the token is typically liable for the whitepaper.
- **Decentralization defense:** "Fully decentralized" protocols with no identifiable issuer may fall outside MiCA's scope — but the definition of "fully decentralized" is not yet settled.

**Practical impact:** DAOs with EU users must either (a) achieve genuine decentralization, (b) obtain CASP registration, or (c) geofence EU users. Legal uncertainty remains.

---

## 5. Future of Governance

### 5.1 Optimistic Governance

**Concept:** Proposals pass automatically after a delay unless explicitly vetoed by a quorum of token holders. The default is to trust the proposer; challenges require active intervention.

**Advantages:**
- Reduces governance overhead — routine decisions don't require a full vote.
- Faster execution for uncontroversial proposals.
- Participation burden falls only on those who object.

**Disadvantages:**
- Requires vigilant community members to monitor proposals.
- Malicious proposers can exploit low-attention periods.

**Example:** Optimism's Security Council uses an optimistic model for protocol upgrades.

### 5.2 veToken Models (Vote-Escrowed)

**Concept:** Popularized by Curve Finance (veCRV). Token holders lock tokens for a fixed period (up to 4 years) to receive vote-escrowed tokens (ve-tokens). Voting power is proportional to locked amount × remaining lock duration.

**Formula:** `veTokens = tokens × (lock_remaining / max_lock)`

**Advantages:**
- Aligns long-term holders with protocol governance.
- Reduces mercenary governance (short-term holders buying votes for one vote then selling).
- Creates sustainable tokenomics — locked supply reduces sell pressure.

**Disadvantages:**
- Lock-up reduces token liquidity.
- "Bribe markets" emerge (Votium, Paladin) where protocols bribe veToken holders to direct emissions — this is governance capture by a different name.
- Complexity for new users.

### 5.3 Time-Weighted Voting (Conviction Voting Variant)

**Concept:** Voting power depends not just on token balance but on how long the voter has held those tokens or participated in governance.

**Advantages:**
- Rewards engaged, long-term community members.
- Makes governance more resistant to short-term speculators and attackers.

**Disadvantages:**
- Hard to implement without a Sybil layer.
- New participants start with no voting power, reducing inclusivity.

### 5.4 AI-Assisted Governance

Emerging research area: using AI agents to summarize proposals, analyze economic impacts, and even vote on behalf of delegators according to pre-set preferences. Reduces voter fatigue but introduces new trust assumptions on the AI model.

---

## 6. Conclusion

On-chain governance remains one of the hardest unsolved problems in DeFi. Token-weighted voting is currently dominant but has clear plutocracy risks. The Beanstalk and Build Finance attacks demonstrate that the timelock + snapshot combination is not optional — it is the minimum viable security baseline. Looking forward, veToken models and optimistic governance offer improvements for specific use cases, while quadratic voting awaits a practical Sybil-resistance solution at scale. The regulatory environment (Wyoming DAO LLC, EU MiCA) is evolving rapidly, and DAOs that do not proactively engage with the legal framework risk being caught off-guard as regulations solidify.
