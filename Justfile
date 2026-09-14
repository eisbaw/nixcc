# Default: list recipes
default:
    @just --list

# Build the lcc reference frontend used as our IR oracle
oracle:
    nix build .#rcc

# Dump lcc's reference IR for a C file (the oracle we diff our frontend against)
ir FILE:
    nix run .#rcc -- -target=symbolic < {{FILE}}

# Run every proof-of-concept
poc:
    #!/usr/bin/env bash
    set -euo pipefail
    for d in poc/*/; do
      [ -x "$d/run.sh" ] || continue
      echo "== $d"
      nix develop --command bash "$d/run.sh"
    done

# Differential-test the RV32I encoder against GNU as
poc-encoder:
    nix develop --command bash poc/01-encoder/run.sh

# Enter the dev shell
shell:
    nix develop
