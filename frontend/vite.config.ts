import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import wasm from 'vite-plugin-wasm'

const ttyShim = fileURLToPath(new URL('./src/shims/tty.ts', import.meta.url))
const detectNodeShim = fileURLToPath(new URL('./src/shims/detect-node.ts', import.meta.url))

// Aztec dApp Vite config (mirrors AztecProtocol/gregoswap).
//
// The crucial rule: exclude ONLY the WASM-bearing packages from dep pre-bundling
// (bb.js + the noir acvm/noirc packages) — the optimizer corrupts their `import "x.wasm"`.
// Everything else (@aztec/aztec.js, /wallets, /accounts) MUST be pre-bundled, because that
// is what runs the CJS→ESM interop for their transitive deps (pino, detect-node, etc.).
// Excluding those packages is what caused the "does not provide an export named …" blank page.
//
// - define process.env: Aztec's pino logger reads it, but in the browser it's undefined.
// - COOP/COEP headers: SharedArrayBuffer, which bb.js needs for threaded proving.
// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), wasm()],
  resolve: {
    alias: [
      // detect-node's CJS `module.exports = false` interops inconsistently → intermittent
      // "does not provide an export named 'default'" from pino. Force a stable ESM default.
      { find: /^detect-node$/, replacement: detectNodeShim },
      // bb.js imports Node builtins Vite externalizes to empty stubs in the browser.
      // `util` → real polyfill (provides inspect.custom, which grumpkin reads); `tty` → stub.
      { find: /^(node:)?util$/, replacement: 'util/util.js' },
      { find: /^(node:)?assert$/, replacement: 'assert/build/assert.js' },
      { find: /^(node:)?tty$/, replacement: ttyShim },
    ],
  },
  define: {
    // bb.js / foundation reference Node globals that don't exist in the browser.
    global: 'globalThis',
    'process.env': JSON.stringify({ LOG_LEVEL: 'silent' }),
  },
  optimizeDeps: {
    // CJS deps that get served RAW and break on named imports ("does not provide an export named
    // X" → blank page). Root cause: the EXCLUDED packages below (protocol-contracts, bb.js, noir)
    // are served raw, and they import @aztec/foundation + @aztec/stdlib — also raw — whose CJS leaf
    // deps then load raw too. Vite's dep *scanner* only crawls bare imports in src/, so these
    // node_modules-internal leaves are never discovered → esbuild leaves them external → CJS named
    // imports fail in the browser. Force-including them puts them in the optimize set, where esbuild
    // applies CJS→ESM interop and synthesizes the named exports.
    //
    // This is the browser-safe CJS leaf set of the raw subtree (foundation/stdlib/constants),
    // across ALL import forms (named, default, namespace) — `import chunk from 'lodash.chunk'`
    // breaks the same way as named imports.
    // NOT included on purpose — node-only leaves; our code never evaluates their paths and force-
    // bundling them can break the optimizer: koa/@koa/cors/koa-*, undici, @aws-sdk/client-s3,
    // pino-pretty (pino's browser build never loads it).
    // Already handled by resolve.alias above: assert, buffer, util, detect-node.
    // Not needed: @noble/* — no top-level "type" field but their exports map ships ESM, so Vite
    // serves them as ESM and they work raw.
    include: [
      'pino', 'sha3', 'hash.js', 'pako', '@scure/bip39',
      'lodash.chunk', 'lodash.isequal', 'lodash.times', 'json-stringify-deterministic',
    ],
    // Exclude ONLY the wasm packages. The aztec.js/wallets/accounts packages are left in
    // (not excluded) so Vite auto-discovers the subpath imports we actually use and pre-bundles
    // them with CJS→ESM interop. Don't `include` the bare packages — they have no root (".")
    // export, only subpaths, so a bare include throws `"." is not exported`.
    exclude: [
      '@aztec/noir-acvm_js',
      '@aztec/noir-noirc_abi',
      '@aztec/bb.js',
      // protocol-contracts lazy-loads its artifact JSONs via runtime `import('../../artifacts/*.json')`.
      // If it's optimized, Vite discovers those mid-session and re-optimizes → the
      // "504 (Outdated Optimize Dep)" reload loop. Served raw, the JSON URLs are stable.
      '@aztec/protocol-contracts',
    ],
  },
  worker: {
    format: 'es',
    plugins: () => [wasm()],
  },
  build: { target: 'esnext' },
  server: {
    headers: {
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Opener-Policy': 'same-origin',
    },
  },
})
