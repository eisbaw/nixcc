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
    ran=0
    for d in poc/*/; do
      [ -e "$d/run.sh" ] || { echo "no run.sh in $d" >&2; exit 1; }
      echo "== $d"
      nix develop --command bash "$d/run.sh"
      ran=$((ran + 1))
    done
    [ "$ran" -gt 0 ] || { echo "no PoCs ran -- a green suite that tested nothing" >&2; exit 1; }
    echo "$ran PoC(s) passed"

# Differential-test the RV32I encoder against GNU as
poc-encoder:
    nix develop --command bash poc/01-encoder/run.sh

# End-to-end: build the oracles, then run every proof-of-concept
e2e:
    #!/usr/bin/env bash
    set -euo pipefail
    # rcc's own checkPhase runs lcc's corpus, so building it IS the oracle test
    nix build .#rcc --no-link
    nix flake check
    just lint
    just poc

# Lint the Nix and shell sources
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    nix develop --command statix check .
    nix develop --command deadnix --fail .
    nix develop --command shellcheck poc/*/run.sh
    echo "lint clean"

# Print the pinned reference sources (lcc, tinycc, nix-riscv)
sources:
    @nix develop --command sh -c 'echo "lcc:       $LCC_SRC"; echo "tinycc:    $TINYCC_SRC"; echo "nix-riscv: $NIX_RISCV"'

# Enter the dev shell
shell:
    nix develop
