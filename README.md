# Private DEX

A constant-product AMM on **Aztec** — add/remove liquidity and swap token A for token B. Trades are private (nobody sees *who* traded), but reserves and amounts stay public, since the price math is checked on-chain. Each action splits into a private step that spends your tokens and opens an empty "IOU", and a public step that reads the reserves, does the math, and fills it in — those IOUs are **partial notes**.

**Aztec.nr** · **Noir** · **React + Vite**

## Layout

- **[`contracts/`](contracts/README.md)** — AMM, LP token, math helpers, tests, deploy.
- **[`frontend/`](frontend/README.md)** — React + Vite app with an embedded wallet.

Each folder's README has the full walkthrough — start there for details.

## Quick start

Everything runs from the repo root (the root `Makefile` forwards to `contracts/`):

```bash
make sandbox     # terminal 1: start the local network (long-running)
make deploy      # terminal 2: import accounts + deploy everything + shield into test0
make dev         # terminal 2/3: run the frontend
make help        # full list of targets
```

`make deploy` runs once per fresh sandbox (addresses are pinned, so the frontend hardcodes them). After a restart: `rm -rf ~/.aztec/wallet && make deploy`.

## Privacy model

Only the **caller's address** is private. Balances, amounts, and reserves are **public** — the price math is verified on-chain. You hide *who* traded, not *how much*.

---

*Study project for learning Aztec's private-execution model and the partial-note pattern.*
