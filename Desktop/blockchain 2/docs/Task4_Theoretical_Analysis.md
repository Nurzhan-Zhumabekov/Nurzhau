# Task 4 — Layer 2 Theoretical Analysis

## 1. Optimistic vs ZK Rollups

Both Optimistic and ZK rollups solve the same problem — execute thousands
of transactions cheaply off-chain while keeping Ethereum L1 as the source
of truth — but they pay for it with very different trade-offs.

**Optimistic rollups** (Arbitrum One, Optimism Mainnet, Base) post the
batched state transitions to L1 and assume they're correct. Anyone with a
copy of the transaction data can re-execute, detect a fraudulent batch,
and submit a *fraud proof*. To give the system time for this, withdrawals
back to L1 are delayed by a **7-day challenge window**. Computation is
cheap because no proof is generated up front; only contested batches
require a re-run on L1. The downside is the latency for trust-minimised
exits and the requirement that at least one honest validator is watching.

**ZK rollups** (zkSync Era, StarkNet, Polygon zkEVM, Linea) take the
opposite approach: every batch ships with a succinct cryptographic
*validity proof* (a zk-SNARK or zk-STARK) that L1 verifies before
accepting the new state root. There is no challenge window — finality is
mathematical the moment the proof is verified, so withdrawals to L1 can
clear in minutes. The cost is on the prover side: generating proofs is
computationally expensive, and the EVM-compatible variants (zkEVM, zkSync)
must either rebuild the EVM in zk-friendly form or use a custom compiler,
which trails general EVM features by months.

In one line: **optimistic = cheap to run, slow to exit; ZK = expensive to
prove, fast to exit.**

The two design spaces also differ on:

- **Decentralisation maturity.** Both ecosystems run a single sequencer
  today. Optimistic rollups have a clearer path to permissionless
  validation (anyone can submit a fraud proof), while ZK rollups need
  decentralised provers, which is technically harder.
- **Operator trust.** With an optimistic rollup, a malicious sequencer
  can re-order or censor for up to 7 days before a fraud proof would
  surface; ZK proofs prevent invalid state but not censorship.
- **Throughput.** ZK rollups ship more compact proofs of execution; OP
  rollups must post enough data for re-execution. EIP-4844 narrowed this
  gap dramatically.

## 2. Security model

The security argument for any rollup rests on **data availability** and
**state correctness**. Ethereum L1 supplies both: the rollup's data is
posted to L1 (so anyone can reconstruct state) and the state root that
gets accepted into the rollup contract is constrained by a fraud proof
(optimistic) or validity proof (ZK).

If L1 itself is honest (1/N honest validators), then:

- An OP rollup is secure as long as **at least one honest watcher**
  exists who is willing to publish a fraud proof inside the challenge
  window.
- A ZK rollup is secure as long as **the proof system itself is sound**
  (no cryptographic break) and the prover can keep up with the chain.

Where rollups can fail in practice:

- **Sequencer outage.** If the sequencer goes offline, users can be
  blocked from submitting transactions. Both Arbitrum and Optimism
  expose an L1 escape hatch (`forceInclusion` / `submitBatch`) that
  lets users push transactions directly through L1, but it's slow.
- **Sequencer reorgs.** Until the batch hits L1, the L2 ordering is
  whatever the sequencer decides. Front-running is possible inside
  this window.
- **Upgradeable contracts.** Most rollups are administered by a
  multisig that can upgrade the bridge contract. A compromised multisig
  is a complete loss of funds, regardless of fraud / validity proofs.

## 3. Data availability and EIP-4844

Before EIP-4844 ("proto-danksharding"), every rollup posted its batches
as L1 calldata at 16 gas per non-zero byte. That dominated cost — for
Arbitrum, ~85% of L2 fees was just L1 calldata.

EIP-4844 (Cancun-Deneb, March 2024) introduced **blobs**: ~125 KB
sidecar payloads attached to L1 transactions, priced on a separate fee
market. Blobs are stored by consensus-layer nodes for ~18 days, then
pruned, but the rollup contract verifies a KZG commitment against the
blob hash at the moment of inclusion. After 18 days, only the
commitment remains on-chain, not the raw data.

Two consequences:

1. **Costs collapsed.** Vault deposit on Arbitrum dropped from ~$0.40
   pre-4844 to ~$0.03 post-4844, even at the same gas price. Most of
   the saving is mechanical: blob gas is currently 100× cheaper than
   the equivalent calldata.
