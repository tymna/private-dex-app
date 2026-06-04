import { useSwap } from '../hooks/useSwap'
import { useSwapForm } from '../hooks/useSwapForm'
import { formatAmount, formatDisplay as fmt, sanitizeDecimal, tryParseAmount } from '../lib/amounts'
import type { Balances, Reserves } from '../types'

type Props = {
  reserves?: Reserves
  /** Pool swap fee in parts-per-10000 — drives the output estimate. */
  feeRate?: bigint
  /** Private balances — the input-side balance bounds the amount + powers Max. */
  balances?: Balances
  /** Re-read balances + reserves after a successful swap. */
  refresh: () => Promise<void> | void
}

/**
 * The swap form body (exact input) — rendered inside the action card, so no
 * outer chrome of its own. Amount + direction + estimate live in useSwapForm;
 * the tx + authwit live in useSwap. The ⇄ button flips direction; we block
 * submitting more than the input-side balance.
 */
export function SwapForm({ reserves, feeRate, balances, refresh }: Props) {
  const { amountIn, onAmountIn, zeroForOne, flip, estOut, reset } = useSwapForm(reserves, feeRate)
  const { submit, pending, error } = useSwap(refresh)

  const tokenIn = zeroForOne ? 'token0' : 'token1'
  const tokenOut = zeroForOne ? 'token1' : 'token0'
  const balIn = zeroForOne ? balances?.token0 : balances?.token1

  const parsed = tryParseAmount(amountIn)
  const insufficient = parsed !== undefined && balIn !== undefined && parsed > balIn

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        void submit(zeroForOne, amountIn).then((ok) => {
          if (ok) reset()
        })
      }}
    >
      <div className="swap-direction">
        <span>
          {tokenIn} → {tokenOut}
        </span>
        <button type="button" onClick={flip} aria-label="Flip swap direction">
          ⇄
        </button>
      </div>

      <div className="field">
        <div className="field-top">
          <span className="field-label">{tokenIn} in</span>
          <button
            type="button"
            className="bal"
            disabled={balIn === undefined || balIn === 0n}
            onClick={() => balIn !== undefined && onAmountIn(formatAmount(balIn))}
          >
            Balance {fmt(balIn)} · Max
          </button>
        </div>
        <div className="input-wrap">
          <input
            value={amountIn}
            onChange={(e) => onAmountIn(sanitizeDecimal(e.target.value))}
            placeholder="0.0"
            inputMode="decimal"
            className={insufficient ? 'over' : undefined}
          />
          <span className="unit">{tokenIn}</span>
        </div>
      </div>

      {estOut !== undefined && (
        <p className="hint">
          You'll receive ≈ <b>{fmt(estOut)}</b> {tokenOut}
        </p>
      )}

      <button type="submit" disabled={pending || !amountIn || insufficient}>
        {insufficient ? 'Insufficient balance' : pending ? 'Swapping…' : 'Swap'}
      </button>

      {error && <p className="error">Error: {error}</p>}
    </form>
  )
}
