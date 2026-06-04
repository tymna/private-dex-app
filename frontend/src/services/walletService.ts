// Pure Aztec layer — ZERO React. The UI never touches a PXE call directly;
// it only ever calls the exported functions below.
//
// Model (see notes): embedded wallet = the PXE runs in THIS browser tab. We use
// the sandbox's deterministic prefunded `test0` account (re-derived here via
// registerInitialLocalNetworkAccountsInWallet — same account the Makefile funds),
// and attach to the contracts at their fixed-salt addresses from addresses.ts.
// Neither @aztec/aztec.js nor @aztec/wallets has a root export — only subpaths.
// `EmbeddedWallet` from /embedded resolves to the node build under TS's bundler
// resolution but to the BROWSER build at runtime via Vite (the package's
// `browser` export condition), which is what we want in the tab.
//
// Write calls (addLiquidity/removeLiquidity/swap) share one authwit story: the
// AMM pulls tokens out of our private balance via `transfer_private_to_public`
// ON OUR BEHALF, so each pull needs an authwit. We never build those by hand —
// `.send()` pre-simulates the call, sees the authorization requests the tokens
// emit, and the in-tab PXE auto-signs them (no external prompt). `.send()` also
// waits for the tx to mine, resolving to { receipt }, so there's no separate
// `.wait()`. All we do is pass a fresh per-call `Fr.random()` nonce, which the
// AMM forwards into the same transfer_private_to_public calls the authwits bind to.
import { AztecAddress } from '@aztec/aztec.js/addresses'
import { Fr } from '@aztec/aztec.js/fields'
import { createAztecNodeClient } from '@aztec/aztec.js/node'
import { EmbeddedWallet } from '@aztec/wallets/embedded'
import { registerInitialLocalNetworkAccountsInWallet } from '@aztec/wallets/testing'

import { AMMContract, AMMContractArtifact } from '../contracts/AMM'
import { TokenContract, TokenContractArtifact } from '../contracts/Token'
import { LiquidityTokenContract, LiquidityTokenContractArtifact } from '../contracts/LiquidityToken'
import { ADDRESSES } from '../config/addresses'

const NODE_URL = 'http://localhost:8080'

// Module-level state: set once by init(), reused by every read/write below.
let wallet: EmbeddedWallet | undefined
let account: AztecAddress | undefined
let token0: TokenContract
let token1: TokenContract
let amm: AMMContract
let lpToken: LiquidityTokenContract

function ensureReady() {
  if (!wallet || !account) {
    throw new Error('Wallet not initialized — call initWallet() first.')
  }
}

/**
 * Boots the embedded wallet: starts the in-browser PXE, registers test0, and
 * attaches to the four deployed contracts. Idempotent — safe to call repeatedly.
 * Returns the connected account address (for display).
 */
export async function initWallet(): Promise<{ address: string }> {
  if (wallet && account) {
    return { address: account.toString() }
  }

  const node = createAztecNodeClient(NODE_URL)
  // proverEnabled: false → no real proofs on the sandbox (much faster). The
  // Makefile deploys with PROVER_ENABLED=false too, so this matches.
  wallet = await EmbeddedWallet.create(node, { pxe: { proverEnabled: false } })

  // Re-derive the sandbox test accounts in this PXE. The first one is the
  // funded `test0` the Makefile shielded tokens into — DO NOT create a fresh
  // account, or balances read zero.
  const [test0] = await registerInitialLocalNetworkAccountsInWallet(wallet)
  if (!test0) {
    throw new Error('No local-network test accounts found. Is `aztec start --local-network` running?')
  }
  account = test0

  // Register each deployed contract in the PXE so it can simulate their
  // functions, then attach a typed handle. The instances are fetched from the
  // node (the contracts were publicly deployed by `make deploy`).
  await registerDeployed(node, ADDRESSES.token0, TokenContractArtifact)
  await registerDeployed(node, ADDRESSES.token1, TokenContractArtifact)
  await registerDeployed(node, ADDRESSES.amm, AMMContractArtifact)
  await registerDeployed(node, ADDRESSES.lp_token, LiquidityTokenContractArtifact)

  token0 = TokenContract.at(toAddress(ADDRESSES.token0), wallet)
  token1 = TokenContract.at(toAddress(ADDRESSES.token1), wallet)
  amm = AMMContract.at(toAddress(ADDRESSES.amm), wallet)
  lpToken = LiquidityTokenContract.at(toAddress(ADDRESSES.lp_token), wallet)

  return { address: account.toString() }
}

/** Private (shielded) balances of test0 — what the swap UI cares about. */
export async function getBalances(): Promise<{ token0: bigint; token1: bigint; lp: bigint }> {
  ensureReady()
  const owner = account!
  const [t0, t1, lp] = await Promise.all([
    token0.methods.balance_of_private(owner).simulate({ from: owner }),
    token1.methods.balance_of_private(owner).simulate({ from: owner }),
    lpToken.methods.balance_of_private(owner).simulate({ from: owner }),
  ])
  return {
    token0: t0.result as bigint,
    token1: t1.result as bigint,
    lp: lp.result as bigint,
  }
}

