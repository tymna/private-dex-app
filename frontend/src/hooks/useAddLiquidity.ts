import { useCallback, useState } from 'react'

import { parseAmount } from '../lib/amounts'
import { addLiquidity } from '../services/walletService'

/**
 * Wraps walletService.addLiquidity for the UI: parses the two human amounts,
 * tracks pending/error, and runs `onDone` (the wallet refresh) after a
 * successful add so balances + reserves re-read. The form never sees a PXE call
 * or an authwit — the embedded wallet auto-signs those inside `addLiquidity`.
 *
 * `submit` resolves to `true` on success and `false` on failure, so the caller
 * can sweep its inputs only when the add actually went through.
 */
export function useAddLiquidity(onDone: () => Promise<void> | void) {
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string>()

  const submit = useCallback(
    async (amount0: string, amount1: string): Promise<boolean> => {
      setPending(true)
      setError(undefined)
      try {
        await addLiquidity({
          amount0Max: parseAmount(amount0),
          amount1Max: parseAmount(amount1),
        })
        await onDone()
        return true
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e))
        return false
      } finally {
        setPending(false)
      }
    },
    [onDone],
  )

  return { submit, pending, error }
}
