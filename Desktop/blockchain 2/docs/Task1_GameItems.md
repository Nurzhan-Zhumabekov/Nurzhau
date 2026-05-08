# Task 1 — ERC-1155 GameItems

## Why ERC-1155 fits a game economy

A game like ours needs two very different kinds of assets in one wallet view:
fungible **resources** (gold, gems, wood) that exist in millions of identical
copies, and unique **artifacts** (a specific sword, a specific shield) that are
non-fungible. Issuing each of those as a separate ERC-20 + ERC-721 contract
forces players to pay gas to a different address for every interaction and
forces clients to query each contract independently. ERC-1155 collapses both
families into a single contract with one storage layout
(`balances[id][account]`), one approval system (`setApprovalForAll`), and one
batched transfer call (`safeBatchTransferFrom`) — so equipping a hero with
a sword, a shield, and 200 gems costs one transaction instead of three, and
one indexer subscription instead of three.

## How GameItems uses the standard

- **Token IDs as namespaces.** IDs `1–3` are reserved for fungible resources
  (`GOLD`, `GEM`, `WOOD`) and IDs `100+` for NFTs (`SWORD`, `SHIELD`). The
  `_isFungible / _isNFT` helpers gate which mint paths are legal: NFTs must
  have `amount == 1` and may only be minted once (`totalSupply[id] == 0`),
  while fungible resources can be minted in any quantity.
- **Metadata.** `uri(uint256)` returns a single base string containing the
  `{id}` placeholder, exactly per EIP-1155 §metadata; clients substitute the
  lowercase hex token id at render time, which lets us serve every item
  type from the same JSON template.
- **Crafting.** `craftSword()` and `craftShield()` are the headline gameplay
  mechanic. They burn fungible inputs (`100 GOLD + 50 WOOD` for a sword,
  `200 GOLD + 5 GEM` for a shield) and mint a single NFT to the caller in
  the same transaction, emitting `Crafted(crafter, outputId, amount)` so an
  off-chain leaderboard can index forge activity directly.
- **Safety.** Every mint and transfer that lands at a contract address goes
  through `_doSafeTransferAcceptanceCheck`, which calls
  `IERC1155Receiver.onERC1155Received` and reverts with
  `NonERC1155Receiver` if the receiver returns the wrong magic value or
  doesn't implement the hook — preventing tokens from being silently locked
  in a non-aware contract.

## Tests

`test/GameItems.t.sol` covers 16 cases: mint/burn for fungibles, NFT
uniqueness, batched mint and transfer, operator approval flows, the receiver
hook (both compliant and non-compliant), the crafting recipe, URI metadata,
and ERC-165 interface support. All 16 pass under `forge test --match-contract
GameItemsTest`.
