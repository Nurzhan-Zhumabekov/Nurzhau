# Task 5 — Chainlink Oracle Integration

## Architecture

Three contracts, each with a single responsibility:

1. **`PriceFeedConsumer.sol`** — wraps a Chainlink `AggregatorV3` feed and
   exposes `getLatestPrice()`, `ethToUsd(uint256)`, `usdToEth(uint256)` in a
   normalised 18-decimal scale. All staleness, sign, and round-completeness
   checks live here. Other contracts depend only on this thin interface,
   not on the raw aggregator.
2. **`PriceDependentVault.sol`** — accepts native ETH deposits up to a fixed
   USD ceiling. Per-user holdings are stored in ETH but the cap is checked in
   USD at the current oracle price, so as ETH/USD moves the available headroom
   moves with it. This is a deliberate, observable consequence of using an
   oracle in business logic.
3. **`MockAggregator.sol`** — a Chainlink-shaped mock with setters for the
   answer, the `updatedAt` timestamp, the round id, and the `answeredInRound`
   field. Tests use it to construct adversarial round states cheaply.

## Stale-price handling

Chainlink price feeds publish a new round only when the price has moved by
more than the deviation threshold or the heartbeat has elapsed. Reading a
feed without checking `updatedAt` would let an attacker exploit a paused or
mis-aggregated feed during a market dislocation. `PriceFeedConsumer` rejects:

- `updatedAt == 0` or `answeredInRound < roundId` — round wasn't finalised
  (`IncompleteRound`).
- `block.timestamp - updatedAt > maxStaleness` — the feed exceeded its
  expected heartbeat (`StalePrice`).
- `answer <= 0` — physically impossible for ETH/USD; treat as a corrupt
  feed (`NegativePrice`).

`maxStaleness` is set in the constructor; for ETH/USD on Sepolia we'd use
`3600` (the 1-hour heartbeat). On a faster-heartbeat feed you tighten it.

## Decimal normalisation

ETH/USD on mainnet uses 8 decimals; some feeds are 18, some are even less.
`getLatestPrice` scales the raw answer to a fixed 18-decimal output, so the
rest of the codebase only ever multiplies by `1e18` and never has to inspect
`feed.decimals()`. This makes the calling code (`ethToUsd`, the vault cap
check) immune to feed-level decimal differences.

## Why `vm.mockCall` matters

Live integration with a Sepolia feed is slow (RPC roundtrip per test) and
non-deterministic (real prices move). Foundry's `vm.mockCall` lets us hand-
roll a fake aggregator response from inside the test, exercising the
consumer logic without ever leaving the local EVM. `test_MockedFeedViaCheatcode`
in `test/PriceFeed.t.sol` shows the pattern: we register synthetic
`decimals()` and `latestRoundData()` answers at an arbitrary address, deploy
a fresh consumer pointed at that address, and assert the normalisation
worked end-to-end. The `MockAggregator` contract is the higher-level
counterpart for stateful scenarios (multiple rounds, staleness, etc.).

## Tests

`test/PriceFeed.t.sol` covers 12 cases: 18-decimal normalisation across
8-decimal and 18-decimal feeds, ETH⇄USD conversion, staleness rejection,
incomplete-round rejection, negative-price rejection, vault deposit/withdraw
under the USD cap, the cap moving with the oracle price, and the
`vm.mockCall` end-to-end flow. All 12 pass.
