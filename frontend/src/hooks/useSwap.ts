import { useCallback, useState } from 'react'

import { parseAmount } from '../lib/amounts'
import { swap } from '../services/walletService'

/**
 * Wraps walletService.swap for the UI: parses the input amount, tracks
 * pending/error, and runs `onDone` (the wallet refresh) after a successful swap
 * so balances + reserves re-read. The form never sees a PXE call or an authwit —
 * the embedded wallet auto-signs the input pull inside `swap`.
 *
 * `submit` resolves to `true` on success and `false` on failure, so the caller
 * can clear its input only when the swap actually went through.
 */
export function useSwap(onDone: () => Promise<void> | void) {
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string>()

  const submit = useCallback(
    async (zeroForOne: boolean, amountIn: string): Promise<boolean> => {
      setPending(true)
      setError(undefined)
      try {
        await swap({ zeroForOne, amountIn: parseAmount(amountIn) })
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
