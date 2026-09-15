#!/usr/bin/env bash
# Check that each reject case throws with the diagnostic it promised.
#
# builtins.tryEval hands back success and value but never the message, so "it
# threw" is all must-fail.nix can check by itself; a frontend whose every
# diagnostic read "error" would pass it. Re-evaluating each reject out here and
# grepping the message is the only way to hold the refusals to a contract, and
# this project's rule -- refuse loudly, with a filed task per refusal -- is
# half untested without it.
#
# THREE FRAGMENTS ARE LOAD-BEARING BEYOND THEIR OWN CASE:
#
#   * `decision-006' and `task-015' on the float refusal, so that a reader who
#     meets it can tell a deferred CHOICE from a gap somebody forgot.
#
#   * `line 4:'. task-011 left this slice an open question: evalFCON THROWS,
#     a Nix throw cannot be caught and re-thrown with a position, and tryEval
#     discards the message -- so the one diagnostic decision-006 cares most
#     about was reaching the user with no idea where it came from. The answer
#     taken here is that the PARSER throws, at the site that knows which token
#     it was looking at, and const.nix is never asked to evaluate an FCON at
#     all. This case is what holds that answer in place.
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
  # A fragment that is empty, or that appears in the SOURCE nix echoes back in
  # its error trace, would match whatever was printed. must-fail.nix already
  # refuses an empty or near-empty one; this is the other half, and it is why
  # the fragments name a decision, a task or a line rather than an English
  # word.
  [ -n "$expect" ] || {
    echo "reject case '$what' has no expected fragment at all" >&2; exit 1; }
  msg=$(nix eval --impure --expr \
    "(import $poc/must-fail.nix).forceReject $i" 2>&1) && {
    echo "reject case '$what' did not throw at all" >&2; exit 1; }
  # Only the final `error:' line, not nix's whole trace: the trace echoes
  # source lines from must-fail.nix and compile.nix, and a fragment matching
  # one of those would be matching the test rather than the diagnostic.
  final=$(printf '%s\n' "$msg" | grep -E '^ *error: ' | tail -1)
  case "$final" in
    *"$expect"*) ;;
    *) echo "reject case '$what' threw, but its diagnostic does not contain" >&2
       echo "  \"$expect\"" >&2
       echo "  it said: $final" >&2
       exit 1 ;;
  esac
done
echo "$n refusals checked for the diagnostic text each promised"
