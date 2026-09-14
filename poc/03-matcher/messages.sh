#!/usr/bin/env bash
# Check that each reject case throws with the diagnostic it promised.
#
# builtins.tryEval hands back success and value but never the message, so "it
# threw" is all must-fail.nix can check by itself; a matcher whose every
# diagnostic read "error" would pass it. Re-evaluating each reject out here and
# grepping the message is the only way to hold the diagnostics to a contract,
# and "refuse rather than emit wrong code" is half untested without it.
#
# Only the text from the LAST `error:' onwards is compared, not the whole of
# nix's output. Nix prints the source around each frame of the trace, and
# must-fail.nix's own `expect = "..."' lines are in that source: matching
# against everything nix printed made this check pass for any diagnostic at
# all, which a mutation caught. "Onwards" rather than "that line", because a
# thrown message may itself span lines -- a template with a newline in it does.
#
# Its own file rather than a block inside run.sh so that run.sh's mutation
# stage can run it against a mutated copy without re-entering run.sh.
#
#   messages.sh POC_DIR
set -euo pipefail
poc=${1:?usage: messages.sh POC_DIR}

# The floor comes from must-fail.nix rather than being repeated here, so the
# two cannot drift. Forcing `summary' is what applies it: it throws if the
# reject table has shrunk below it.
nix eval --impure --raw --expr "(import $poc/must-fail.nix).summary" >/dev/null
n=$(nix eval --impure --expr "builtins.length (import $poc/must-fail.nix).rejects")
[ "$n" -gt 0 ] || { echo "no reject cases to check messages for" >&2; exit 1; }

for i in $(seq 0 $((n - 1))); do
  meta=$(nix eval --impure --raw --expr \
    "let r = builtins.elemAt (import $poc/must-fail.nix).rejects $i;
     in \"\${r.what}\t\${r.expect}\"")
  what=${meta%%$'\t'*}
  expect=${meta#*$'\t'}
  full=$(nix eval --impure --expr \
    "let r = builtins.elemAt (import $poc/must-fail.nix).rejects $i;
     in builtins.deepSeq r.run 1" 2>&1) && {
    echo "reject case '$what' did not throw at all" >&2; exit 1; }
  msg=$(printf '%s\n' "$full" |
    awk '/^ *error: /{buf = ""} {buf = buf $0 "\n"} END{printf "%s", buf}')
  case "$msg" in
    *"$expect"*) ;;
    *) echo "reject case '$what' threw, but the message does not contain" >&2
       echo "  \"$expect\"" >&2
       echo "the message was: $msg" >&2
       exit 1 ;;
  esac
done
echo "$n reject messages checked for their diagnostic text"
