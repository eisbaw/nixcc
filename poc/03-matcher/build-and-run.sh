#!/usr/bin/env bash
# Compile ONE case with the matcher, assemble and link it with the cross
# toolchain, and RUN it in the Nix RV32I emulator -- against a given copy of
# this PoC.
#
#     build-and-run.sh TREE NAME OUT
#
# On success it prints the emulator's own answer as JSON -- halted, reason,
# exitCode, steps -- plus the instruction count of the assembled function, and
# nothing else, so a caller can read its whole stdout with json.loads.
#
# IT REPORTS, IT DOES NOT JUDGE. A program that faulted, or that ran out of the
# step budget without reaching its exit syscall, comes back here as a clean
# exit 0 and a `reason' that is not "exit". Deciding what the answer should
# have been needs cases.nix, which is the caller's business and not this
# script's -- both callers in run.sh check `reason' and then the exit code
# against the corpus, and a third would have to as well.
#
# Its own file rather than a function in run.sh, for the reason
# poc/04-assembler/gnu-diff.sh is one: the mutation stage runs each mutation
# inside a mount namespace of its own, and a shell function defined in run.sh
# is not in scope there. As a script under TREE it is the MUTATED copy that
# runs. That matters more here than anywhere else in this tree -- this is the
# only thing in poc/03-matcher that EXECUTES the code, and so the only way to
# catch a rule template computing the wrong thing while satisfying every
# assertion check.nix makes about the emitted text. Left as a function it was
# also the one mutation in the suite that could not be given a filesystem of
# its own (task-041).
#
# OUT is an argument rather than a path under TREE, which is where gnu-diff.sh
# puts its scratch. During a mutation TREE is a tmpfs and either would do; the
# main execution stage passes the real PoC directory, and that must not be
# written into.
set -euo pipefail
tree=$(cd "${1:?usage: build-and-run.sh TREE NAME OUT}" && pwd)
name=${2:?usage: build-and-run.sh TREE NAME OUT}
out=${3:?usage: build-and-run.sh TREE NAME OUT}
: "${NIX_RISCV:?NIX_RISCV is unset -- run this inside nix develop}"

mkdir -p "$out"
nix eval --impure --raw --expr \
  "((import $tree/emit.nix { }).compile
     ((import $tree/parse.nix).parse (builtins.readFile $tree/ir/$name.sym))).asm" \
  > "$out/$name.s"
[ -s "$out/$name.s" ] || { echo "$name: the matcher emitted nothing" >&2; exit 1; }

# -mno-relax and --no-relax. Linker relaxation rewrites `la rd,sym' into
# `addi rd,gp,off' whenever sym is within 2 KB of __global_pointer$, and that
# is correct only if the startup code loaded gp. None of drivers/*.s does:
# `_start' is the first instruction of the image and gp is zero, so the
# relaxed form addresses whatever sits near address 0. Not hypothetical --
# ir/gsym.c's `la s1,tbl+4' relaxed to `addi s1,gp,-2044' and the store
# faulted.
#
# Say plainly which way round this is: these programs do not conform to the
# gp half of the ABI, and the honest alternative is to make them conform by
# loading gp in a shared `_start' (task-031). Until then the flags are the
# smaller lie, because the target this project is building -- a Nix
# assembler that emits no relocations and a Nix emulator that sets no gp --
# cannot express the optimisation either. `2>/dev/null' on ld hides its
# `-z relro ignored' noise, and with it any real linker diagnostic; that is
# also task-031.
riscv32-none-elf-as -march=rv32i -mno-relax -o "$out/fn.o" "$out/$name.s"
riscv32-none-elf-as -march=rv32i -mno-relax -o "$out/rt.o" "$tree/runtime.s"
riscv32-none-elf-as -march=rv32i -mno-relax -o "$out/drv.o" "$tree/drivers/$name.s"
riscv32-none-elf-ld --no-relax -Ttext=0x10000 -o "$out/prog.elf" \
  "$out/drv.o" "$out/rt.o" "$out/fn.o" 2>/dev/null
riscv32-none-elf-objcopy -O binary "$out/prog.elf" "$out/prog.bin"

# The assembler is allowed to reject nothing silently: if it had produced an
# empty .text the emulator would fault rather than pass, but say so here.
#
# The floor is 5 and it only catches "essentially nothing came out" -- the
# smallest function in the corpus assembles to 29 instructions and `expr' to
# 66, so this would not notice four fifths of one going missing. Said rather
# than dressed up, because a floor that looks like a bound and is not is worse
# than no floor: what catches a function that lost most of its body is
# check.nix, which pins the emitted lines and their count.
#
# objdump's own failure is separated from grep finding nothing. `|| true' over
# the whole pipeline swallowed both under `pipefail', so an objdump that could
# not read the object at all reported "only 0 instructions in the assembled
# object" -- a statement about an object this script never saw.
riscv32-none-elf-objdump -d "$out/fn.o" > "$out/fn.dis"
insns=$(grep -cE '^\s+[0-9a-f]+:' "$out/fn.dis") || insns=0
[ "$insns" -ge 5 ] || {
  echo "$name: only $insns instructions in the assembled object" >&2; exit 1; }

python3 -c "import json,sys; json.dump(list(open(sys.argv[1],'rb').read()), open(sys.argv[2],'w'))" \
  "$out/prog.bin" "$out/prog.json"

nix eval --impure --json --expr "
  let cpu = import (/. + \"$NIX_RISCV/rv32.nix\");
      bytes = builtins.fromJSON (builtins.readFile $out/prog.json);
      final = cpu.run 200000 (cpu.load { inherit bytes; base = 65536; entry = 65536; });
  in { inherit (final) halted reason exitCode steps; insns = $insns; }"
