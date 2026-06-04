import { useRemoveLiquidity } from '../hooks/useRemoveLiquidity'
import { useRemoveLiquidityForm } from '../hooks/useRemoveLiquidityForm'
import { formatDisplay as fmt, sanitizeDecimal, tryParseAmount } from '../lib/amounts'
import type { Reserves } from '../types'

type Props = {
  reserves?: Reserves
  lpSupply?: bigint
  /** The holder's private LP balance — drives Max + bounds the input. */
  lpBalance?: bigint
  /** Re-read balances + reserves after a successful removal. */
  refresh: () => Promise<void> | void
}

/**
 * The remove-liquidity form body. The shares field + Max + output estimate live
 * in useRemoveLiquidityForm; the tx + authwit live in useRemoveLiquidity. We
 * block burning more LP than is held.
 */
export function RemoveLiquidityForm({ reserves, lpSupply, lpBalance, refresh }: Props) {
  const { shares, onShares, setMax, estOut, reset } = useRemoveLiquidityForm(
    reserves,
    lpSupply,
    lpBalance,
  )
  const { submit, pending, error } = useRemoveLiquidity(refresh)

  const parsed = tryParseAmount(shares)
  const insufficient = parsed !== undefined && lpBalance !== undefined && parsed > lpBalance

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        void submit(shares).then((ok) => {
          if (ok) reset()
        })
      }}
    >
      <div className="field">
        <div className="field-top">
          <span className="field-label">LP shares</span>
          <button
            type="button"
            className="bal"
            disabled={lpBalance === undefined || lpBalance === 0n}
            onClick={setMax}
          >
            Balance {fmt(lpBalance)} · Max
          </button>
        </div>
        <div className="input-wrap">
          <input
            value={shares}
            onChange={(e) => onShares(sanitizeDecimal(e.target.value))}
            placeholder="0.0"
            inputMode="decimal"
            className={insufficient ? 'over' : undefined}
          />
          <span className="unit">LP</span>
        </div>
      </div>

      {estOut && (
        <p className="hint">
          You'll receive ≈ <b>{fmt(estOut.amount0)}</b> token0 + <b>{fmt(estOut.amount1)}</b> token1
        </p>
      )}

      <button type="submit" disabled={pending || !shares || insufficient}>
        {insufficient ? 'Insufficient balance' : pending ? 'Removing…' : 'Remove liquidity'}
      </button>

      {error && <p className="error">Error: {error}</p>}
    </form>
  )
}
