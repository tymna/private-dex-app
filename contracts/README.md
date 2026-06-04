# Private DEX

A constant-product AMM on Aztec where you add/remove liquidity and swap token A for token B. Trades are private — nobody can see *who* traded — but pool reserves and amounts stay public, since the price math has to be checked on-chain.

The trick that makes this work: a swap can't know the price while it's still private (reserves live in public state). So each action runs in two steps — a private part that spends your tokens and leaves an empty "IOU", and a public part that reads the reserves, does the math, and fills the IOU in. Those IOUs are **partial notes**.

**Aztec.nr** · **Noir**

## Highlights

**Core Logic**

- `add_liquidity` / `remove_liquidity` / `swap` — each splits into a private step and a public step
- Private step spends the caller's tokens and opens partial notes (commitments) for whatever they're owed back; `to` is sealed into each note so the payout lands in the right private balance
- Public step reads the reserves, computes amounts, and completes those notes — refunds for off-ratio deposits, token payouts for burns, output for swaps
- First liquidity provider locks a tiny `MIN_LIQUIDITY` amount (minted to the zero address) so the pool can never be fully drained and share-price-manipulated
- Caller always funds their own action — there's no "spend someone else's balance" path, because a relayer can't nullify another account's private notes

**Math**

- `mul_div(a, b, c)` = `floor(a*b/c)` without overflow — AMM ratios blow past `u128` on the intermediate product, so it does the multiply at 256-bit precision out-of-circuit and *verifies* `a*b == q*c + r` in-circuit
- `isqrt` for the initial-deposit share formula `sqrt(amount0 * amount1)`, same hint-and-verify approach
- `get_amount_out` — the `x*y=k` swap formula with a configurable fee (parts-per-10000)

**Tokens**

- `token` — the tradeable asset, with public and private balances. This is Aztec's reference [AIP-20 standard token](https://github.com/AztecProtocol/aztec-packages/tree/master/noir-projects/noir-contracts/contracts/app/token_contract), vendored as-is so the DEX has something real to deploy against — not my own work.
- `lp_token` — liquidity shares; a trimmed version of the same standard token, kept to just what the AMM needs (mint, burn, transfer, commitments, total supply). The AMM is wired in as its only minter, in a second deploy step to avoid a circular address dependency.

**Testing**

- Unit tests per feature: happy paths, slippage failures, dust/zero-share rejection, input validation
- Separate math tests covering the 256-bit helpers against known values and edge cases

## Build

```bash
# Compile (use the aztec CLI wrapper, NOT nargo directly)
aztec compile

# Run the test suite
aztec test
```

## Deploy

Deployment runs through the **Makefile** with the `aztec-wallet` CLI (no JS script) — fixed salts give stable addresses across sandbox restarts, so the frontend can hardcode them.

```bash
make sandbox        # start a local network (separate terminal, long-running)
make deploy         # import test accounts + deploy everything + shield into test0
```

`make deploy` runs these in order — the sequence is forced by the contract wiring (the lp_token needs the AMM's address as its minter, and the AMM needs the lp_token's address to mint shares — a circular dependency broken with a second step):

1. `accounts` — register the sandbox's prefunded test accounts
2. `deploy-token0` / `deploy-token1` — mint initial supply to test0's public balance
3. `deploy-amm` — `constructor(token0, token1, fee_rate=3000)`, its `lp_token` slot left empty
4. `deploy-lptoken` — deploy the lp_token with the AMM as minter
5. `set-lptoken` — `amm.set_lp_token(...)` fills the AMM's empty slot; it asserts the AMM really is the lp_token's minter, so bad wiring fails loudly
6. `to-private` — shield both tokens from test0's public balance into its private balance

Each deploy target upserts its address into `addresses.json` (jq required). Run once per fresh sandbox; after a restart: `rm -rf ~/.aztec/wallet && make deploy`.

---

*Study project for learning Aztec's private-execution model and the partial-note pattern.*
