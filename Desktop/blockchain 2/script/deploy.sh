#!/usr/bin/env bash
# One-shot deployment driver for Assignment 3.
#
# Usage:
#   1. cp .env.example .env  (fill in PRIVATE_KEY, ARBITRUM_SEPOLIA_RPC_URL,
#      ARBISCAN_API_KEY)
#   2. ./script/deploy.sh
#
# Chains:
#   - Deploy.s.sol         -> GameItems, MockERC20 (USDS), Vault
#   - DeployOracle.s.sol   -> PriceFeedConsumer, PriceDependentVault
#   - Interact.s.sol       -> >=5 meaningful transactions
#
# Then parses the broadcast JSON files, prints a summary, and patches the
# deployed addresses into docs/Task3_L2_Deployment.md and
# subgraph/subgraph.yaml so the artifacts in the repo match reality.

set -euo pipefail

# ----- env -----
if [[ -f .env ]]; then
    set -a; source .env; set +a
else
    echo "[error] .env not found. Copy .env.example to .env and fill in values."
    exit 1
fi

: "${PRIVATE_KEY:?PRIVATE_KEY must be set in .env}"
: "${ARBITRUM_SEPOLIA_RPC_URL:?ARBITRUM_SEPOLIA_RPC_URL must be set in .env}"

CHAIN_ID=421614  # Arbitrum Sepolia
PRICE_FEED_ARB_SEPOLIA="0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165"

VERIFY_FLAG=""
if [[ -n "${ARBISCAN_API_KEY:-}" ]]; then
    VERIFY_FLAG="--verify"
fi

echo "[1/3] Deploying GameItems + MockERC20 + Vault..."
forge script script/Deploy.s.sol:Deploy \
    --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast $VERIFY_FLAG

DEPLOY_JSON="broadcast/Deploy.s.sol/${CHAIN_ID}/run-latest.json"

GAME_ITEMS=$(node -e "const j=require('./${DEPLOY_JSON}'); const tx=j.transactions.find(t=>t.contractName==='GameItems'); console.log(tx.contractAddress)")
USDS=$(node -e "const j=require('./${DEPLOY_JSON}'); const tx=j.transactions.find(t=>t.contractName==='MockERC20'); console.log(tx.contractAddress)")
VAULT=$(node -e "const j=require('./${DEPLOY_JSON}'); const tx=j.transactions.find(t=>t.contractName==='Vault'); console.log(tx.contractAddress)")
DEPLOY_BLOCK=$(node -e "const j=require('./${DEPLOY_JSON}'); console.log(parseInt(j.receipts[0].blockNumber, 16))")

echo "  GameItems  = $GAME_ITEMS"
echo "  MockERC20  = $USDS"
echo "  Vault      = $VAULT"

echo "[2/3] Deploying PriceFeedConsumer + PriceDependentVault..."
PRICE_FEED="$PRICE_FEED_ARB_SEPOLIA" \
forge script script/DeployOracle.s.sol:DeployOracle \
    --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast $VERIFY_FLAG

ORACLE_JSON="broadcast/DeployOracle.s.sol/${CHAIN_ID}/run-latest.json"
CONSUMER=$(node -e "const j=require('./${ORACLE_JSON}'); const tx=j.transactions.find(t=>t.contractName==='PriceFeedConsumer'); console.log(tx.contractAddress)")
PD_VAULT=$(node -e "const j=require('./${ORACLE_JSON}'); const tx=j.transactions.find(t=>t.contractName==='PriceDependentVault'); console.log(tx.contractAddress)")

echo "  PriceFeedConsumer    = $CONSUMER"
echo "  PriceDependentVault  = $PD_VAULT"

echo "[3/3] Sending >=5 interaction transactions..."
GAME_ITEMS="$GAME_ITEMS" VAULT="$VAULT" USDS="$USDS" \
forge script script/Interact.s.sol:Interact \
    --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast

echo "[patch] Writing addresses into docs/Task3_L2_Deployment.md..."
python3 - "$GAME_ITEMS" "$USDS" "$VAULT" "$CONSUMER" "$PD_VAULT" <<'PY'
import sys, re, pathlib
gi, usds, vault, consumer, pd = sys.argv[1:6]
path = pathlib.Path("docs/Task3_L2_Deployment.md")
text = path.read_text(encoding="utf-8")
table = (
    "| `GameItems`             | `" + gi + "` | ✅       |\n"
    "| `MockERC20` (USDS)      | `" + usds + "` | ✅       |\n"
    "| `Vault` (vUSDS)         | `" + vault + "` | ✅       |\n"
    "| `PriceFeedConsumer`     | `" + consumer + "` | ✅       |\n"
    "| `PriceDependentVault`   | `" + pd + "` | ✅       |"
)
text = re.sub(
    r"\| `GameItems`.*\n\| `MockERC20`.*\n\| `Vault`.*\n\| `PriceFeedConsumer`.*\n\| `PriceDependentVault`.*",
    table,
    text,
    flags=re.MULTILINE,
)
path.write_text(text, encoding="utf-8")
print("  patched docs/Task3_L2_Deployment.md")
PY

echo "[patch] Writing addresses into subgraph/subgraph.yaml..."
python3 - "$GAME_ITEMS" "$VAULT" "$DEPLOY_BLOCK" <<'PY'
import sys, pathlib, re
gi, vault, block = sys.argv[1:4]
path = pathlib.Path("subgraph/subgraph.yaml")
text = path.read_text(encoding="utf-8")
# Replace per-source.
def patch(text, name, addr):
    pattern = re.compile(
        r'(  - kind: ethereum/contract\s+name: ' + re.escape(name) + r'.*?source:\s+address: ")[^"]+(".*?startBlock: )\d+',
        re.DOTALL,
    )
    return pattern.sub(r'\g<1>' + addr + r'\g<2>' + str(block), text)
text = patch(text, "Vault", vault)
text = patch(text, "GameItems", gi)
path.write_text(text, encoding="utf-8")
print("  patched subgraph/subgraph.yaml")
PY

cat <<EOF

==========================================
Deployment complete.

GameItems            $GAME_ITEMS
MockERC20 (USDS)     $USDS
Vault (vUSDS)        $VAULT
PriceFeedConsumer    $CONSUMER
PriceDependentVault  $PD_VAULT

Next:
  cd subgraph
  npm install
  graph codegen
  graph build
  graph auth --studio <DEPLOY_KEY>
  graph deploy --studio blockchain2-assignment3
==========================================
EOF
