#!/usr/bin/env bash
# Differential test: our Nix RV32I encoder vs GNU as.
#
# The harness is as much on trial as the encoder. A test that reports PASS
# while comparing nothing is worse than no test, so every step that could
# silently produce an empty or short comparison is guarded below.
set -euo pipefail
# Scratch work happens on a tmpfs inside a bubblewrap sandbox, which the kernel
# reclaims when this process exits: no cleanup, no trap, nothing to delete.
# This re-execs, so it comes before anything else. See poc/lib/sandbox.sh.
# shellcheck source-path=SCRIPTDIR source=../lib/sandbox.sh
. "$(dirname "$(readlink -f "$0")")/../lib/sandbox.sh"
cd "$(dirname "$0")"

nix eval --impure --raw --expr \
  'builtins.concatStringsSep "\n" (map (c: c.asm) (import ./cases.nix))' > "$work/in.s"
printf '\n' >> "$work/in.s"
nix eval --impure --raw --expr \
  'let cs = import ./cases.nix; e = import ./encode.nix;
   in builtins.concatStringsSep "\n" (map (c: e.toHex c.word) cs)' > "$work/ours.txt"

riscv32-none-elf-as -march=rv32i -o "$work/a.o" "$work/in.s"
riscv32-none-elf-objcopy -O binary --only-section=.text "$work/a.o" "$work/a.bin"

python3 ./compare.py "$work"

# Separate must-fail suite: a differential test cannot exercise throw paths,
# so if `fits` were inverted every case above would still pass.
nix eval --impure --raw --file ./must-fail.nix