/** The AMM's public reserves (the pool's pricing state). */
export async function getReserves(): Promise<{ reserve0: bigint; reserve1: bigint }> {
  ensureReady()
  const owner = account!
  const [r0, r1] = await Promise.all([
    amm.methods.reserve0().simulate({ from: owner }),
    amm.methods.reserve1().simulate({ from: owner }),
  ])
  return {
    reserve0: r0.result as bigint,
    reserve1: r1.result as bigint,
  }
}

/**
 * Adds liquidity to the pool from test0's PRIVATE balances (two pulls, one per
 * token — see the module header for the shared authwit/nonce/`.send()` story).
 *
 * `to` is the caller itself (test0): shares + any refund of the unused side
 * come back to us. `amount{0,1}Min` are the slippage floors — the tx reverts if
 * the pool's ratio means less than this much of either token gets used. Both
 * must be > 0 (the contract asserts it).
 *
 * @returns the mined tx hash (for display / explorer linking).
 */
export async function addLiquidity(params: {
  amount0Max: bigint
  amount1Max: bigint
  amount0Min?: bigint
  amount1Min?: bigint
}): Promise<{ txHash: string }> {
  ensureReady()
  const to = account!

  const nonce = Fr.random()

  const { receipt } = await amm.methods
    .add_liquidity(
      to,
      params.amount0Max,
      params.amount1Max,
      params.amount0Min ?? 1n,
      params.amount1Min ?? 1n,
      nonce,
    )
    .send({ from: to })

  return { txHash: receipt.txHash.toString() }
}

/**
 * Removes liquidity, burning `shares` of test0's PRIVATE LP balance and paying
 * both underlying tokens back to us as private notes. ONE pull (the LP-share
 * transfer) — see the module header for the shared authwit/nonce/`.send()` story.
 * The public `_remove_liquidity` reads reserves, prices the proportional payout,
 * completes both token commitments, and burns the shares.
 *
 * `to` is the caller itself (test0): both token payouts come back to us as
 * private notes. `amount{0,1}Min` are the slippage floors — the tx reverts if the
 * pool would return less than this much of either side. Both must be > 0 (the
 * contract asserts it).
 *
 * @returns the mined tx hash (for display / explorer linking).
 */
export async function removeLiquidity(params: {
  shares: bigint
  amount0Min?: bigint
  amount1Min?: bigint
}): Promise<{ txHash: string }> {
  ensureReady()
  const to = account!

  const nonce = Fr.random()

  const { receipt } = await amm.methods
    .remove_liquidity(to, params.shares, params.amount0Min ?? 1n, params.amount1Min ?? 1n, nonce)
    .send({ from: to })

  return { txHash: receipt.txHash.toString() }
}

/**
 * Swaps `amountIn` of one token for the other from test0's PRIVATE balance
 * (exact input). `zeroForOne` picks the direction: true = token0 in → token1
 * out, false = the reverse. ONE pull (the input token) — see the module header
 * for the shared authwit/nonce/`.send()` story. The public `_swap` reads
 * reserves, prices the output via get_amount_out (CPMM net of fee_rate), and
 * completes the single output commitment.
 *
 * `to` is the caller itself (test0): the output comes back to us as a private
 * note. `amountOutMin` is the slippage floor — the tx reverts if the pool would
 * return less. It must be > 0 (the contract asserts it). Exact-input means the
 * whole input is consumed, so there is no input refund.
 *
 * @returns the mined tx hash (for display / explorer linking).
 */
export async function swap(params: {
  zeroForOne: boolean
  amountIn: bigint
  amountOutMin?: bigint
}): Promise<{ txHash: string }> {
  ensureReady()
  const to = account!

  const tokenIn = params.zeroForOne ? toAddress(ADDRESSES.token0) : toAddress(ADDRESSES.token1)

  const nonce = Fr.random()

  const { receipt } = await amm.methods
    .swap(to, tokenIn, params.amountIn, params.amountOutMin ?? 1n, nonce)
    .send({ from: to })

  return { txHash: receipt.txHash.toString() }
}

/** The pool's swap fee, in parts-per-10000 (public state). Needed to price swaps. */
export async function getFeeRate(): Promise<bigint> {
  ensureReady()
  const r = await amm.methods.fee_rate().simulate({ from: account! })
  return BigInt(r.result as bigint | number)
}

/**
 * Total LP shares in circulation (public state on the LiquidityToken). Needed to
 * estimate how many shares an add-liquidity deposit would mint — the contract
 * prices shares against this supply (see estimateLpShares).
 */
export async function getLpTotalSupply(): Promise<bigint> {
  ensureReady()
  const r = await lpToken.methods.total_supply().simulate({ from: account! })
  return r.result as bigint
}

// --- internals -------------------------------------------------------------

function toAddress(s: string): AztecAddress {
  if (s.startsWith('0xREPLACE_ME')) {
    throw new Error(`addresses.ts still has a placeholder (${s}). Run \`make deploy\` and paste the real addresses.`)
  }
  return AztecAddress.fromString(s)
}

async function registerDeployed(
  node: ReturnType<typeof createAztecNodeClient>,
  address: string,
  artifact: Parameters<EmbeddedWallet['registerContract']>[1],
): Promise<void> {
  const addr = toAddress(address)
  const instance = await node.getContract(addr)
  if (!instance) {
    throw new Error(
      `No contract deployed at ${address} on ${NODE_URL}. Run \`make deploy\` and update addresses.ts.`,
    )
  }
  await wallet!.registerContract(instance, artifact)
}
