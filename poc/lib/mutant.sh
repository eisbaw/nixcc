#!/usr/bin/env bash
# One mutation, run against a copy of a PoC directory that lives on a tmpfs of
# its own. Meant to be exec'd by bwrap:
#
#     bwrap --dev-bind / / --tmpfs "$mut" --die-with-parent -- \
#       bash poc/lib/mutant.sh "$poc" "$mut" "$apply" "$run" "$edits"
#
# The tmpfs is what makes the copy fresh. The pattern this replaces was
# `rm -rf "$mut"; cp -r "$poc" "$mut"', which is fresh only if the remove
# succeeded completely -- and a mutation testing a half-reverted tree is the
# kind of harness fault that reports as a clean pass. Here there is nothing to
# remove: the mount is empty because it was created empty, and it is gone when
# this process is.
#
# Exit status is the mutated suite's own, so the caller can tell "the mutation
# was not detected" (0) from "it was" (anything else) exactly as before. The
# three ways this script itself can fail use statuses no evaluator or python
# harness produces, so the caller can name them instead of reporting them as a
# detection:
#
#   120  the copy failed
#   121  the mutation's own commands failed
#   122  the mutation edited nothing, having said it would
#   123  EDITS-TREE was neither `yes' nor `no'
#
# Those four are outside what an evaluator or a python harness returns today.
# That is a property of the suites this runs rather than a guarantee about
# every possible one, and it is the reason the numbers are high and odd.
set -uo pipefail

poc=${1:?usage: mutant.sh POC MUT APPLY RUN EDITS-TREE}
mut=${2:?usage: mutant.sh POC MUT APPLY RUN EDITS-TREE}
apply=${3:?usage: mutant.sh POC MUT APPLY RUN EDITS-TREE}
run=${4:?usage: mutant.sh POC MUT APPLY RUN EDITS-TREE}
# `yes' or `no': does APPLY change files, or does it change the INVOCATION?
# Declared by the caller rather than guessed from the snippet's text. An
# earlier version checked whether APPLY was literally the word `true', which
# put the caller's intent inside the callee and made a trailing space change
# the meaning.
edits=${5:?usage: mutant.sh POC MUT APPLY RUN EDITS-TREE}
case "$edits" in yes|no) ;; *) exit 123 ;; esac

[ -d "$mut" ] || exit 120
# Contents, not the directory: $mut already exists, because it is the mount
# point the tmpfs was put on.
cp -r "$poc"/. "$mut" || exit 120
cd "$mut" || exit 120
# A subshell with -e, so that a compound apply -- `sed -i A; sed -i B' -- is
# not reported as clean because its LAST clause succeeded. `eval' on its own
# carries only the last status.
( set -e; eval "$apply" ) || exit 121

# A sed whose pattern no longer matches edits nothing, and the suite then
# passes, which reads as "not detected" when the truth is "not applied".
# Renaming a binding in the code under test is enough to cause it. A mutation
# that changes the INVOCATION rather than the tree says so with EDITS-TREE=no.
if [ "$edits" = yes ] && diff -rq "$poc" "$mut" >/dev/null; then
  exit 122
fi

eval "$run"
