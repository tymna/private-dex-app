# Frontend targets. Run from frontend/, contracts/, or root — see loop guard below.
# PREREQ for dev: `make sandbox` running + `make deploy` done (both contract targets).

.DEFAULT_GOAL := help
.PHONY: help dev build preview
help:
	@$(MAKE) -C ../contracts help

dev:
	yarn dev

build:
	yarn build

preview:
	yarn preview

# contract targets live in ../contracts/Makefile. Forward any target we don't own
# there — unless _FWD=1, meaning the request already came FROM contracts, so we
# don't bounce it back (loop guard).
ifndef _FWD
%:
	@$(MAKE) -C ../contracts _FWD=1 $@
endif
