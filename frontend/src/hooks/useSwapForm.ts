import { useCallback, useState } from 'react'

import { estimateSwapOut, tryParseAmount } from '../lib/amounts'
import type { Reserves } from '../types'

/**
 * Owns the swap form's amount field + direction toggle, so the component stays
 * presentational. Behaviour:
 *
 *   - `zeroForOne` is the direction: true = token0 in → token1 out, false = the
 *     reverse. `flip` toggles it; the live estimate re-points reserve in/out.
 *   - `estOut` is the output preview, priced exactly like the contract
 *     (get_amount_out, net of fee). undefined while the input is empty/invalid.
 */
export function useSwapForm(reserves: Reserves | undefined, feeRate: bigint | undefined) {
  const [amountIn, setAmountIn] = useState('')
  const [zeroForOne, setZeroForOne] = useState(true)

  const onAmountIn = useCallback((v: string) => setAmountIn(v), [])
  const flip = useCallback(() => setZeroForOne((d) => !d), [])
  const reset = useCallback(() => setAmountIn(''), [])

  const estOut =
    reserves && feeRate !== undefined
      ? estimateSwapOut({
          amountIn: tryParseAmount(amountIn) ?? 0n,
          reserveIn: zeroForOne ? reserves.reserve0 : reserves.reserve1,
          reserveOut: zeroForOne ? reserves.reserve1 : reserves.reserve0,
          feeRate,
        })
      : undefined

  return { amountIn, onAmountIn, zeroForOne, flip, estOut, reset }
}
