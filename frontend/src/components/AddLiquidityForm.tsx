import { useAddLiquidity } from '../hooks/useAddLiquidity'
import { useLiquidityForm } from '../hooks/useLiquidityForm'
import { formatAmount, formatDisplay as fmt, sanitizeDecimal, tryParseAmount } from '../lib/amounts'
import type { Balances, Reserves } from '../types'

type Props = {
  reserves?: Reserves
  lpSupply?: bigint
  /** Private balances — bound each side + power the per-field Max. */
  balances?: Balances
  /** Re-read balances + reserves after a successful add. */
  refresh: () => Promise<void> | void
}

/**
 * The add-liquidity form body. Ratio auto-fill + shares estimate live in
 * useLiquidityForm; the tx + authwits live in useAddLiquidity. We block
 * submitting more than is held on either side.
 */
export function AddLiquidityForm({ reserves, lpSupply, balances, refresh }: Props) {
  const { amount0, amount1, onAmount0, onAmount1, estShares, reset } = useLiquidityForm(
    reserves,
    lpSupply,
  )
  const { submit, pending, error } = useAddLiquidity(refresh)

  const p0 = tryParseAmount(amount0)
  const p1 = tryParseAmount(amount1)
  const over0 = p0 !== undefined && balances?.token0 !== undefined && p0 > balances.token0
  const over1 = p1 !== undefined && balances?.token1 !== undefined && p1 > balances.token1
  const insufficient = over0 || over1

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        void submit(amount0, amount1).then((ok) => {
          if (ok) reset()
        })
      }}
    >
      <div className="field">
        <div className="field-top">
          <span className="field-label">Token 0</span>
          <button
            type="button"
            className="bal"
            disabled={balances?.token0 === undefined || balances.token0 === 0n}
            onClick={() => balances && onAmount0(formatAmount(balances.token0))}
          >
            Balance {fmt(balances?.token0)} · Max
          </button>
        </div>
        <div className="input-wrap">
          <input
            value={amount0}
            onChange={(e) => onAmount0(sanitizeDecimal(e.target.value))}
            placeholder="0.0"
            inputMode="decimal"
            className={over0 ? 'over' : undefined}
          />
          <span className="unit">token0</span>
        </div>
      </div>

      <div className="field">
        <div className="field-top">
          <span className="field-label">Token 1</span>
          <button
            type="button"
            className="bal"
            disabled={balances?.token1 === undefined || balances.token1 === 0n}
            onClick={() => balances && onAmount1(formatAmount(balances.token1))}
          >
            Balance {fmt(balances?.token1)} · Max
          </button>
        </div>
        <div className="input-wrap">
          <input
            value={amount1}
            onChange={(e) => onAmount1(sanitizeDecimal(e.target.value))}
            placeholder="0.0"
            inputMode="decimal"
            className={over1 ? 'over' : undefined}
          />
          <span className="unit">token1</span>
        </div>
      </div>

      {estShares !== undefined && (
        <p className="hint">
          You'll receive ≈ <b>{fmt(estShares)}</b> LP
        </p>
      )}

      <button type="submit" disabled={pending || !amount0 || !amount1 || insufficient}>
        {insufficient ? 'Insufficient balance' : pending ? 'Adding…' : 'Add liquidity'}
      </button>

      {error && <p className="error">Error: {error}</p>}
    </form>
  )
}
