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

# Prove the harnesses name their one hard requirement rather than failing
# obscurely without it. Every run.sh re-execs itself inside bubblewrap, which
# needs unprivileged user namespaces; a machine without them has to be told so.
# That cannot be arranged by turning the kernel feature off, so a stub `bwrap'
# that fails the way such a kernel does is put in front of the real one -- and
# the stub lives on a tmpfs inside a sandbox of its own, so this check leaves
# nothing behind either.
sandbox-refuses:
    #!/usr/bin/env bash
    set -uo pipefail
    out=$(bwrap --dev-bind / / --tmpfs /tmp -- bash -c '
      mkdir /tmp/stub && cp poc/lib/no-userns-bwrap.sh /tmp/stub/bwrap
      PATH=/tmp/stub:$PATH exec bash poc/01-encoder/run.sh' 2>&1)
    status=$?
    [ "$status" = 2 ] || {
      echo "with bubblewrap unable to start, a harness exited $status; a missing" >&2
      echo "kernel feature is a harness fault (2), not a verdict on the thing" >&2
      echo "under test:" >&2; echo "$out" >&2; exit 1; }
    for want in "UNPRIVILEGED USER NAMESPACES" "setting up uid map" "harness fault"; do
      case "$out" in
        *"$want"*) ;;
        *) echo "the no-sandbox diagnostic never said \"$want\":" >&2
           echo "$out" >&2; exit 1 ;;
      esac
    done
    echo "a machine without unprivileged user namespaces is told so, in bwrap's own words"

# Run every proof-of-concept
poc:
    #!/usr/bin/env bash
    set -euo pipefail
    # Outside any sandbox, because it is the entry to the sandbox it checks.
    just sandbox-refuses
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
# RV32I emulator inside one `nix eval' in a sandbox holding nothing but nix's
# own runtime closure, plus the fault table, the memory measurement and the
# mutation test
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
    # -x so that the sandbox helper every run.sh sources is followed rather
    # than warned about, and so $work is seen to be assigned where it is.
    nix develop --command shellcheck -x poc/*/*.sh
    just no-deletes
    echo "lint clean"

# No harness may delete anything. Their scratch work lives on a tmpfs inside a
# bubblewrap sandbox (poc/lib/sandbox.sh) that the kernel reclaims when the
# process exits, so there is nothing to remove -- and a `rm -rf' that creeps
# back in would be both unnecessary and, on the wrong variable, unbounded.
# Written as a grep because "we removed them all" is a claim about one moment
# and this is a claim about every run.
#
# Whole-line comments are skipped, and that is deliberate rather than a gap: a
# comment is not a command, and the files that explain WHY these harnesses no
# longer delete anything have to be able to quote what they replaced. A line
# with code on it is checked whatever it also says, so `foo && rm -rf bar # x'
# is still caught. An executed line that genuinely has to survive can carry a
# trailing `# ok:' and its reason.
no-deletes:
    #!/usr/bin/env bash
    set -uo pipefail
    pattern='(^|[;&|(` ])(rm|rmdir|shred|truncate)([ ]|$)|git[ ]+clean|git[ ]+reset[ ]+--hard'
    hits=$(grep -nEH "$pattern" poc/*/*.sh poc/*/*.py Justfile \
           | grep -vE ':[0-9]+:[[:space:]]*#' | grep -v '# ok:' || true)
    if [ -n "$hits" ]; then
      echo "delete-shaped commands in the harnesses:" >&2
      echo "$hits" >&2
      echo >&2
      echo "Scratch work belongs on the sandbox tmpfs, which the kernel reclaims" >&2
      echo "when the harness exits, so there is nothing to clean up. If one of" >&2
      echo "these genuinely has to run, mark the line '# ok:' and say why." >&2
      exit 1
    fi
    echo "no delete-shaped commands in any harness"

# Print the pinned reference sources (lcc, tinycc, nix-riscv)
sources:
    @nix develop --command sh -c 'echo "lcc:       $LCC_SRC"; echo "tinycc:    $TINYCC_SRC"; echo "nix-riscv: $NIX_RISCV"'

# Enter the dev shell
shell:
    nix develop
