import './App.css'

import { AccountBar } from './components/AccountBar'
import { LiquiditySection } from './components/LiquiditySection'
import { SwapForm } from './components/SwapForm'
import { useWallet } from './hooks/useWallet'
import { formatDisplay as fmt } from './lib/amounts'

function App() {
  const { address, balances, reserves, lpSupply, feeRate, error, loading, refresh } = useWallet()
  const ready = address && !error
  const feePct = feeRate !== undefined ? (Number(feeRate) / 100).toFixed(2) : undefined

  return (
    <div className="page">
      <div className="glow" aria-hidden />
      <div className="grain" aria-hidden />

      <header className="topbar">
        <div className="brand">
          <span className="mark">◈</span>Private<em>DEX</em>
        </div>
        <AccountBar address={address} loading={loading} error={error} />
      </header>

      <main className="content">
        <section className="hero">
          <h1>
            Private <em>swaps</em>,<br />
            <span className="h1-sub">public pool.</span>
          </h1>
          <p className="lede">
            An automated market maker on Aztec. The address behind every swap and deposit stays
            private — pool reserves and amounts are public.
          </p>
        </section>

        {loading && (
          <div className="status">
            <span className="status-dot" />
            Connecting to the sandbox…
          </div>
        )}

        {error && !loading && (
          <div className="status status-error">
            Couldn't connect to the sandbox — {error}
          </div>
        )}

        {ready && (
          <div className="sections">
            <section className="section">
              <div className="section-head">
                <h2>Swap</h2>
                <p>Trade one token for the other along the constant-product curve. The amount you send stays private.</p>
              </div>
              <div className="section-body">
                <SwapForm reserves={reserves} feeRate={feeRate} balances={balances} refresh={refresh} />
              </div>
            </section>

            <section className="section">
              <div className="section-head">
                <h2>Provide liquidity</h2>
                <p>Deposit both tokens to mint LP shares, or burn shares to withdraw your slice of the pool.</p>
              </div>
              <div className="section-body">
                <LiquiditySection
                  reserves={reserves}
                  lpSupply={lpSupply}
                  balances={balances}
                  refresh={refresh}
                />
              </div>
            </section>

            <section className="section">
              <div className="section-head">
                <h2>Pool</h2>
                <p>Live reserves and the swap fee for this pair.</p>
              </div>
              <div className="section-body">
                <div className="pool-row">
                  <div className="pool-stat">
                    <span className="label">Reserve 0</span>
                    <span className="value">{fmt(reserves?.reserve0)}</span>
                  </div>
                  <div className="pool-stat">
                    <span className="label">Reserve 1</span>
                    <span className="value">{fmt(reserves?.reserve1)}</span>
                  </div>
                  {feePct !== undefined && (
                    <div className="pool-stat">
                      <span className="label">Fee</span>
                      <span className="value">{feePct}%</span>
                    </div>
                  )}
                  <button
                    type="button"
                    className="refresh"
                    onClick={() => void refresh()}
                    aria-label="Refresh pool"
                  >
                    ↻
                  </button>
                </div>
              </div>
            </section>
          </div>
        )}
      </main>
    </div>
  )
}

export default App
