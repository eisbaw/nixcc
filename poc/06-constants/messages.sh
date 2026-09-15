#!/usr/bin/env bash
# Check that each reject case throws with the diagnostic it promised.
#
# builtins.tryEval hands back success and value but never the message, so "it
# threw" is all must-fail.nix can check by itself; an evaluator whose every
# diagnostic read "error" would pass it. Re-evaluating each reject out here and
# grepping the message is the only way to hold the diagnostics to a contract,
# and "fail fast and verbosely" is half untested without it.
#
# Two of these fragments are load-bearing beyond their own case. The float
# rejection has to name decision-006 and task-015, because a reader who meets
# it needs to know that float is a deferred CHOICE with a task behind it
# rather than a gap someone forgot -- see decision-006, which says in so many
# words that a frontend quietly accepting `double' is worse than one refusing
# it.
#
# Its own file rather than a block inside run.sh so that run.sh's mutation
# stage can run it against a mutated copy without re-entering run.sh.
#
#   messages.sh POC_DIR
set -euo pipefail
poc=${1:?usage: messages.sh POC_DIR}

n=$(nix eval --impure --expr "builtins.length (import $poc/must-fail.nix).rejects")
[ "$n" -ge 12 ] || { echo "only $n reject cases to check messages for" >&2; exit 1; }

for i in $(seq 0 $((n - 1))); do
  meta=$(nix eval --impure --raw --expr \
    "let r = builtins.elemAt (import $poc/must-fail.nix).rejects $i;
     in \"\${r.what}\t\${r.expect}\"")
  what=${meta%%$'\t'*}
  expect=${meta#*$'\t'}
  msg=$(nix eval --impure --expr \
    "(import $poc/must-fail.nix).forceReject $i" 2>&1) && {
    echo "reject case '$what' did not throw at all" >&2; exit 1; }
  case "$msg" in
    *"$expect"*) ;;
    *) echo "reject case '$what' threw, but the message does not contain" >&2
       echo "  \"$expect\"" >&2
       echo "$msg" >&2
       exit 1 ;;
  esac
done
echo "$n reject messages checked for their diagnostic text"
