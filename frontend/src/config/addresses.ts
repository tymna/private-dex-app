// Deployed contract addresses on the local sandbox.
//
// These are STABLE across `make sandbox` restarts because the Makefile deploys
// each contract with a fixed --salt (token0=0x1, token1=0x2, amm=0x3, lp=0x4)
// from the deterministic test0 account. So you paste them ONCE.
//
// To fill in: run `make deploy` in ../contracts and copy the four
// "<name> → 0x..." lines from the output here. Re-paste only if you change a
// contract's bytecode or constructor args (that changes its address).
export const ADDRESSES = {
  token0: '0x2f9f96304f8a0e38242b236086c6f9ca1b50008eb7bffefe74bddcd5217a999e',
  token1: '0x14ba2ca41a1b1cecd76e984585535c26d9d437cf2a065b9ede79f4ded44843e3',
  amm: '0x303413b5fdb44c50d9846ab2abe9d31a767586fb75ebe0d5b361b67d340bfae2',
  lp_token: '0x1210f39bf589e6475090db446e31b04682879d52ce78cc5da0d4ace6e88477ae',
} as const
