# wallet defaults to host.docker.internal:8080 (Docker-only hostname);
# everything here runs natively, so point it at localhost.
export AZTEC_NODE_URL := http://localhost:8080

# runnable from root, contracts/, or frontend/ — the root and frontend Makefiles
# forward every target here via `$(MAKE) -C contracts`.
.DEFAULT_GOAL := help
.PHONY: help
help:
	@echo "Private DEX — runnable from root, contracts/, or frontend/:"
	@echo "  make sandbox    start local network (term 1, long-running)"
	@echo "  make deploy     import accounts + deploy all contracts + shield into test0"
	@echo "  make dev        run the frontend (yarn dev)"
	@echo ""
	@echo "  make get-balances-private / get-balances-public / get-reserves"
	@echo "  make add-liquidity / swap / remove-liquidity"
	@echo ""
	@echo "Fresh sandbox restart? -> rm -rf ~/.aztec/wallet && make deploy"

# initial token supply minted to test0 at deploy (1000e18)
SUPPLY ?= 1000000000000000000000

# deployed contract addresses — upserted by each deploy-* target (jq required)
ADDRESSES_JSON := addresses.json

# 1st start local network:
# long-running; leave it open in its own terminal
sandbox:
	aztec start --local-network


# 2nd deployment:
# register the sandbox's prefunded test accounts (test0, test1, …) — run once
accounts:
	aztec-wallet import-test-accounts

# 1. token0 — mints SUPPLY to test0's PUBLIC balance at deploy (no minter role)
deploy-token0:
	@set -e; \
	out=$$(aztec-wallet deploy artifacts/token_contract-Token.json \
		--from accounts:test0 \
		--init constructor_with_initial_supply \
		--args Token0 TK0 18 $(SUPPLY) accounts:test0 \
		--alias token0 --salt 0x1 2>&1); \
	printf '%s\n' "$$out"; \
	addr=$$(printf '%s\n' "$$out" | grep -oE '0x[0-9a-fA-F]{60,}' | tail -1 || true); \
	[ -n "$$addr" ] || { echo "ERROR: token0 address not found in deploy output"; exit 1; }; \
	if [ -f $(ADDRESSES_JSON) ]; then \
		tmp=$$(mktemp); \
		jq --arg v "$$addr" '.token0=$$v' $(ADDRESSES_JSON) > "$$tmp" && mv "$$tmp" $(ADDRESSES_JSON); \
	else \
		jq -n --arg v "$$addr" '{token0:$$v}' > $(ADDRESSES_JSON); \
	fi; \
	echo "token0 → $$addr"

# 2. token1 — same, also to test0 so one account holds both for testing
deploy-token1:
	@set -e; \
	out=$$(aztec-wallet deploy artifacts/token_contract-Token.json \
		--from accounts:test0 \
		--init constructor_with_initial_supply \
		--args Token1 TK1 18 $(SUPPLY) accounts:test0 \
		--alias token1 --salt 0x2 2>&1); \
	printf '%s\n' "$$out"; \
	addr=$$(printf '%s\n' "$$out" | grep -oE '0x[0-9a-fA-F]{60,}' | tail -1 || true); \
	[ -n "$$addr" ] || { echo "ERROR: token1 address not found in deploy output"; exit 1; }; \
	if [ -f $(ADDRESSES_JSON) ]; then \
		tmp=$$(mktemp); \
		jq --arg v "$$addr" '.token1=$$v' $(ADDRESSES_JSON) > "$$tmp" && mv "$$tmp" $(ADDRESSES_JSON); \
	else \
		jq -n --arg v "$$addr" '{token1:$$v}' > $(ADDRESSES_JSON); \
	fi; \
	echo "token1 → $$addr"

