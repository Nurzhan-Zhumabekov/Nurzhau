# Task 2 — ERC-4626 Vault

## What ERC-4626 standardises

EIP-4626 fixes the surface that yield-bearing vaults expose. Before 4626 every
protocol invented its own deposit / withdraw signature, so wallets and
aggregators had to integrate each one separately. 4626 mandates a fixed
ERC-20-compatible share token plus four mutating entry points (`deposit`,
`mint`, `withdraw`, `redeem`), four matching `preview*` helpers that simulate
the call without state changes, and a `convertToShares` / `convertToAssets`
pair for off-chain pricing. Because the shares are an ordinary ERC-20, anything
that already understands an ERC-20 — DEXes, lending markets, accounting tools —
gets vault support for free.

## Implementation choices in Vault.sol

- **Single underlying.** `asset` is set in the constructor and is immutable;
  `decimals` is mirrored from the asset, which keeps the share token decimals
  semantically aligned with what the user deposits.
- **Virtual shares & assets.** `_convertToShares` / `_convertToAssets` add a
  phantom `+1 share / +1 asset` to both sides of the ratio. This is the
  standard mitigation against the "first-depositor inflation" attack, where an
  adversary deposits 1 wei to mint 1 share, then donates a large amount of
  underlying directly into the vault to make every subsequent deposit round
  down to zero shares. With virtual offsets the attacker eats most of the
  donation themselves.
- **Rounding follows the spec.** `previewDeposit` / `previewRedeem` round
  *down* (the user gets at most the displayed value); `previewMint` /
  `previewWithdraw` round *up* (the user pays at least the displayed value).
  The internal `_mulDivUp` helper makes this explicit instead of relying on
  ad-hoc `+1` corrections.
- **Yield via `harvest()`.** Owner-only; pulls `yieldAmount` of underlying
  from the owner's balance into the vault. Because total supply of shares is
  unchanged but `totalAssets()` grew, every existing holder's
  `previewRedeem(shares)` value goes up — the standard accrual model.
  `Harvest` event records the new total so a subgraph can chart APR.
- **Allowance reuse.** Withdraw / redeem accept `(receiver, owner)`; if a
  third party calls them on behalf of `owner`, the share allowance is debited.
  This is the same pattern as ERC-20 `transferFrom`, so wallets that already
  approve vault shares "just work."

## Tests

`test/Vault.t.sol` covers 16 cases: metadata, first-depositor 1:1 ratio,
deposit ⇄ redeem round-trip (fuzz, 256 runs), `harvest` lifting share value,
yield split between two depositors, rounding direction, allowance flows for
third-party redeem, share-token transfers, and revert paths (zero amount,
zero receiver, non-owner harvest, insufficient allowance). All 16 pass.
