#!/usr/bin/env bash
# The headline demo: ONE `nix eval', no toolchain, C in and program output out.
#
# check.nix already runs the same chain and checks far more about it. This
# stage exists for the one claim check.nix cannot make about itself: that
# nothing outside the evaluator is involved. It runs the compile-assemble-
# execute eval with a PATH holding exactly one binary -- nix -- and REFUSES to
# render a verdict if the cross assembler, linker or objcopy is still
# reachable from it.
#
# Be clear about how much that proves. A `nix eval' of a pure expression could
# only reach a PATH binary through import-from-derivation, so for THIS
# expression the property is close to true by construction and this stage is a
# demonstration more than a proof. What it does rule out is the thing that has
# actually gone wrong in this repo before: a harness that quietly shells out
# to binutils on the way to its answer. It is also the stage a reader runs to
# see the claim, which is worth having on its own.
#
# The expectation is read in a SECOND evaluation, and not because that buys
# independence -- it does not, it imports the same driver.nix from the same
# directory, and the pin is a literal either way. It is because only the first
# evaluation runs under the guarded PATH, and keeping that one down to
# "compile, assemble, run, hand back what was printed" is the whole point of
# the stage.
#
# Its own file rather than a block inside run.sh so that run.sh's mutation
# stage can run it against a mutated copy without re-entering run.sh.
#
#   closed-loop.sh POC_DIR
set -euo pipefail
poc=${1:?usage: closed-loop.sh POC_DIR}
: "${NIX_RISCV:?NIX_RISCV is unset -- run this inside nix develop}"

# A directory holding ONE symlink, to `nix'. Not the directory nix happens to
# live in: on this machine that is the system profile, 1566 binaries including
# a host assembler and linker, and "no toolchain" measured against it would be
# a much weaker statement than it reads.
tools=$(mktemp -d)
trap 'rm -rf "$tools"' EXIT
ln -s "$(command -v nix)" "$tools/nix"
guarded=$tools

PATH=$guarded command -v nix >/dev/null 2>&1 || {
  echo "nix is not reachable from the guarded PATH ($guarded); this stage cannot run" >&2; exit 1; }
for tool in riscv32-none-elf-as riscv32-none-elf-ld riscv32-none-elf-objcopy; do
  if PATH=$guarded command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is still reachable from the guarded PATH ($guarded)," >&2
    echo "so running the demo under it would prove nothing about the toolchain." >&2
    exit 1
  fi
done

# ONE evaluation. It reads hello.sym, selects instructions, assembles them to
# bytes and executes those bytes on the RV32I machine, and hands back what the
# program printed.
got=$(PATH=$guarded nix eval --impure --json --expr "
  let cpu = import (/. + \"$NIX_RISCV/rv32.nix\");
      d = import $poc/demo.nix { inherit cpu; };
  in { inherit (d.report) reason exitCode steps stdout stdoutBytes; }")

want=$(nix eval --impure --json --expr \
  "let d = import $poc/driver.nix { }; in { inherit (d) expectedStdout expectedBytes; }")

python3 - "$got" "$want" <<'PY'
import json, sys
got, want = json.loads(sys.argv[1]), json.loads(sys.argv[2])
if got["reason"] != "exit":
    sys.exit(f"the demo halted with reason {got['reason']!r}, not a clean exit")
if got["exitCode"] != 0:
    sys.exit(f"the demo exited {got['exitCode']}, not 0")
if got["stdoutBytes"] != want["expectedBytes"]:
    sys.exit(f"the program wrote {got['stdoutBytes']}, expected {want['expectedBytes']} "
             f"-- it printed {got['stdout']!r}, expected {want['expectedStdout']!r}")
if got["stdout"] != want["expectedStdout"]:
    sys.exit(f"the program printed {got['stdout']!r}, expected {want['expectedStdout']!r}")
if got["steps"] < 100:
    sys.exit(f"the machine ran {got['steps']} instructions; nothing was executed")
print(f"  one nix eval, nothing but nix on PATH: {got['steps']} RV32I instructions executed,")
print(f"  {len(got['stdoutBytes'])} bytes written through the write syscall, exit status "
      f"{got['exitCode']} through the exit syscall")
sys.stdout.write("  the program printed: " + got["stdout"])
PY
