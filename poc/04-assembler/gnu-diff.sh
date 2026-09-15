#!/usr/bin/env bash
# The byte-for-byte differential against GNU as, on ONE program, run against a
# given copy of this PoC.
#
#   gnu-diff.sh TREE NAME
#
# Its own file rather than a function in run.sh for the reason run.sh's other
# helpers are: the mutation stage runs each mutation in a mount namespace of
# its own, and a shell function defined in run.sh is not in scope there. It was
# briefly `export -f gnu_diff' instead, which worked and was wrong -- the child
# then ran the PARENT's copy, so this file was the one part of the differential
# path a mutation could not reach, while the comment beside it claimed the
# opposite. As a script under TREE it is the MUTATED copy that runs, which is
# what "breaking the comparison is itself testable" was always supposed to mean.
#
# `data' is the program that carries alignment padding and a symbol-valued
# .word, so it is the one whose bytes move for the mutations the pure checks
# cannot see.
set -euo pipefail
tree=$(cd "${1:?usage: gnu-diff.sh TREE NAME}" && pwd)
name=${2:?usage: gnu-diff.sh TREE NAME}

# Under the tree being tested, which during a mutation is a tmpfs created fresh
# for that one mutation: nothing from a previous differential can be in it, and
# nothing from this one outlives the process.
out=$tree/gnu-diff-$name
mkdir -p "$out"
nix eval --impure --json --expr "
  let a = import $tree/asm.nix { };
      p = import $tree/parse.nix { asm = a; };
      r = a.assemble { items = p.parseFile (/. + \"$tree/progs/$name.s\"); };
  in { inherit (r) bytes dataBase; }" > "$out/ours.json"
python3 - "$out" <<'PYEOF'
import json, sys
out = sys.argv[1]
r = json.load(open(f"{out}/ours.json"))
json.dump(r["bytes"], open(f"{out}/bytes.json", "w"))
# Hex with an 0x prefix: GNU ld's -Tdata reads a bare number as HEX, so
# passing 66048 put .data at 0x66048 and produced a 344 kB image.
open(f"{out}/database", "w").write("0x%x" % r["dataBase"])
PYEOF
riscv32-none-elf-as -march=rv32i -mno-relax -o "$out/whole.o" "$tree/progs/$name.s"
riscv32-none-elf-ld --no-relax -Ttext=0x10000 -Tdata="$(cat "$out/database")" \
  -o "$out/whole.elf" "$out/whole.o" 2>/dev/null
riscv32-none-elf-objcopy -O binary "$out/whole.elf" "$out/whole.bin"
python3 "$tree/diff.py" "$out/bytes.json" "$out/whole.bin" "$name"
