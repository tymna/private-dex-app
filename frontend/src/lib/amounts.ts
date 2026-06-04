// Pure fixed-point helpers shared by the UI and the wallet service. Token
// amounts are 18-decimal: the human "1.5" is the on-chain 1500000000000000000n.
// No React, no Aztec — just bigint math, so this stays unit-testable and matches
// the contract's integer arithmetic exactly.

const DECIMALS = 18n
const ONE = 10n ** DECIMALS

// Matches `global MIN_LIQUIDITY` in amm/src/main.nr — the dust locked to the zero
// address on the first-ever deposit, subtracted from the initial depositor's shares.
const MIN_LIQUIDITY = 1000n

/** Human "1.5" → raw bigint (1500000000000000000n). Throws on non-numeric input. */
export function parseAmount(input: string): bigint {
  const s = input.trim()
  if (!/^\d+(\.\d+)?$/.test(s)) throw new Error(`Invalid amount: "${input}"`)
  const [whole, frac = ''] = s.split('.')
  return BigInt(whole) * ONE + BigInt(frac.padEnd(18, '0').slice(0, 18))
}

/**
 * Sanitize a live-typed amount to a valid decimal: digits and at most one dot.
 * "0.00.0.0" → "0.000", "1a2" → "12", "1.2.3" → "1.23". Lets the user keep
 * typing (a trailing "." is allowed) while making malformed input impossible.
 */
export function sanitizeDecimal(input: string): string {
  const s = input.replace(/[^\d.]/g, '')
  const dot = s.indexOf('.')
  if (dot === -1) return s
  // keep the first dot, strip any later ones
  return s.slice(0, dot + 1) + s.slice(dot + 1).replace(/\./g, '')
}

/** Like parseAmount but returns undefined instead of throwing — for live typing. */
export function tryParseAmount(input: string): bigint | undefined {
  try {
    return parseAmount(input)
  } catch {
    return undefined
  }
}

/** Raw bigint → human string, trailing zeros trimmed (1500000000000000000n → "1.5"). */
export function formatAmount(v: bigint | undefined): string {
  if (v === undefined) return '—'
  const whole = v / ONE
  const frac = (v % ONE).toString().padStart(18, '0').replace(/0+$/, '')
  return frac ? `${whole}.${frac}` : `${whole}`
}

/**
 * Display formatter for the UI: rounds to `decimals` places (half-up) and groups
 * thousands — `999.697106…` → "999.70". The full-precision value still lives in
 * the bigint; this is purely what we show. A non-zero amount that rounds to all
 * zeros shows "<0.01" so tiny dust never reads as exactly 0.
 */
export function formatDisplay(v: bigint | undefined, decimals = 2): string {
  if (v === undefined) return '—'
  const scale = 10n ** BigInt(decimals)
  // round to `decimals`: scale into integer units, add half, floor
  const scaled = (v * scale + ONE / 2n) / ONE
  if (v > 0n && scaled === 0n) return `<0.${'0'.repeat(decimals - 1)}1`
  const whole = scaled / scale
  const frac = (scaled % scale).toString().padStart(decimals, '0')
  return `${whole.toLocaleString('en-US')}.${frac}`
}

/**
 * The paired deposit amount that keeps the pool's current ratio, so the AMM
 * uses both sides fully and refunds ~nothing:
 *
 *     amountOut = amountIn * reserveOut / reserveIn   (floor division)
 *
 * Returns undefined when `reserveIn` is 0 — i.e. an empty pool, where there is
 * no ratio yet and the first depositor sets the price themselves (no auto-fill).
 */
export function quotePairedAmount(
  amountIn: bigint,
  reserveIn: bigint,
  reserveOut: bigint,
): bigint | undefined {
  if (reserveIn === 0n) return undefined
  return (amountIn * reserveOut) / reserveIn
}

/** Integer square root (floor) for bigint — the JS twin of the contract's isqrt_u256. */
function isqrt(n: bigint): bigint {
  if (n < 0n) throw new Error('isqrt of negative')
  if (n < 2n) return n
  let x = n
  let y = (x + 1n) / 2n
  while (y < x) {
    x = y
    y = (x + n / x) / 2n
  }
  return x
}

/**
 * The LP shares an add-liquidity deposit would mint, mirroring _add_liquidity in
 * amm/src/main.nr exactly (floor division throughout, so it agrees with the chain):
 *
 *   - empty pool (supply 0): sqrt(amount0 · amount1) − MIN_LIQUIDITY
 *   - otherwise:             min(amount0·supply/reserve0, amount1·supply/reserve1)
 *
 * Returns undefined when there's nothing meaningful to quote (a zero input, or an
 * initial deposit too small to clear MIN_LIQUIDITY — which the contract rejects).
 * All values are raw 18-decimal bigints; format with formatAmount for display.
 */
export function estimateLpShares(p: {
  amount0: bigint
  amount1: bigint
  reserve0: bigint
  reserve1: bigint
  totalSupply: bigint
}): bigint | undefined {
  const { amount0, amount1, reserve0, reserve1, totalSupply } = p
  if (amount0 <= 0n || amount1 <= 0n) return undefined

  if (totalSupply === 0n) {
    const root = isqrt(amount0 * amount1)
    return root > MIN_LIQUIDITY ? root - MIN_LIQUIDITY : undefined
  }

  if (reserve0 === 0n || reserve1 === 0n) return undefined
  const s0 = (amount0 * totalSupply) / reserve0
  const s1 = (amount1 * totalSupply) / reserve1
  return s0 < s1 ? s0 : s1
}

/**
 * The token0 / token1 a remove-liquidity redemption of `shares` would return,
 * mirroring _remove_liquidity in amm/src/main.nr exactly (floor division, and
 * totalSupply read BEFORE the burn so the denominator still includes the
 * redeemed shares — the correct proportion):
 *
 *   amountN = shares · reserveN / totalSupply
 *
 * Returns undefined when there's nothing meaningful to quote (zero shares or an
 * empty pool). All values are raw 18-decimal bigints; format with formatAmount.
 */
export function estimateRemoveAmounts(p: {
  shares: bigint
  reserve0: bigint
  reserve1: bigint
  totalSupply: bigint
}): { amount0: bigint; amount1: bigint } | undefined {
  const { shares, reserve0, reserve1, totalSupply } = p
  if (shares <= 0n || totalSupply === 0n) return undefined
  return {
    amount0: (shares * reserve0) / totalSupply,
    amount1: (shares * reserve1) / totalSupply,
  }
}

/**
 * The exact-input swap output, mirroring get_amount_out in amm/src/math.nr:
 *
 *   inWithFee = amountIn · (10000 − feeRate)              (feeRate is parts-per-10000)
 *   amountOut = inWithFee · reserveOut
 *               ─────────────────────────────
 *               reserveIn · 10000 + inWithFee            (floor)
 *
 * Bigint math, so the intermediate product can't overflow (the contract needs
 * mul_div for the same reason; here it's free). Returns undefined when there's
 * nothing to quote — zero input or an empty side of the pool.
 */
export function estimateSwapOut(p: {
  amountIn: bigint
  reserveIn: bigint
  reserveOut: bigint
  feeRate: bigint
}): bigint | undefined {
  const { amountIn, reserveIn, reserveOut, feeRate } = p
  if (amountIn <= 0n || reserveIn === 0n || reserveOut === 0n) return undefined
  const inWithFee = amountIn * (10000n - feeRate)
  return (inWithFee * reserveOut) / (reserveIn * 10000n + inWithFee)
}