2. **Data availability is now time-bounded.** Once blobs are pruned,
   the source of truth is whatever indexer / archive node holds a copy.
   For optimistic rollups this matters for the 7-day window (still well
   within blob retention); for ZK rollups the validity proof is on-chain
   regardless, so the historical data is "needed" only for full state
   reconstruction.

**Full danksharding** (the long-term plan) scales blobs further with a
data-availability sampling network, theoretically unlocking 100x more
rollup throughput.

## 4. Bridge security

Cross-chain bridges have been the single largest source of value loss in
crypto history. The lessons from major incidents:

- **Ronin Network (Mar 2022, ~$625M).** 9-of-9 multisig with 4 keys
  controlled by Sky Mavis and 1 delegated to Axie DAO. Attacker
  compromised 5 keys after Axie DAO had granted Sky Mavis a permission
  that was never revoked. *Lesson: any permission you don't revoke
  becomes part of the attack surface forever.*
- **Wormhole (Feb 2022, ~$325M).** A signature verification check on
  Solana didn't validate the address of the verifier set, allowing the
  attacker to forge a "guardian" approval and mint 120 k wETH on
  Solana. *Lesson: signature schemes must verify both the message **and**
  the signer's authority.*
- **Nomad (Aug 2022, ~$190M).** Bridge initialised the trusted root to
  `0x000…0`, treating any message with that as the root as pre-approved.
  Once one user noticed, everyone copy-pasted the exploit. *Lesson:
  initialisation states are part of the security boundary; defaults
  must be invalid, not "empty."*

Common patterns to mitigate these risks:

- **Native rollup bridges over third-party bridges.** Arbitrum's and
  Optimism's bridges inherit Ethereum's security; third-party "fast"
  bridges trade safety for latency.
- **Smaller blast radius.** Permissions on the bridge contract should
  be split across multisigs with different signers, and time-locked
  upgrades let users withdraw before a malicious upgrade lands.
- **Independent monitoring.** A fraud proof is only useful if someone
  watches. The same applies to bridges — projects like L2Beat track
  ongoing risk-rating changes publicly.

## 5. Cost analysis

### Effective fee structure on L2

L2 transaction cost = `L2 execution gas × L2 gas price` + `L1 data fee`

The L1 data fee depends on what the rollup posts. Post-4844 most major
rollups post batches as blobs, which trade a capped supply (currently 6
blobs per L1 block) for a cheap unit price. When blob demand spikes
(e.g. during NFT mints across L2s), blob fees do too — but they almost
never reach the pre-4844 baseline.

### Worked example

A `Vault.deposit(1000 USDS, ...)` from this assignment costs `107 000`
EVM gas. At L1 (25 gwei base fee + 1 gwei tip, ETH = $3 000), that's

```
107 000 × 26e-9 × 3 000 ≈ $8.35
```

The same transaction on Arbitrum Sepolia at typical sequencer pricing
(~0.1 gwei effective) costs

```
107 000 × 0.1e-9 × 3 000 ≈ $0.032
```

a ~260× saving. Optimism and Base land in the same range; zkSync Era
adds prover cost into its gas price and is roughly comparable
(~0.01–0.05 USD for the same operation).

### When to stay on L1 anyway

- **High-value, low-frequency.** A $50M institutional deposit pays $8
  in gas without complaint and benefits from the strongest available
  finality.
- **Compatibility with existing L1 protocols.** A Uniswap-V3 hook or a
  MakerDAO collateral type lives where its counterparty lives.

### When to choose L2

- **Per-user retail flows.** Game items, vault deposits, Chainlink
  reads — anything where 100 ms latency and $0.03 fee are
  product-relevant.
- **High-frequency on-chain logic.** Indexing, oracles, paymasters —
  L2 throughput unblocks designs that were impossible at L1 fees.

## 6. Conclusion

L2 rollups are the deployment default for new EVM applications today,
not a niche specialisation. The two main families (Optimistic, ZK)
trade-off finality latency against proving cost, but both inherit
Ethereum's security as long as data availability and proofs are honored.
EIP-4844 has compressed L2 costs into a range where most consumer
applications no longer have a price reason to deploy on L1 directly.
Bridge security is now the primary risk surface — choose native rollup
bridges and assume any third-party bridge is part of your attack model.
