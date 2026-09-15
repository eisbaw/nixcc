# Default: list recipes
default:
    @just --list

# Build the lcc reference frontend used as our IR oracle
oracle:
    nix build .#rcc

# Dump lcc's reference IR for a C file (the oracle we diff our frontend against).
# Goes through the rcc-rv32 wrapper, never raw `rcc -target=symbolic`: the raw
# oracle declares little_endian=0 and lays out bitfields for a big-endian
# machine (decision-004). Needs the dev shell, which is where rcc-rv32 lives.
ir FILE:
    rcc-rv32 < {{FILE}}

# Run every proof-of-concept
poc:
    #!/usr/bin/env bash
    set -euo pipefail
    ran=0
    refused=0
    # Numbered directories only: poc/lib/ is what the PoCs share, not a PoC.
    # Still a hard error rather than a skip, so a real PoC cannot go missing.
    for d in poc/[0-9]*-*/; do
      [ -e "$d/run.sh" ] || { echo "no run.sh in $d" >&2; exit 1; }
      echo "== $d"
      status=0
      nix develop --command bash "$d/run.sh" || status=$?
      ran=$((ran + 1))
      # Exit 3 is a timing ladder refusing to judge a machine that was busy
      # while it measured. That is not a failure of the thing under test, so it
      # must not stop the PoCs after it from running -- and not a pass either,
      # so the suite still ends red, with a count rather than a silence.
      case "$status" in
        0) ;;
        3) refused=$((refused + 1)); echo "== $d rendered NO VERDICT; carrying on" ;;
        *) exit "$status" ;;
      esac
    done
    [ "$ran" -gt 0 ] || { echo "no PoCs ran -- a green suite that tested nothing" >&2; exit 1; }
    if [ "$refused" -gt 0 ]; then
      echo "$ran PoC(s) ran and $refused rendered NO VERDICT: this machine was too" >&2
      echo "busy to measure linearity on. Every other check in them passed." >&2
      exit 3
    fi
    echo "$ran PoC(s) passed"

# Differential-test the RV32I encoder against GNU as
poc-encoder:
    nix develop --command bash poc/01-encoder/run.sh

# Exercise the C89 lexer: token tables, round-trip, throughput, mutation test
poc-lexer:
    nix develop --command bash poc/02-lexer/run.sh

# Exercise the lburg-style tree matcher: rule table, labelling, cost duels,
# emitted RV32 assembly executed in the Nix emulator, scale, mutation test
poc-matcher:
    nix develop --command bash poc/03-matcher/run.sh

# Exercise the RV32 assembler: layout, labels, lui/addi materialisation,
# a byte-for-byte differential against GNU as, execution in the Nix emulator
poc-assembler:
    nix develop --command bash poc/04-assembler/run.sh

# Close the loop: compile a C program, assemble it and execute it in the Nix
# RV32I emulator inside one `nix eval' with no toolchain on PATH, plus the
# fault table, the memory measurement and the mutation test
poc-loop:
    nix develop --command bash poc/05-loop/run.sh

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
    nix develop --command shellcheck poc/*/*.sh
    echo "lint clean"

# Print the pinned reference sources (lcc, tinycc, nix-riscv)
sources:
    @nix develop --command sh -c 'echo "lcc:       $LCC_SRC"; echo "tinycc:    $TINYCC_SRC"; echo "nix-riscv: $NIX_RISCV"'

# Enter the dev shell
shell:
    nix develop
