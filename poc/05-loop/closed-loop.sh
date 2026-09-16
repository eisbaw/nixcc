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
# It now runs inside a bubblewrap sandbox that binds nix's own runtime closure
# -- three score store paths on this machine, and the only ones whose names
# mention a compiler at all are gcc's own runtime libraries, libgcc and
# libstdc++ -- plus the PoC directory it evaluates, the tree that directory
# sits in, and the emulator it imports. A floor below refuses a closure too
# small to be the real one, which is the part that cannot go stale. There is no
# assembler, linker or objcopy in the sandbox's filesystem to find, by name or
# by path, and the stage checks exactly that: it asks nix itself, from inside,
# whether the absolute path of each host tool exists. `builtins.pathExists' is
# the one probe available, because the sandbox is minimal enough that there is
# no /bin/sh in it either.
#
# The sandbox also unshares the network and does NOT bind /nix/var/nix, so the
# nix daemon is unreachable and nix falls back to a chroot store inside the
# tmpfs. That matters because import-from-derivation is the one escape a pure
# `nix eval' actually has, and an earlier draft of this stage left the daemon
# socket bound -- which would have let an evaluation realise a derivation on
# the HOST, with the real toolchain, while this file claimed hermeticity.
# Checked: `builtins.fetchurl' now fails and `nix store info' reports a chroot
# store rather than the daemon.
#
# BOUND THE CLAIM ANYWAY, because it is a sampled absence and not a proof of
# absence. Six names are probed. That does not establish that no compiler of
# any name is in the sandbox -- busybox is in nix's runtime closure and does
# ship an `sh', though not an assembler. And a chroot store is still a store:
# nothing here proves an evaluation could not build SOMETHING, only that it
# could not use this machine's toolchain or its daemon to do it. What the
# stage does establish is the thing that has actually gone wrong in this repo
# before -- a harness that quietly shells out to binutils on the way to its
# answer -- and it establishes it by absence rather than by naming.
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
closure=0
while read -r path; do
  guarded+=(--ro-bind "$path" "$path")
  closure=$((closure + 1))
done < <(nix path-info -r "$nix_real")
# Paths, not array elements: each path contributes three of the latter, so a
# floor written against ${#guarded[@]} would have been a third of what it read
# like. The number itself is a floor rather than the count, which was 63 when
# this was written -- a count in a comment rots, a floor that fails does not.
[ "$closure" -ge 20 ] || {
  echo "nix's runtime closure came back as $closure store paths, which is too" >&2
  echo "few to be the real thing -- refusing to claim a sandbox that may simply" >&2
  echo "be binding the host" >&2; exit 1; }
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
  # No /nix/var/nix and no network: see the header. Without the first, nix
  # cannot reach the daemon and uses a chroot store under the tmpfs HOME;
  # without the second, nothing in the evaluation can fetch.
  --unshare-net
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
# them is a real widening of the bind list, and the absence check below is a
# probe of six names rather than an audit of everything bound -- so what keeps
# this honest is that the links are the PoC's own siblings, in a tree with no
# toolchain in it, and that those six names are probed after the list is
# finished rather than before.
for link in "$poc_parent"/*; do
  [ -L "$link" ] || continue
  target=$(readlink -f "$link") || continue
  [ -e "$target" ] && guarded+=(--ro-bind "$target" "$target")
done

in_sandbox() { bwrap "${guarded[@]}" -- "$nix_bin/nix" "$@"; }

# $1 an absolute path; prints `yes' or `no' for whether it exists inside the
# sandbox. Anything else -- a sandbox that would not build, a nix that would
# not start -- is a broken check rather than an absent toolchain, and says so
# rather than letting empty output read as "not yes, therefore absent".
reachable() {
  local expr answer
  expr="if builtins.pathExists \"$1\" then \"yes\" else \"no\""
  # stderr discarded for the ANSWER and shown for the DIAGNOSIS. nix prints two
  # warnings on every call in here -- no network, and no /nix/var/nix so it
  # uses a chroot store -- and folding them into the answer is how a draft of
  # this check came to read `warning: ...\nyes' and refuse a sandbox that was
  # working perfectly. On failure the same evaluation is run once more with its
  # output visible, so the reason still reaches the reader.
  if ! answer=$(in_sandbox eval --impure --raw --expr "$expr" 2>/dev/null); then
    echo "the sandbox could not be entered to ask whether $1 is inside it." >&2
    echo "Running the same evaluation again with its diagnostics:" >&2
    in_sandbox eval --impure --raw --expr "$expr" >&2 || true
    echo "That is a broken check rather than an absent toolchain, so this stage" >&2
    echo "renders no verdict on the toolchain at all." >&2
    exit 2
  fi
  case "$answer" in
    yes|no) printf '%s' "$answer" ;;
    *) echo "the reachability probe for $1 answered '$answer', which is" >&2
       echo "neither yes nor no; the check is not asking what it thinks" >&2
       exit 2 ;;
  esac
}

# THE POSITIVE CONTROL, and it goes first. Every probe below reports absence,
# and a probe that can only ever report absence reports it most confidently
# when it has stopped asking: replace `builtins.pathExists' with `false' and
# six tools come back missing and this stage prints its greenest line. So ask
# it about a path that MUST be there -- nix's own binary, which is running the
# question -- and require a yes before believing any no.
[ "$(reachable "$nix_real")" = yes ] || {
  echo "the reachability probe says nix itself is not in the sandbox, which is" >&2
  echo "being asked from inside the sandbox by that very binary. The probe is" >&2
  echo "not measuring what is there, so nothing it says about the toolchain" >&2
  echo "means anything." >&2; exit 2; }

# Absence, not invisibility. PATH would only say that these are not reachable
# by NAME; this asks nix, from inside the sandbox, whether the absolute path
# each of them occupies on this host exists there at all.
absent=0
for tool in riscv32-none-elf-as riscv32-none-elf-ld riscv32-none-elf-objcopy gcc as ld; do
  abs=$(command -v "$tool" 2>/dev/null) || continue
  abs=$(readlink -f "$abs")
  if [ "$(reachable "$abs")" = yes ]; then
    echo "$tool is still reachable inside the sandbox at $abs," >&2
    echo "so running the demo in it would prove nothing about the toolchain." >&2
    exit 1
  fi
  absent=$((absent + 1))
done
# A loop that checked nothing would also print no complaint. The host has all
# six of these on PATH inside `nix develop'; fewer than three means the tools
# were not found to check FOR, and the absence above is then vacuous.
[ "$absent" -ge 3 ] || {
  echo "only $absent of the host toolchain's binaries were on PATH to check for," >&2
  echo "so \"none of them is reachable in the sandbox\" is a claim about nothing" >&2
  exit 1; }
echo "  no toolchain in the sandbox: $absent host binaries checked by absolute path, none present"

# ONE evaluation. It reads hello.c -- the C, not lcc's listing, since task-028
# closed the last arrow that left the evaluator -- lexes it, parses it into the
# DAG, selects instructions, assembles them to bytes, executes those bytes on
# the RV32I machine, and hands back what the program printed.
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
