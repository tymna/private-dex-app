import { useCallback, useState } from 'react'

import { estimateRemoveAmounts, formatAmount, tryParseAmount } from '../lib/amounts'
import type { Reserves } from '../types'

/**
 * Owns the remove-liquidity form's single LP-shares field and everything derived
 * from it, so the component stays presentational. Behaviour:
 *
 *   - One input: how many LP shares to burn.
 *   - `setMax` fills it with the holder's full LP balance (the common case).
 *   - `estOut` is a live preview of the token0/token1 the redemption would
 *     return, computed exactly like the contract (floor, supply-before-burn).
 */
export function useRemoveLiquidityForm(
  reserves: Reserves | undefined,
  lpSupply: bigint | undefined,
  lpBalance: bigint | undefined,
) {
  const [shares, setShares] = useState('')

  const onShares = useCallback((v: string) => setShares(v), [])

  const setMax = useCallback(() => {
    if (lpBalance !== undefined) setShares(formatAmount(lpBalance))
  }, [lpBalance])

  const reset = useCallback(() => setShares(''), [])

  const estOut =
    reserves && lpSupply !== undefined
      ? estimateRemoveAmounts({
          shares: tryParseAmount(shares) ?? 0n,
          reserve0: reserves.reserve0,
          reserve1: reserves.reserve1,
          totalSupply: lpSupply,
        })
      : undefined

  return { shares, onShares, setMax, estOut, reset }
}
