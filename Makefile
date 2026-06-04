# Root Makefile — run everything from the repo root instead of cd-ing into contracts/.
# Each target just forwards to contracts/Makefile (command-line vars like TOKEN=token1
# propagate to the sub-make automatically).
#
#   make sandbox     # term 1: start local network (long-running)
#   make deploy      # term 2: import accounts + deploy + shield
#   make dev         # term 2/3: run the frontend
#
# See `make help` for the full list.

CONTRACTS := contracts

.DEFAULT_GOAL := help
.PHONY: help
help:
	@$(MAKE) -C $(CONTRACTS) help

# forward every other target (and command-line vars like TOKEN=token1) to contracts/
%:
	@$(MAKE) -C $(CONTRACTS) $@
