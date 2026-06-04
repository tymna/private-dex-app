// Shared domain shapes used across the service, hooks, and components. All token
// amounts are raw 18-decimal bigints (format with lib/amounts.formatAmount).

/** A holder's private (shielded) balances. */
export type Balances = { token0: bigint; token1: bigint; lp: bigint }

/** The AMM's public reserves — the pool's pricing state. */
export type Reserves = { reserve0: bigint; reserve1: bigint }
