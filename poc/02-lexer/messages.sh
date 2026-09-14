#!/usr/bin/env bash
# Check that each reject case throws with the diagnostic it promised.
#
# builtins.tryEval hands back success and value but never the message, so "it
# threw" is all must-fail.nix can check by itself; a lexer whose every
# diagnostic read "error" would pass it. Re-evaluating each reject out here and
# grepping the message is the only way to hold the diagnostics to a contract,
# and "fail fast and verbosely" is half untested without it.
#
# Its own file rather than a block inside run.sh so that run.sh's mutation
# stage can run it against a mutated copy without re-entering run.sh.
#
#   messages.sh POC_DIR
set -euo pipefail
poc=${1:?usage: messages.sh POC_DIR}

n=$(nix eval --impure --expr "builtins.length (import $poc/must-fail.nix).rejects")
[ "$n" -ge 16 ] || { echo "only $n reject cases to check messages for" >&2; exit 1; }

for i in $(seq 0 $((n - 1))); do
  meta=$(nix eval --impure --raw --expr \
    "let r = builtins.elemAt (import $poc/must-fail.nix).rejects $i;
     in \"\${r.what}\t\${r.expect}\"")
  what=${meta%%$'\t'*}
  expect=${meta#*$'\t'}
  msg=$(nix eval --impure --expr \
    "let m = import $poc/must-fail.nix; l = import $poc/lex.nix;
     in builtins.deepSeq (l.lex (builtins.elemAt m.rejects $i).src) 1" 2>&1) && {
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
