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
# What that proves, and it is now a good deal more than it was. This stage used
# to build a directory holding one symlink to `nix' and run the demo with that
# as PATH, which its author called "closer to a demonstration than a proof":
# PATH says what a program will find by NAME, and nothing at all about what it
# could open by absolute path. The toolchain was still sitting in the
# filesystem a dozen characters away.
#
# It now runs inside a bubblewrap sandbox that binds NOTHING but nix's own
# runtime closure -- 63 store paths on this machine, of which the only three
# whose names mention a compiler are libgcc and libstdc++ runtime libraries --
# plus the PoC directory it evaluates and the emulator it imports. There is no
# assembler, linker or objcopy in the sandbox's filesystem to find, by name or
# by path, and the stage checks exactly that: it asks nix itself, from inside,
# whether the absolute path of each host tool exists. `builtins.pathExists' is
# the one probe available, because the sandbox is minimal enough that there is
# no /bin/sh in it either.
#
# What it still does not prove is that this particular expression COULD have
# reached a toolchain: a `nix eval' of a pure expression can only reach a
# binary through import-from-derivation, so for this expression the property is
# close to true by construction. What it now does rule out is the thing that
# has actually gone wrong in this repo before -- a harness that quietly shells
# out to binutils on the way to its answer -- and it rules it out by absence
# rather than by naming.
#
# The expectation is read in a SECOND evaluation, outside the sandbox, and not
# because that buys independence -- it does not, it imports the same driver.nix
# from the same directory, and the pin is a literal either way. It is because
# only the first evaluation runs under the guard, and keeping that one down to
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
command -v bwrap >/dev/null || {
  echo "no \`bwrap' on PATH; this stage cannot build the sandbox it needs" >&2; exit 2; }

nix_real=$(readlink -f "$(command -v nix)")
nix_bin=$(dirname "$nix_real")
# nix's RUNTIME closure, which is what it needs to run and nothing else. Every
# path read-only: this evaluation writes nothing outside the tmpfs below.
guarded=()
while read -r path; do
  guarded+=(--ro-bind "$path" "$path")
done < <(nix path-info -r "$nix_real")
[ "${#guarded[@]}" -ge 20 ] || {
  echo "nix's runtime closure came back as ${#guarded[@]} bind arguments," >&2
  echo "which is too few to be the real thing -- refusing to claim a sandbox" >&2
  echo "that may simply be binding the host" >&2; exit 1; }
guarded+=(
  # HOME and TMPDIR both under /tmp, which exists on any root and so can be
  # mounted over. A tmpfs on a top-level path of its own works when this is the
  # outermost sandbox and fails with "Can't mkdir: Permission denied" when
  # run.sh's mutation stage nests it inside the harness sandbox, which is not a
  # difference this stage should be able to notice.
  --proc /proc --dev /dev --tmpfs /tmp
  --setenv HOME /tmp --setenv TMPDIR /tmp
  --setenv PATH "$nix_bin"
  # The user's nix.conf is not in the sandbox, so the features this needs are
  # stated here rather than inherited. That is the more hermetic half of the
  # bargain: the stage no longer depends on how the reader configured nix.
  --setenv NIX_CONFIG "experimental-features = nix-command"
  --ro-bind /nix/var/nix /nix/var/nix
  --ro-bind "$poc" "$poc"
  --ro-bind "$NIX_RISCV" "$NIX_RISCV"
  --die-with-parent
)

# The PoC directory reaches its siblings by relative path -- demo.nix imports
# ../03-matcher and ../04-assembler -- so bind the tree it sits in rather than
# only itself.
poc_parent=$(dirname "$poc")
[ "$poc_parent" = / ] || guarded+=(--ro-bind "$poc_parent" "$poc_parent")

# And bind what any sibling SYMLINK points at. run.sh's mutation stage runs
# this against a copy of the PoC directory whose siblings are links back into
# the real tree -- they are not what is being mutated, and a copy of them is a
# copy that could go stale -- so a sandbox that bound only the copy would fail
# to follow them, with an error about a path that plainly does exist. Binding
# them does not loosen what this stage claims: the absence check below runs
# against the finished bind list, so anything that arrived this way and should
# not have is caught rather than assumed away.
for link in "$poc_parent"/*; do
  [ -L "$link" ] || continue
  target=$(readlink -f "$link") || continue
  [ -e "$target" ] && guarded+=(--ro-bind "$target" "$target")
done

in_sandbox() { bwrap "${guarded[@]}" -- "$nix_bin/nix" "$@"; }

# Absence, not invisibility. PATH would only say that these are not reachable
# by NAME; this asks nix, from inside the sandbox, whether the absolute path
# each of them occupies on this host exists there at all.
absent=0
for tool in riscv32-none-elf-as riscv32-none-elf-ld riscv32-none-elf-objcopy gcc as ld; do
  abs=$(command -v "$tool" 2>/dev/null) || continue
  abs=$(readlink -f "$abs")
  # The answer has to be one of two words. A probe that simply FAILED -- a
  # sandbox that could not be built, a nix that would not start -- produces
  # empty output, and "empty is not yes" would have read as "absent": the
  # check would pass most loudly exactly when it had stopped working.
  probe=$(in_sandbox eval --impure --raw --expr \
          "if builtins.pathExists \"$abs\" then \"yes\" else \"no\"" 2>&1) || {
    echo "the sandbox could not be entered to ask whether $tool is inside it:" >&2
    echo "$probe" >&2
    echo "That is a broken check rather than an absent toolchain, so this stage" >&2
    echo "renders no verdict on the toolchain at all." >&2
    exit 2; }
  case "$probe" in
    yes) echo "$tool is still reachable inside the sandbox at $abs," >&2
         echo "so running the demo in it would prove nothing about the toolchain." >&2
         exit 1 ;;
    no)  absent=$((absent + 1)) ;;
    *)   echo "the reachability probe for $tool answered '$probe', which is" >&2
         echo "neither yes nor no; the check is not asking what it thinks" >&2
         exit 2 ;;
  esac
done
# A loop that checked nothing would also print no complaint. The host has all
# six of these on PATH inside `nix develop'; fewer than three means the tools
# were not found to check FOR, and the absence above is then vacuous.
[ "$absent" -ge 3 ] || {
  echo "only $absent of the host toolchain's binaries were on PATH to check for," >&2
  echo "so \"none of them is reachable in the sandbox\" is a claim about nothing" >&2
  exit 1; }
echo "  no toolchain in the sandbox: $absent host binaries checked by absolute path, none present"

# ONE evaluation. It reads hello.sym, selects instructions, assembles them to
# bytes and executes those bytes on the RV32I machine, and hands back what the
# program printed.
got=$(in_sandbox eval --impure --json --expr "
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
print(f"  one nix eval, in a filesystem holding nothing but nix: {got['steps']} RV32I "
      f"instructions executed,")
print(f"  {len(got['stdoutBytes'])} bytes written through the write syscall, exit status "
      f"{got['exitCode']} through the exit syscall")
sys.stdout.write("  the program printed: " + got["stdout"])
PY
