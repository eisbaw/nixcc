#!/usr/bin/env bash
# Check that each reject case throws with the diagnostic it promised.
#
# builtins.tryEval hands back success and value but never the message, so "it
# threw" is all must-fail.nix can check by itself; a preprocessor whose every
# diagnostic read "error" would pass it. Re-evaluating each reject out here and
# grepping the message is the only way to hold the refusals to a contract, and
# this project's rule -- refuse loudly, naming the task that will do the thing
# -- is half untested without it.
#
# FIVE FRAGMENTS ARE LOAD-BEARING BEYOND THEIR OWN CASE, because they are the
# only thing that stops a deferral from going unfiled:
#
#   * `task-013.02' on the function-like, stringify and paste refusals.
#   * `task-013.03' and `task-070' on #include, which is blocked rather than
#     merely unwritten -- where a header resolves from is undecided.
#   * `task-014' on a directive the minimal preprocessor does not implement,
#     which is the task that records what it deliberately leaves out.
#   * `task-008' on a phase-2 splice, which is a KNOWN divergence from ISO C
#     and not a bug: the reader has to be able to tell those apart.
#   * `decision-006' on a float in a `#if', for the same reason
#     poc/06-constants pins it -- a deferred CHOICE reads as a gap otherwise.
#
# Its own file rather than a block inside run.sh so that run.sh's mutation
# stage can run it against a mutated copy without re-entering run.sh.
#
#   messages.sh POC_DIR
set -euo pipefail
poc=${1:?usage: messages.sh POC_DIR}

# The count comes from must-fail.nix, which declares one number and asserts its
# own table against it. A second constant here would be a second thing to
# forget to raise.
n=$(nix eval --impure --expr "builtins.length (import $poc/must-fail.nix).cases")
declared=$(nix eval --impure --expr "(import $poc/must-fail.nix).declaredCases")
[ "$n" = "$declared" ] || {
  echo "must-fail.nix holds $n cases against the $declared it declares" >&2; exit 1; }

for i in $(seq 0 $((n - 1))); do
  meta=$(nix eval --impure --raw --expr \
    "let r = builtins.elemAt (import $poc/must-fail.nix).cases $i;
     in \"\${r.what}\t\${r.expect}\"")
  what=${meta%%$'\t'*}
  expect=${meta#*$'\t'}
  [ -n "$expect" ] || {
    echo "reject case '$what' has no expected fragment at all" >&2; exit 1; }
  msg=$(nix eval --impure --expr \
    "(import $poc/must-fail.nix).forceReject $i" 2>&1) && {
    echo "reject case '$what' did not throw at all" >&2; exit 1; }
  # Only the final `error:' line, not nix's whole trace: the trace echoes
  # source lines from must-fail.nix and cpp.nix, and a fragment matching one of
  # those would be matching the test rather than the diagnostic.
  #
  # `|| true' because grep exits 1 when it matches nothing, and under
  # `pipefail' that kills the assignment and takes the script with it -- so a
  # refusal that threw WITHOUT an `error:' line used to die silently at
  # exactly the point whose whole job is to report a missing diagnostic.
  final=$(printf '%s\n' "$msg" | { grep -E '^ *error: ' || true; } | tail -1)
  case "$final" in
    *"$expect"*) ;;
    *) echo "reject case '$what' threw, but its diagnostic does not contain" >&2
       echo "  \"$expect\"" >&2
       echo "  it said: $final" >&2
       exit 1 ;;
  esac
done
echo "$n refusals checked for the diagnostic text each promised"
