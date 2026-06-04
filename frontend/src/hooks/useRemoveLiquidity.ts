import { useCallback, useState } from 'react'

import { parseAmount } from '../lib/amounts'
import { removeLiquidity } from '../services/walletService'

/**
 * Wraps walletService.removeLiquidity for the UI: parses the LP-shares amount,
 * tracks pending/error, and runs `onDone` (the wallet refresh) after a
 * successful removal so balances + reserves re-read. The form never sees a PXE
 * call or an authwit — the embedded wallet auto-signs the LP-share pull inside
 * `removeLiquidity`.
 *
 * `submit` resolves to `true` on success and `false` on failure, so the caller
 * can clear its input only when the removal actually went through.
 */
export function useRemoveLiquidity(onDone: () => Promise<void> | void) {
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string>()

  const submit = useCallback(
    async (shares: string): Promise<boolean> => {
      setPending(true)
      setError(undefined)
      try {
        await removeLiquidity({ shares: parseAmount(shares) })
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
