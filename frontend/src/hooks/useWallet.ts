import { useCallback, useEffect, useState } from 'react'

import {
  getBalances,
  getFeeRate,
  getLpTotalSupply,
  getReserves,
  initWallet,
} from '../services/walletService'
import type { Balances, Reserves } from '../types'

/**
 * Connects the embedded wallet on mount (no button — embedded-only app) and
 * exposes the connected address plus a refreshable balances/reserves snapshot.
 * The UI only ever touches this hook, never walletService directly.
 */
export function useWallet() {
  const [address, setAddress] = useState<string>()
  const [balances, setBalances] = useState<Balances>()
  const [reserves, setReserves] = useState<Reserves>()
  const [lpSupply, setLpSupply] = useState<bigint>()
  const [feeRate, setFeeRate] = useState<bigint>()
  const [error, setError] = useState<string>()
  const [loading, setLoading] = useState(true)

  const refresh = useCallback(async () => {
    const [b, r, s, f] = await Promise.all([
      getBalances(),
      getReserves(),
      getLpTotalSupply(),
      getFeeRate(),
    ])
    setBalances(b)
    setReserves(r)
    setLpSupply(s)
    setFeeRate(f)
  }, [])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const { address } = await initWallet()
        if (cancelled) return
        setAddress(address)
        await refresh()
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e))
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [refresh])

  return { address, balances, reserves, lpSupply, feeRate, error, loading, refresh }
}
