type Props = {
  address?: string
  loading: boolean
  error?: string
}

/** Top-bar pill: connection progress, the connected account, or a connect error. */
export function AccountBar({ address, loading, error }: Props) {
  if (error) {
    return (
      <div className="account is-error">
        <span className="dot" />
        Connection failed
      </div>
    )
  }

  if (loading || !address) {
    return (
      <div className="account">
        <span className="dot pulse" />
        Connecting wallet…
      </div>
    )
  }

  return (
    <div className="account">
      <span className="dot" />
      <code>
        {address.slice(0, 8)}…{address.slice(-6)}
      </code>
    </div>
  )
}