# 3. amm
deploy-amm:
	@set -e; \
	out=$$(aztec-wallet deploy target/amm-AMM.json \
		--from accounts:test0 \
		--init constructor \
		--args contracts:token0 contracts:token1 3000 \
		--alias amm --salt 0x3 2>&1); \
	printf '%s\n' "$$out"; \
	addr=$$(printf '%s\n' "$$out" | grep -oE '0x[0-9a-fA-F]{60,}' | tail -1 || true); \
	[ -n "$$addr" ] || { echo "ERROR: amm address not found in deploy output"; exit 1; }; \
	if [ -f $(ADDRESSES_JSON) ]; then \
		tmp=$$(mktemp); \
		jq --arg v "$$addr" '.amm=$$v' $(ADDRESSES_JSON) > "$$tmp" && mv "$$tmp" $(ADDRESSES_JSON); \
	else \
		jq -n --arg v "$$addr" '{amm:$$v}' > $(ADDRESSES_JSON); \
	fi; \
	echo "amm → $$addr"

# 4. lp token
deploy-lptoken:
	@set -e; \
	out=$$(aztec-wallet deploy target/lp_token-LiquidityToken.json \
		--from accounts:test0 \
		--init constructor \
		--args LPToken LPT 18 contracts:amm \
		--alias lp_token --salt 0x4 2>&1); \
	printf '%s\n' "$$out"; \
	addr=$$(printf '%s\n' "$$out" | grep -oE '0x[0-9a-fA-F]{60,}' | tail -1 || true); \
	[ -n "$$addr" ] || { echo "ERROR: lp_token address not found in deploy output"; exit 1; }; \
	if [ -f $(ADDRESSES_JSON) ]; then \
		tmp=$$(mktemp); \
		jq --arg v "$$addr" '.lp_token=$$v' $(ADDRESSES_JSON) > "$$tmp" && mv "$$tmp" $(ADDRESSES_JSON); \
	else \
		jq -n --arg v "$$addr" '{lp_token:$$v}' > $(ADDRESSES_JSON); \
	fi; \
	echo "lp_token → $$addr"

# 5. set lp token in amm
set-lptoken:
	aztec-wallet send set_lp_token \
        --contract-address contracts:amm \
        --from accounts:test0 \
        --args contracts:lp_token


# 6. shield: move ACCOUNT's PUBLIC balance (minted at deploy) into its PRIVATE balance.
# self-transfer (from == msg_sender), so _nonce = 0 (no authwit needed).
# usage:  make to-private TOKEN=token1 AMOUNT=500000000000000000000
TOKEN  ?= token0
AMOUNT ?= 1000000000000000000000   # 1000e18

to-private:
	aztec-wallet send transfer_public_to_private \
		--contract-address contracts:$(TOKEN) \
		--from $(ACCOUNT) \
		--args $(ACCOUNT) $(ACCOUNT) $(AMOUNT) 0


# 3rd interactions

# silence the aztec logger so only our own output shows
export LOG_LEVEL := silent

# check balances (private notes) for ACCOUNT — defaults to test0
# override:  make get-balances ACCOUNT=accounts:test1
ACCOUNT ?= accounts:test0

# $(call sim,<fn>,<contract-alias>,<from>,<args...>) -> prints just the result value
sim = aztec-wallet simulate $(1) --contract-address contracts:$(2) --from $(3) $(if $(4),--args $(4)) 2>/dev/null | sed -n 's/.*Simulation result: *\(.*[^ ]\) *$$/\1/p'

get-balances-private:
	@printf "token0 private balance:   %s\n" "$$($(call sim,balance_of_private,token0,$(ACCOUNT),$(ACCOUNT)))"
	@printf "token1 private balance:   %s\n" "$$($(call sim,balance_of_private,token1,$(ACCOUNT),$(ACCOUNT)))"
	@printf "lp_token private balance: %s\n" "$$($(call sim,balance_of_private,lp_token,$(ACCOUNT),$(ACCOUNT)))"

# public balances — where freshly-minted (mint_to_public) tokens land before shielding
get-balances-public:
	@printf "token0 public balance:   %s\n" "$$($(call sim,balance_of_public,token0,$(ACCOUNT),$(ACCOUNT)))"
	@printf "token1 public balance:   %s\n" "$$($(call sim,balance_of_public,token1,$(ACCOUNT),$(ACCOUNT)))"

# public reserves held by the AMM
get-reserves:
	@printf "reserve0: %s\n" "$$($(call sim,reserve0,amm,accounts:test0))"
	@printf "reserve1: %s\n" "$$($(call sim,reserve1,amm,accounts:test0))"

