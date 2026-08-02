# get-powerbash development tasks.
#
# CI calls these same targets, so a target that stops matching what the
# project actually does fails on the next push rather than going stale in
# prose. `make check` is the whole of CI except the macOS and live jobs.
#
# The container plumbing lives in the recipe below rather than in a script.
# tests/install-test.sh stays a file because the bash 3.2 image it runs in is
# Alpine, with no make in it -- make cannot be its entry point there.
#
# Recipes are written for GNU make 3.81, which is what macOS ships: no
# .ONESHELL, so multi-step recipes are one backslash-continued shell line.

BASH ?= bash

# index.html *is* the installer, so shellcheck has to be told the shell
# rather than guessing from the extension.
SHELLCHECK_TARGETS := index.html tests/*.sh

BASH32_IMAGE := docker.io/library/bash:3.2

.DEFAULT_GOAL := help

.PHONY: help lint test test-bash32 check version

help: ## Show this message
	@echo "get-powerbash $$(sed -n 's/^VERSION=\"\(.*\)\"$$/\1/p' index.html)"
	@echo
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'
	@echo
	@echo "  BASH=/path/to/bash    run the suite under a specific bash"

lint: ## shellcheck the installer and the tests
	shellcheck -s bash $(SHELLCHECK_TARGETS)

test: ## Run the install round trip (BASH=... picks the interpreter)
	$(BASH) tests/install-test.sh

# The container needs two things the base image lacks: curl, because busybox
# wget cannot fetch the file:// URLs the suite serves from, and a non-root
# user, because the installer refuses to run as root -- which is the point,
# so running the suite as root would make every install case "pass" by being
# refused.
test-bash32: ## Run the install round trip under bash 3.2, in a container
	@if command -v podman >/dev/null 2>&1; then \
	    engine=podman; mount="$(CURDIR):/src:ro,Z"; \
	elif command -v docker >/dev/null 2>&1; then \
	    engine=docker; mount="$(CURDIR):/src:ro"; \
	else \
	    echo "Neither podman nor docker found. Install one of them first." >&2; \
	    exit 1; \
	fi; \
	"$$engine" run --rm -v "$$mount" -w /tmp $(BASH32_IMAGE) \
	  sh -c 'apk add --no-cache curl diffutils >/dev/null && adduser -D tester && bash --version | head -1 && su tester -c "bash /src/tests/install-test.sh"'

check: lint test test-bash32 ## Everything CI runs that can run locally

version: ## Print the version the installer declares
	@sed -n 's/^VERSION="\(.*\)"$$/\1/p' index.html
