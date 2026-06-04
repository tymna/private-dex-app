# Private DEX — frontend

React + Vite, embedded wallet against the local Aztec sandbox (node on `:8080`).

## Run it (3 terminals)

### 1. Local env — start the sandbox
```sh
cd contracts
make sandbox          # long-running; leave it open in its own terminal
```
Wait until it finishes booting (it prints the test accounts + admin API key, then goes quiet).

### 2. Setup accounts + deploy
```sh
cd contracts
make deploy           # imports test accounts, then deploys token0/token1/AMM/lp_token + shields into test0
```
One run per **fresh** sandbox. Salts are fixed, so the four addresses are always the same — they're already hardcoded in `src/config/addresses.ts`, no copy-paste needed.

### 3. Run the frontend
```sh
cd contracts
make dev              # == yarn --cwd ../frontend dev
```
Open the printed URL. It should connect the embedded wallet and show test0's balances.

## Gotchas

- **Restarted the sandbox?** If a later command dies with `Block hash … not found … possibly a reorg`, the wallet has stale state from the old chain. Clear it and redeploy:
  ```sh
  rm -rf ~/.aztec/wallet && make deploy
  ```
- **Sandbox not up** → deploys fail with `ECONNREFUSED` on `:8080`. Start `make sandbox` first.
- **`yarn build`** runs `tsc -b` then `vite build`. `tsconfig.app.json` leaves `noUnusedLocals`/`noUnusedParameters` to ESLint (which exempts the generated `src/contracts/` files via their `/* eslint-disable */` header), so the build is clean. The only output is a harmless "chunk > 500 kB" warning — that's the Aztec wasm bundle.
- **Re-verify addresses** after a deploy:
  ```sh
  cd contracts && aztec-wallet get-alias | grep contracts:
  ```

## First-time setup

Already wired in `package.json` / `vite.config.ts` — listed here for reference. The Aztec
PXE needs WASM support, so the build uses `vite-plugin-wasm` with `build.target: 'esnext'`
(esnext handles top-level await natively, so no separate TLA plugin is needed):
```sh
yarn add -D vite-plugin-wasm@^3.5.0
```