# liquidity amounts / slippage / authwit nonce — override on the command line as needed
TO    ?= accounts:test0
AMT0  ?= 100000000000000000000   # 100e18
AMT1  ?= 100000000000000000000   # 100e18
MIN0  ?= 1                       # must be > 0
MIN1  ?= 1
SHARES ?= 1000000000000000000    # 1e18 LP shares to burn on remove
NONCE ?= 1                       # links the authwits to the call (any value, must match)

# swap (exact input): spend AMT_IN of TOKEN_IN, receive the other token
TOKEN_IN ?= token0               # which token you put IN (token0 or token1)
AMT_IN   ?= 10000000000000000000 # 10e18
OUT_MIN  ?= 1                    # min output (slippage floor); must be > 0

# add liquidity: AMM pulls AMT0 of token0 AND AMT1 of token1 from ACCOUNT's private balance,
# so ACCOUNT must authorize the AMM to make BOTH transfer_private_to_public calls.
add-liquidity:
	aztec-wallet create-authwit transfer_private_to_public contracts:amm \
		--contract-address contracts:token0 --from $(ACCOUNT) \
		--args $(ACCOUNT) contracts:amm $(AMT0) $(NONCE) --alias lp_aw0
	aztec-wallet create-authwit transfer_private_to_public contracts:amm \
		--contract-address contracts:token1 --from $(ACCOUNT) \
		--args $(ACCOUNT) contracts:amm $(AMT1) $(NONCE) --alias lp_aw1
	aztec-wallet send add_liquidity \
		--contract-address contracts:amm --from $(ACCOUNT) \
		--args $(TO) $(AMT0) $(AMT1) $(MIN0) $(MIN1) $(NONCE) \
		--auth-witness lp_aw0,lp_aw1

# remove liquidity: AMM pulls SHARES of the LP token from ACCOUNT, so authorize that ONE call.
remove-liquidity:
	aztec-wallet create-authwit transfer_private_to_public contracts:amm \
		--contract-address contracts:lp_token --from $(ACCOUNT) \
		--args $(ACCOUNT) contracts:amm $(SHARES) $(NONCE) --alias rm_aw
	aztec-wallet send remove_liquidity \
		--contract-address contracts:amm --from $(ACCOUNT) \
		--args $(TO) $(SHARES) $(MIN0) $(MIN1) $(NONCE) \
		--auth-witness rm_aw

# swap: AMM pulls AMT_IN of TOKEN_IN from ACCOUNT, prices it against the reserves,
# and pays the other token to TO. One authwit (on TOKEN_IN), like remove-liquidity.
swap:
	aztec-wallet create-authwit transfer_private_to_public contracts:amm \
		--contract-address contracts:$(TOKEN_IN) --from $(ACCOUNT) \
		--args $(ACCOUNT) contracts:amm $(AMT_IN) $(NONCE) --alias sw_aw
	aztec-wallet send swap \
		--contract-address contracts:amm --from $(ACCOUNT) \
		--args $(TO) contracts:$(TOKEN_IN) $(AMT_IN) $(OUT_MIN) $(NONCE) \
		--auth-witness sw_aw


# one-shot: register test accounts, deploy all contracts (fixed salts → stable
# addresses across sandbox restarts), wire the LP token, and shield both tokens
# into test0's private balance. PREREQ: `make sandbox` running in another terminal.
deploy:
	$(MAKE) accounts
	$(MAKE) deploy-token0
	$(MAKE) deploy-token1
	$(MAKE) deploy-amm
	$(MAKE) deploy-lptoken
	$(MAKE) set-lptoken
	$(MAKE) to-private TOKEN=token0
	$(MAKE) to-private TOKEN=token1


# frontend targets (dev, build, …) live in ../frontend/Makefile. Forward any
# target we don't own there — unless _FWD=1, meaning the request already came
# FROM frontend, so we don't bounce it back (loop guard).
ifndef _FWD
%:
	@$(MAKE) -C ../frontend _FWD=1 $@
endif