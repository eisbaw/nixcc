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
#   * `on line 4'. task-011 left this slice an open question: evalFCON THROWS,
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
n=$(nix eval --impure --expr "builtins.length (import $poc/must-fail.nix).rejects")
declared=$(nix eval --impure --expr "(import $poc/must-fail.nix).declaredRejects")
[ "$n" = "$declared" ] || {
  echo "must-fail.nix holds $n reject cases against the $declared it declares" >&2; exit 1; }

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
