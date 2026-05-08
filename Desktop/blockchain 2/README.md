# Blockchain Technologies 2 — Assignment 3

**Layer 2 Deployment & Oracle Integration**
Author: Nurzhan Zhumabekov

This repository implements all six tasks of Assignment 3:

| Task | Subject                              | Files                                                                                |
|------|--------------------------------------|--------------------------------------------------------------------------------------|
| 1    | ERC-1155 game items                  | [src/GameItems.sol](src/GameItems.sol) · [test/GameItems.t.sol](test/GameItems.t.sol) · [docs/Task1_GameItems.md](docs/Task1_GameItems.md) |
| 2    | ERC-4626 vault                       | [src/Vault.sol](src/Vault.sol) · [test/Vault.t.sol](test/Vault.t.sol) · [docs/Task2_Vault.md](docs/Task2_Vault.md) |
| 3    | L2 deployment + gas analysis         | [script/Deploy.s.sol](script/Deploy.s.sol) · [script/Interact.s.sol](script/Interact.s.sol) · [docs/Task3_L2_Deployment.md](docs/Task3_L2_Deployment.md) |
| 4    | Theoretical analysis                 | [docs/Task4_Theoretical_Analysis.md](docs/Task4_Theoretical_Analysis.md)             |
| 5    | Chainlink oracle integration         | [src/PriceFeedConsumer.sol](src/PriceFeedConsumer.sol) · [src/PriceDependentVault.sol](src/PriceDependentVault.sol) · [src/MockAggregator.sol](src/MockAggregator.sol) · [test/PriceFeed.t.sol](test/PriceFeed.t.sol) · [docs/Task5_Chainlink.md](docs/Task5_Chainlink.md) |
| 6    | The Graph subgraph                   | [subgraph/](subgraph/) · [docs/Task6_Subgraph.md](docs/Task6_Subgraph.md)            |

## Quick start

```bash
forge install                # forge-std is already vendored under lib/
forge build
forge test                   # 44 tests, all pass
forge test --gas-report      # gas table reproduced in Task 3 doc
```

## Deploy to Arbitrum Sepolia

The whole task-3 deployment is wrapped in `script/deploy.sh`, which runs all
three Forge scripts in order, parses the broadcast JSON, and patches the
deployed addresses into [docs/Task3_L2_Deployment.md](docs/Task3_L2_Deployment.md)
and [subgraph/subgraph.yaml](subgraph/subgraph.yaml).

```bash
cp .env.example .env
# fill in PRIVATE_KEY, ARBITRUM_SEPOLIA_RPC_URL, ARBISCAN_API_KEY
./script/deploy.sh
```

Manual equivalent (one script per stage):

```bash
forge script script/Deploy.s.sol:Deploy \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify

PRICE_FEED=0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165 \
forge script script/DeployOracle.s.sol:DeployOracle \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify

GAME_ITEMS=0x... VAULT=0x... USDS=0x... \
forge script script/Interact.s.sol:Interact \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast
```

## Deploy the subgraph

ABIs are pre-extracted under [subgraph/abis/](subgraph/abis/), so once the
contracts are deployed and `subgraph.yaml` has the right addresses (auto-
patched by `deploy.sh`), the subgraph deploy is one command:

```bash
cd subgraph
npm install
graph codegen
graph build
graph auth --studio <DEPLOY_KEY>
graph deploy --studio blockchain2-assignment3
```

## Test summary

```
Ran 3 test suites: 44 tests passed, 0 failed, 0 skipped (44 total)
- GameItems.t.sol  — 16 tests
- Vault.t.sol      — 16 tests (incl. 256-run fuzz)
- PriceFeed.t.sol  — 12 tests (incl. vm.mockCall integration)
```
