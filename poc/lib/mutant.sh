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
#
# A NOTE FOR CALLERS, not a property of this file: how many of these ran.
#
# It is here because it is one reason and not four, and because this is the
# only file all four mutation stages go through. It does not belong here --
# this script runs ONE mutation and never sees a table -- and the reason it has
# nowhere better to go is that mutate() itself is copied into four run.sh files
# rather than living beside this one. That is task-044.
#
# A count that is PRINTED rather than asserted goes quietly down when a mutate
# call is dropped, commented out or lost to a merge, and the suite then reports
# the smaller number just as confidently as the larger one. The case that
# really bites is the empty one: with no mutations recorded at all, the
# distinctness loop above the count iterates zero times, checks nothing, and
# the stage prints "0 mutations, each detected with its own distinct failure"
# -- its cleanest line, after testing nothing. That is the same shape as an
# absence check with no binaries to look for, which this tree shipped and
# fixed. The one-missing case is milder: the printed number does change, and
# what is wrong is that no machine notices.
#
# So each harness DECLARES its count and asserts equality, and equality is the
# point rather than pedantry. poc/05-loop had a `-ge 34' floor while 36 ran:
# nobody lowered it, two commits added mutations and left it behind, and the
# slack was then there to be spent downward in silence. A floor only catches
# the direction that has never happened here. `-eq' catches both, and the edit
# it forces when a mutation is added is the edit that was wanted anyway.
#
# The four harnesses that use this each declare a count today. Nothing checks
# that a fifth will, and this comment is not that check -- see task-044.

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
