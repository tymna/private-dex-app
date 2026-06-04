import { useCallback, useState } from 'react'

import { estimateLpShares, formatAmount, quotePairedAmount, tryParseAmount } from '../lib/amounts'
import type { Reserves } from '../types'

/**
 * Owns the add-liquidity form's two amount fields and everything derived from
 * them, so the component stays presentational. Behaviour:
 *
 *   - Typing a valid number in one field auto-fills the other at the pool's
 *     current ratio (so the AMM uses both sides fully, no refund).
 *   - Clearing a field (emptying it) clears the other too — you can't add a
 *     one-sided deposit, so a blank input means "start over".
 *   - Mid-edit junk ("1.") leaves the other field untouched until it parses.
 *   - `estShares` is a live preview of the LP shares the deposit would mint.
 *
 * Auto-fill never loops: onChange fires only on user input, and we set the
 * *other* field, which doesn't re-enter the handler we're in.
 */
export function useLiquidityForm(reserves: Reserves | undefined, lpSupply: bigint | undefined) {
  const [amount0, setAmount0] = useState('')
  const [amount1, setAmount1] = useState('')

  const onAmount0 = useCallback(
    (v: string) => {
      setAmount0(v)
      if (v.trim() === '') return setAmount1('')
      const raw = tryParseAmount(v)
      if (raw === undefined || !reserves) return
      const paired = quotePairedAmount(raw, reserves.reserve0, reserves.reserve1)
      if (paired !== undefined) setAmount1(formatAmount(paired))
    },
    [reserves],
  )

  const onAmount1 = useCallback(
    (v: string) => {
      setAmount1(v)
      if (v.trim() === '') return setAmount0('')
      const raw = tryParseAmount(v)
      if (raw === undefined || !reserves) return
      const paired = quotePairedAmount(raw, reserves.reserve1, reserves.reserve0)
      if (paired !== undefined) setAmount0(formatAmount(paired))
    },
    [reserves],
  )

  const reset = useCallback(() => {
    setAmount0('')
    setAmount1('')
  }, [])

  const estShares =
    reserves && lpSupply !== undefined
      ? estimateLpShares({
          amount0: tryParseAmount(amount0) ?? 0n,
          amount1: tryParseAmount(amount1) ?? 0n,
          reserve0: reserves.reserve0,
          reserve1: reserves.reserve1,
          totalSupply: lpSupply,
        })
      : undefined

  return { amount0, amount1, onAmount0, onAmount1, estShares, reset }
}
