#!/usr/bin/env bash
# The IR this PoC compiles is REAL lcc output, re-proved on every run.
#
# hello.sym is checked in so that the closed loop can be evaluated with no
# compiler on the machine at all -- which is the whole point of the single-eval
# demo. A checked-in file is also a file that can be edited to say whatever
# makes the test pass, so it is regenerated from hello.c here and diffed.
#
# Always through the rcc-rv32 wrapper, never raw `rcc -target=symbolic': the
# raw oracle declares little_endian=0 and lays out bitfields for a big-endian
# machine (decision-004).
#
# Its own file rather than a block inside run.sh so that run.sh's mutation
# stage can run it against a mutated copy without re-entering run.sh.
#
#   provenance.sh POC_DIR
set -euo pipefail
# The scratch below lives on the sandbox's tmpfs, which the kernel reclaims
# when this process exits: no trap and nothing to delete. Sourced here as well
# as in run.sh because this file is also runnable on its own, and re-entering
# an existing sandbox is a no-op. See poc/lib/sandbox.sh.
# shellcheck source-path=SCRIPTDIR source=../lib/sandbox.sh
. "$(dirname "$(readlink -f "$0")")/../lib/sandbox.sh"
poc=${1:?usage: provenance.sh POC_DIR}
command -v rcc-rv32 >/dev/null || { echo "no rcc-rv32 on PATH -- run this inside nix develop" >&2; exit 1; }

# A directory of this process's own, since run.sh shares the same tmpfs and
# may be running several copies of this file against several mutated trees.
work=$work/provenance-$$
mkdir -p "$work"

rcc-rv32 < "$poc/hello.c" > "$work/hello.sym"
[ -s "$work/hello.sym" ] || { echo "rcc-rv32 produced nothing for $poc/hello.c" >&2; exit 1; }
if ! diff -u "$poc/hello.sym" "$work/hello.sym"; then
  echo "$poc/hello.sym is not what lcc produces for hello.c any more." >&2
  echo "Regenerate it with \`just ir poc/05-loop/hello.c' rather than editing it." >&2
  exit 1
fi
echo "hello.sym is what lcc produces for hello.c"
