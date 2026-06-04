import { useState } from 'react'

import type { Balances, Reserves } from '../types'
import { AddLiquidityForm } from './AddLiquidityForm'
import { RemoveLiquidityForm } from './RemoveLiquidityForm'

type Props = {
  reserves?: Reserves
  lpSupply?: bigint
  balances?: Balances
  refresh: () => Promise<void> | void
}

/**
 * The "Provide liquidity" section body: a small Add / Remove toggle over the
 * active form. Kept separate from Swap (its own editorial section in App), so
 * the two flows read as distinct rather than tabs of one card.
 */
export function LiquiditySection({ reserves, lpSupply, balances, refresh }: Props) {
  const [mode, setMode] = useState<'add' | 'remove'>('add')

  return (
    <>
      <div className="subtabs">
        <button
          type="button"
          className={mode === 'add' ? 'subtab active' : 'subtab'}
          onClick={() => setMode('add')}
        >
          Add
        </button>
        <button
          type="button"
          className={mode === 'remove' ? 'subtab active' : 'subtab'}
          onClick={() => setMode('remove')}
        >
          Remove
        </button>
      </div>

      {mode === 'add' ? (
        <AddLiquidityForm
          reserves={reserves}
          lpSupply={lpSupply}
          balances={balances}
          refresh={refresh}
        />
      ) : (
        <RemoveLiquidityForm
          reserves={reserves}
          lpSupply={lpSupply}
          lpBalance={balances?.lp}
          refresh={refresh}
        />
      )}
    </>
  )
}
