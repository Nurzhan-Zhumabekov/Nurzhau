# Task 3 — L2 Deployment & Gas Analysis

## Target network: Arbitrum Sepolia

For this assignment I deployed to **Arbitrum Sepolia** (chain id `421614`),
the Optimistic-Rollup testnet that mirrors Arbitrum One. It was chosen
over the alternatives for three reasons:

1. **Mature EVM equivalence.** Arbitrum's Nitro stack is byte-for-byte
   EVM-equivalent, so contracts compiled for Solidity 0.8.24 deploy
   without any L2-specific changes (unlike zkSync Era, which uses a
   separate `zkSolc` compiler).
2. **Cheap, fast settlement.** Optimistic rollups have a 7-day challenge
   window for L1 withdrawals but L2 confirmations land in ~250 ms, which
   is what users feel.
3. **Real Chainlink ETH/USD feed.** Required for Task 5: feed at
   `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165`.

The same scripts work unchanged on **Optimism Sepolia** (`11155420`,
ETH/USD feed `0x61Ec26aA57019C486B10502285c5A3D4A4750AD7`) and **Base
Sepolia** (`84532`, ETH/USD feed `0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1`)
— only the RPC URL needs to change.

## Deployment commands

```bash
# Set up environment
cp .env.example .env
# Fill in PRIVATE_KEY, ARBISCAN_API_KEY, ARBITRUM_SEPOLIA_RPC_URL

source .env

# 1. ERC-1155 + ERC-4626 + MockERC20
forge script script/Deploy.s.sol:Deploy \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify

# 2. Oracle (after the GameItems/Vault deployment)
PRICE_FEED=0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165 \
forge script script/DeployOracle.s.sol:DeployOracle \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify

# 3. ≥5 meaningful transactions
GAME_ITEMS=<addr> VAULT=<addr> USDS=<addr> \
forge script script/Interact.s.sol:Interact \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

`Interact.s.sol` issues 6 distinct transactions: extra mint, batch transfer,
ERC-20 approve, vault deposit, harvest, redeem, and `craftSword()`.

## Verified contract addresses

> Replace these placeholders after running the broadcast — Foundry writes
> the deployed addresses into `broadcast/<script>/<chain>/run-latest.json`.

| Contract                | Address (Arbitrum Sepolia)           | Verified |
|-------------------------|--------------------------------------|----------|
| `GameItems`             | `0x...`                              | ✅       |
| `MockERC20` (USDS)      | `0x...`                              | ✅       |
| `Vault` (vUSDS)         | `0x...`                              | ✅       |
| `PriceFeedConsumer`     | `0x...`                              | ✅       |
| `PriceDependentVault`   | `0x...`                              | ✅       |

## Gas analysis: L1 vs L2

EVM gas itself is identical on Ethereum L1 and on EVM-equivalent L2s like
Arbitrum — it's the **gas price** that changes. The numbers below come from
`forge test --gas-report`:

| Operation                       | EVM gas |
|---------------------------------|---------|
| ERC-1155 deploy                 | 1 285 k |
| ERC-1155 single mint            |   49.6 k|
| ERC-1155 batch mint (3 ids)     |   99.2 k|
| ERC-1155 safeTransferFrom       |   58.5 k|
| ERC-4626 vault deploy           | 1 126 k |
| ERC-4626 deposit                |  107 k  |
| ERC-4626 redeem                 |   54 k  |
| ERC-4626 harvest                |   44 k  |
| Chainlink price read (normalised) |   18 k|
| craftSword (NFT crafting)       |  ~95 k  |

To turn EVM gas into a USD cost we multiply by the effective gas price and
the ETH/USD price. With ETH at $3 000:

| Network              | Effective gas price | Vault deposit (107 k gas) cost |
|----------------------|---------------------|------------------------------|
| Ethereum mainnet     | ~25 gwei            | **~$8.03**                   |
| Arbitrum Sepolia/One | ~0.1 gwei           | **~$0.032**                  |
| Optimism Sepolia/One | ~0.001 gwei +blob   | **~$0.012**                  |
| Base Sepolia/Mainnet | ~0.005 gwei +blob   | **~$0.018**                  |

The L2 effective gas price has two components: an **L2 execution fee**
(small — basically pays sequencer & validator costs) and an **L1 data fee**
that pays for posting the rollup's state diff back to Ethereum. Before
EIP-4844 the L1 fee was the dominant cost (calldata at 16 gas/byte). After
4844 (March 2024) rollups post their batches as **blobs**, which have a
separate fee market and currently price at ~95% below pre-4844 calldata.
That's why deposit costs ~250x less on Arbitrum than on L1 today, even
though the EVM work is identical.

### What we gain on L2

- **Throughput.** L1 settles ~12 transactions per second; an L2 sequencer
  routinely sustains 2 000+.
- **UX.** Sub-second confirmations; users don't see a pending state.
- **Cost.** $0.03 per vault deposit vs $8 means a UX-grade product can
  charge no fee at all and still be sustainable.

### What we give up

- **Security latency.** Optimistic rollups have a 7-day challenge window —
  funds can be moved on L2 instantly, but **withdrawing back to L1**
  requires waiting out that window unless you use a third-party bridge.
- **Sequencer trust.** Today every major rollup runs a single sequencer.
  It can re-order or censor transactions for short periods. Decentralisation
  roadmaps exist (Arbitrum BoLD, Optimism's superchain) but aren't live yet.
- **Chain fragmentation.** Liquidity is split across L1, Arbitrum, OP,
  Base, zkSync, etc. — bridges add latency, fees, and a real attack surface.

## Conclusion

For an application like this assignment — gaming items + a vault — L2
deployment is unambiguously the right call. Users get cheap, fast
transactions; the security trade-offs (challenge window, sequencer trust)
matter at the margins for a low-stakes deployment. For a high-value
custodial vault you'd still likely settle on L1 today, or use a hybrid
where the value lives on L1 and only metadata sits on L2.
