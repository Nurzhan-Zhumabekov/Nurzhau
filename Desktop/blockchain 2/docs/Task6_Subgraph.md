# Task 6 — The Graph Subgraph

## What the subgraph indexes

`subgraph/subgraph.yaml` declares two data sources, both pointed at our
Arbitrum Sepolia deployments:

1. **`Vault`** — listens for `Deposit`, `Withdraw`, and `Harvest` events.
   The handlers in `mappings/vault.ts` maintain a per-user `VaultUser`
   entity (running shares, totals deposited / withdrawn) and a singleton
   `VaultStats` row that aggregates across the whole vault.
2. **`GameItems`** — listens for `TransferSingle`, `TransferBatch`, and
   `Crafted`. The handlers in `mappings/items.ts` keep a `Player`
   entity per address, an `ItemBalance` row per `(player, tokenId)`,
   and an immutable `CraftEvent` log of every successful craft.

The schema in `subgraph/schema.graphql` uses `@derivedFrom` on
`Player.itemBalances` and `VaultUser.deposits` so that querying a single
user pulls their full history without manually correlating IDs.

## Why subgraphs over RPC polling

A naïve dashboard would poll the contract over RPC: `balanceOf` for each
user, `totalAssets` every block, etc. That doesn't scale — for 10 000
players you'd issue 10 000+ calls per refresh. A subgraph turns the same
question into a single GraphQL query backed by a precomputed Postgres
table. The Graph Node walks the chain once, applies the mapping handlers
to every relevant event, and stores the resulting entities; clients then
run rich filtered / sorted queries (e.g. "top 10 depositors by balance,
with their deposit history") in a few milliseconds.

## Sample queries

`subgraph/queries.graphql` ships five working queries; the three that
the assignment specifically asks for:

```graphql
# All vault users with non-zero balance, biggest first.
query TopDepositors {
  vaultUsers(first: 10, orderBy: totalDeposited, orderDirection: desc) {
    id
    shares
    totalDeposited
    totalWithdrawn
  }
}

# Recent deposits with their user, caller, and tx hash.
query RecentDeposits {
  depositEvents(first: 20, orderBy: timestamp, orderDirection: desc) {
    user {id}
    assets
    shares
    timestamp
    txHash
  }
}

# Total counts and lifetime amounts across the whole vault.
query VaultAggregate {
  vaultStats(id: "0x01") {
    totalDeposited
    totalHarvested
    depositCount
    harvestCount
  }
}
```

The other two (`TopCrafters`, `HarvestHistory`) demonstrate cross-entity
querying via `@derivedFrom` and a time-series view that a dashboard
could plot directly.

## Deployment workflow

```bash
cd subgraph
npm install
graph codegen
graph build
# Studio (Hosted Service deprecation replaced by The Graph Studio):
graph auth --studio <DEPLOY_KEY>
graph deploy --studio blockchain2-assignment3
```

Before deploying, paste the deployed contract addresses from
`broadcast/Deploy.s.sol/421614/run-latest.json` into the `address` and
`startBlock` fields of `subgraph.yaml`, and copy the ABIs from
`out/Vault.sol/Vault.json` and `out/GameItems.sol/GameItems.json` into
`subgraph/abis/`.
