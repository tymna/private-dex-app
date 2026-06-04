# Aztec Project

## Critical: Use `aztec` CLI, not `nargo` directly

This is an Aztec smart contract project. Always use the `aztec` CLI wrapper instead of calling `nargo` directly:

- **Compile**: `aztec compile` (NOT `nargo compile`). Using `nargo compile` alone produces incomplete artifacts.
- **Test**: `aztec test` (NOT `nargo test`).
- **Other nargo commands** like `aztec-nargo fmt` and `aztec-nargo doc` are fine to use directly. The Aztec installer exposes the bundled `nargo` as `aztec-nargo`; bare `nargo` resolves to your own install (if any), not the bundled one.

## Error Handling

- NEVER silently swallow errors or fall back to default values. If a value is required, throw if it's missing.
- NEVER use fallback values like `AztecAddress.ZERO`, `"unknown"`, `0`, or `null` to mask missing data. These hide bugs and cause failures elsewhere that are harder to trace.
- NEVER add retry/polling logic unless explicitly asked. Retry loops with long timeouts may brick application loops and mask the real error.
- NEVER wrap calls in try/catch that returns null or a default. Let errors propagate.
- If a precondition isn't met, throw immediately with a descriptive message — don't try to "work around" it.
- Prefer `T` return types over `T | null` when null would indicate a bug rather than a valid state.
- Do not add `.catch(() => defaultValue)` to promises. If something fails, the caller needs to know.

## Hashing: Default to Poseidon2

When writing Aztec.nr contract code that requires hashing, **always use Poseidon2** unless a specific protocol or interoperability requirement calls for a different hash.

- **Default**: `use aztec::protocol::hash::poseidon2_hash;`
- **Do NOT** default to Pedersen (`pedersen_hash`). Pedersen is available but Poseidon2 is cheaper in circuits and is the standard across Aztec.
- If you are unsure which hash to use, use Poseidon2.

## Progress

All three core flows follow the same two-step / partial-note pattern: the private half pulls input into the AMM's public balance and opens commitments (the recipient `to` is sealed in, the AMM is the completer), then enqueues a public half that reads the public reserves, does the math, and completes the commitments. No on-behalf-of `from`/`authorize_once` anywhere: a relayer can't nullify another account's private notes, so the caller (`self.msg_sender()`) always funds and `to` routes the output.

- **add_liquidity**: implemented. `add_liquidity(to, amount0_max, amount1_max, amount0_min, amount1_min, authwit_nonce)` — caller funds, `to` receives shares + refunds.
- **remove_liquidity**: implemented. `remove_liquidity(to, shares, amount0_min, amount1_min, authwit_nonce)` — burns the caller's LP shares, pays both tokens to `to`. Supply floors at MIN_LIQUIDITY (locked on initial deposit), so the pool can never be fully drained.
- **swap**: implemented (exact input). `swap(to, token_in, amount_in, amount_out_min, transfer_nonce)` — `token_in` is an address; direction (`zero_for_one`) is derived once in private and passed to the public `_swap`, which prices via `get_amount_out` (CPMM net of `fee_rate`, in parts-per-10000) and completes ONE output commitment. Whole input consumed → no input refund. Fee accrues to reserves (LPs).
- **math** (`amm/src/math.nr`): `mul_div` (256-bit hint+verify, divisor must be ≤ 2^127), `isqrt_u256`, `get_amount_out`. Unit-tested with hand-computed oracles.
- **tests**: `add_liquidity.nr`, `remove_liquidity.nr`, `swap.nr` (2 happy + to≠from + 4 failures), `math.nr`, `initial_state.nr`. Shared `utils::snapshot` (PoolSnapshot: reserves + an account's private token/LP balances + AMM public custody + supply) collapses before/after assertions. `flows.nr` has multi-op lifecycle tests.
- **NEXT**: deployment — Aztec.js / aztec-wallet deploy script (deploy token0, token1, AMM with `constructor(token0, token1, fee_rate)`, then the lp_token with the AMM as minter, then `set_lp_token`).

## Notes

- Run with **Node 22** (not 24 — TXE/LMDB is unstable on 24). Use either `aztec test` alone OR a standalone `aztec start --txe`, never both (two TXEs on :8081 corrupt the LMDB world-state).

aztec standards: <https://docs.aztec.network/developers/docs/aztec-nr/standards/aip-4626>

example of dex:
<https://github.com/AztecProtocol/aztec-packages/blob/v4.3.0/noir-projects/noir-contracts/contracts/app/amm_contract/src/main.nr#L194>
