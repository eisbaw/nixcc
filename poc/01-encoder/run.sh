#!/usr/bin/env bash
# Differential test: our Nix RV32I encoder vs GNU as.
set -euo pipefail
cd "$(dirname "$0")"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

nix eval --impure --raw --expr \
  'builtins.concatStringsSep "\n" (map (c: c.asm) (import ./cases.nix))' > "$work/in.s"
printf '\n' >> "$work/in.s"
nix eval --impure --raw --expr \
  'let cs = import ./cases.nix; e = import ./encode.nix;
   in builtins.concatStringsSep "\n" (map (c: e.toHex c.word) cs)' > "$work/ours.txt"

riscv32-none-elf-as -march=rv32i -o "$work/a.o" "$work/in.s"
riscv32-none-elf-objcopy -O binary --only-section=.text "$work/a.o" "$work/a.bin"

python3 - "$work" <<'PY'
import sys, struct, pathlib
w = pathlib.Path(sys.argv[1])
asm   = w.joinpath("in.s").read_text().split("\n")
asm   = [l for l in asm if l.strip()]
ours  = w.joinpath("ours.txt").read_text().split()
raw   = w.joinpath("a.bin").read_bytes()
theirs = ["%08x" % v for (v,) in struct.iter_unpack("<I", raw)]

if len(theirs) > len(ours):          # GNU as pads .text to section alignment
    pad, theirs = theirs[len(ours):], theirs[:len(ours)]
    if any(p != "00000000" for p in pad):
        print("unexpected trailing words from as:", pad); sys.exit(1)

assert len(asm) == len(ours), (len(asm), len(ours))
bad = 0
for a, o, t in zip(asm, ours, theirs):
    if o != t:
        print(f"MISMATCH  {a:<28}  ours={o}  as={t}"); bad += 1
print(f"{len(ours)} instructions compared against GNU as")
print("PASS" if bad == 0 else f"FAIL: {bad} mismatch(es)")
sys.exit(1 if bad else 0)
PY
