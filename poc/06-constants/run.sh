#!/usr/bin/env bash
# The C89 constant-evaluator PoC: hand-written value tables, reject paths and
# their messages, a form-by-form differential against lcc's own frontend, the
# three loops run at a size where a Nix traversal's failure modes show, and a
# mutation test of this harness against itself.
#
# The mutation stage is not decoration. An earlier harness in this repo printed
# "48 instructions compared / PASS" while comparing nothing at all, because
# zip() truncates and the count came from the table rather than from the work.
# So every check below is required to prove it can fail, and to fail
# differently from the others.
#
# NO TIMING LADDER HERE, and that is a decision rather than an omission. The
# other harnesses measure linearity because their cost is driven by input
# size in a way that could silently go quadratic; this one evaluates a single
# lexeme at a time, and stress.nix asks the only question worth asking of it
# -- whether its loops survive at a size where the evaluator's failure modes
# appear -- with a yes-or-no answer that needs no quiet machine. So there is
# no contention self-test and no NO VERDICT path in this file.
set -euo pipefail
# Scratch work happens on a tmpfs inside a bubblewrap sandbox, which the kernel
# reclaims when this process exits: no cleanup, no trap, nothing to delete.
# This re-execs, so it comes before anything else. See poc/lib/sandbox.sh.
# shellcheck source-path=SCRIPTDIR source=../lib/sandbox.sh
. "$(dirname "$(readlink -f "$0")")/../lib/sandbox.sh"
cd "$(dirname "$0")"
poc=$PWD
root=$(cd "$poc/.." && pwd)

command -v rcc-rv32 >/dev/null 2>&1 || {
  echo "no \`rcc-rv32' on PATH. The differential below needs lcc's own" >&2
  echo "frontend, which the flake builds. Run this inside \`nix develop'." >&2
  exit 2; }

# --- 1. hand-written value tables ---------------------------------------
nix eval --impure --raw --expr "import $poc/check.nix"

# --- 2. reject paths ----------------------------------------------------
nix eval --impure --raw --expr "(import $poc/must-fail.nix).summary"

bash "$poc/messages.sh" "$poc"

# --- 3. the loops at a size where they would break -----------------------
nix eval --impure --raw --expr "import $poc/stress.nix"

# --- 4. the differential against lcc -------------------------------------
# Criterion #6 of task-011: behaviour DIFFED against rcc rather than
# asserted. Its own script, so that a mutation can reach it.
python3 "$poc/oracle.py" "$poc"

# --- 5. mutation test ---------------------------------------------------
# Each mutation must make the suite fail, must produce its own fragment, and
# must produce NONE of the other fragments. That last condition is what proves
# the checks are distinguishing rather than all collapsing into one alarm.
#
# The mutated copy needs poc/02-lexer beside it, because const.nix reaches
# ../02-lexer/lex.nix by relative path for `explode'. It is symlinked rather
# than copied: it is not what is being mutated, and a copy of it is a copy
# that could go stale.
mut=$work/poc/06-constants
mkdir -p "$work/poc"
ln -s "$root/02-lexer" "$work/poc/02-lexer"

names=(); fragments=(); outputs=()

# $1 name, $2 fragment that must appear, $3 shell snippet that mutates $mut,
# $4 shell snippet that runs the mutated suite
# $5 optional: "no" if $3 changes the INVOCATION rather than the tree, so that
# the "this mutation edited nothing" check knows not to expect an edit
mutate() {
  # A tmpfs of its own for every mutation, so no state can survive from the
  # last one -- by construction, rather than by a remove that has to have
  # worked. poc/lib/mutant.sh does the copy, the apply and the run inside it,
  # and hands back the mutated suite's own exit status.
  local out status=0
  out=$(bwrap --dev-bind / / --tmpfs "$mut" --die-with-parent -- \
        bash "$root/lib/mutant.sh" "$poc" "$mut" "$3" "$4" "${5:-yes}" 2>&1) || status=$?
  case "$status" in
    120) echo "HARNESS FAULT: could not copy $poc for mutation '$1'" >&2; exit 1 ;;
    121) echo "HARNESS FAULT: mutation '$1' did not apply cleanly:" >&2
         echo "$out" >&2; exit 1 ;;
    122) echo "HARNESS FAULT: mutation '$1' changed nothing -- its pattern no longer matches" >&2
         exit 1 ;;
    123) echo "HARNESS FAULT: mutation '$1' declared \"${5:-yes}\" for whether it edits the tree" >&2
         exit 1 ;;
  esac
  if [ "$status" = 0 ]; then
    echo "MUTATION NOT DETECTED: '$1' still passed:" >&2
    echo "$out" >&2
    exit 1
  fi
  names+=("$1"); fragments+=("$2"); outputs+=("$out")
}

table_check="nix eval --impure --raw --expr 'import $mut/check.nix'"
must_fail="nix eval --impure --raw --expr '(import $mut/must-fail.nix).summary'"
stress_check="nix eval --impure --raw --expr 'import $mut/stress.nix'"
oracle_check="python3 $mut/oracle.py $mut"

# --- mutations of the evaluator ---
mutate "evaluator: the long suffix stops choosing long" \
       "\`7l' should be long 7" \
       "sed -i 's|else if suffix == \"l\" then|else if false then|' const.nix" \
       "$table_check"

# NOT "wraps": `accumulate' freezes its value at the last pre-overflow
# partial, so the mutant reports 429496729 for 4294967296. The defect is that
# the clamp is gone, which is what the name has to say.
mutate "evaluator: an overflowing constant keeps its partial instead of clamping" \
       "\`4294967296' should be unsigned long 4294967295" \
       "sed -i 's|value = if blown then limit else n;|value = n;|' const.nix" \
       "$table_check"

mutate "evaluator: an overflowing constant is clamped without saying so" \
       "we warn [], lcc warns [\"overflow in constant" \
       "sed -i 's|warnings = if blown then|warnings = if false then|' const.nix" \
       "$oracle_check"

mutate "evaluator: a character constant is not sign extended" \
       "lcc says signed -1" \
       "sed -i 's|else if first >= CHAR_SIGN_BIT then first - CHAR_MODULUS|else if false then first - CHAR_MODULUS|' const.nix" \
       "$oracle_check"

# The fragment names the CASE rather than the generic `why' prefix, which any
# failing narrow-string case would produce.
mutate "evaluator: a string constant drops its embedded NUL" \
       "an embedded NUL, which no Nix string could hold: " \
       "sed -i 's|      units = r.values;|      units = b.filter (v: v != 0) r.values;|' const.nix" \
       "$table_check"

# The fragments below name a CASE, not a position in the list: the message is
# "these should have been rejected but evaluated fine: <comma list>", and an
# "evaluated fine: X" fragment silently depended on X being first. Inserting a
# reject would have turned that into a gate failure with no defect behind it.
mutate "evaluator: float is quietly accepted instead of refused" \
       "a floating constant names the rejection task too" \
       "sed -i 's|^  evalFCON = lexeme: throw|  evalFCON = _: { value = 0; type = \"double\"; warnings = [ ]; }; unusedFCON = lexeme: throw|' const.nix" \
       "$must_fail"

mutate "evaluator: a byte outside ASCII evaluates to an invented value" \
       "a byte outside ASCII in a character constant" \
       "sed -i 's|or nonAsciiByte;|or 0;|' const.nix" \
       "$must_fail"

mutate "evaluator: the float refusal stops naming the decision behind it" \
       "the message does not contain" \
       "sed -i 's|decision-006|a later wave|' const.nix" \
       "bash $mut/messages.sh $mut"

mutate "evaluator: a long literal is decoded only as far as its first unit" \
       "decoded to 1 units" \
       "sed -i 's|          startSet = \[ (unitAt 0) \];|          startSet = [ (unitAt 0 // { next = n; }) ];|' const.nix" \
       "$stress_check"

# --- mutations of the harness ---
mutate "harness: the scalar expectations are emptied" \
       "0 scalar cases, against the" \
       "sed -i 's|^  scalars = \[|  scalars = [ ]; unusedScalars = [|' cases.nix" \
       "$table_check"

mutate "harness: the lexed expectations are emptied" \
       "expects 0 constants in total" \
       "sed -i 's|      expect = \[|      expect = [ ]; unusedExpect = [|' cases.nix" \
       "$table_check"

mutate "harness: the reject table is emptied" \
       "tables hold 0 rejects" \
       "sed -i 's|^  rejects = \[|  rejects = [ ]; unusedRejects = [|' must-fail.nix" \
       "$must_fail"

mutate "harness: the oracle's form table is emptied" \
       "the oracle table holds 0 scalar" \
       "sed -i 's|^  scalars = \[|  scalars = [ ]; unusedScalars = [|' oracle.nix" \
       "$oracle_check"

# With the stderr parser silenced, every form reads as "lcc warned nothing".
# The per-form comparison would catch that for the 21 forms we warn about; the
# declared-diagnostics control catches it first and for the right reason, and
# this is what proves that control is load-bearing.
mutate "harness: the oracle stops reading lcc's diagnostics at all" \
       "diagnostics were parsed out of the" \
       "sed -i 's|        diagnostics\[index\].append(m.group(2))|        pass|' oracle.py" \
       "$oracle_check"

# The one that matters most: with lcc replaced by `cat', the oracle's input
# comes back as its own output and no constant node is in it. A differential
# that would still pass with the reference removed is not a differential.
mutate "harness: the oracle stops consulting lcc at all" \
       "this form was never compared" \
       "sed -i 's|^ORACLE = \"rcc-rv32\"|ORACLE = \"cat\"|' oracle.py" \
       "$oracle_check"

mutate "harness: the stress sizes are cut below where anything breaks" \
       "stress sizes were shrunk" \
       "sed -i 's|^  repeats = 20000;|  repeats = 10;|' stress.nix" \
       "$stress_check"

# --- the checks review found nothing was aimed at ---
# THE ONE CRITERION #2 RESTS ON. Take the pre-multiply guard out of
# `accumulate' and a 5000-digit constant is no longer clamped at the target
# ceiling -- the accumulation runs on until Nix itself raises "integer
# overflow", which is the failure this whole design exists to avoid and the
# one no other mutation reaches. stress.nix is the only stage large enough to
# get there.
mutate "evaluator: the overflow guard is removed, so Nix throws instead" \
       "integer overflow" \
       "sed -i 's|else if acc.value > (ULONG_MAX - d) / base then acc // { overflow = true; }|else if false then acc|' const.nix" \
       "$stress_check"

# The CONTROL half of must-fail.nix carries its headline claim -- that an
# evaluator refusing everything could not pass it either -- and nothing
# proved that branch ran.
mutate "evaluator: every integer constant is refused, controls included" \
       "should have evaluated but threw" \
       "sed -i 's|^  evalICON = lexeme: if isCharLexeme|  evalICON = _: throw \"refused\"; unusedICON = lexeme: if isCharLexeme|' const.nix" \
       "$must_fail"

# The oracle's STRING comparison. The `cat' mutation proves the never-compared
# path; this proves a wrong decoded literal is caught rather than waved past.
mutate "harness: the oracle stops comparing decoded string units" \
       "lcc says width 1" \
       "sed -i 's|      units = r.values;|      units = b.filter (v: v != 0) r.values;|' const.nix" \
       "$oracle_check"

# And that the per-function constant-node assertion is evaluated at all. It is
# what stops the oracle reading the relational's own CNSTI4 1 as the form's
# value -- which is the right answer by accident for the forms `1' and
# `'\\1'', and was a live fail-open before review found it.
mutate "harness: the per-function constant-node count stops matching" \
       "constant nodes, not 4" \
       "sed -i 's|^CNSTS_PER_SCALAR = 3|CNSTS_PER_SCALAR = 4|' oracle.py" \
       "$oracle_check"

for i in "${!names[@]}"; do
  case "${outputs[$i]}" in
    *"${fragments[$i]}"*) ;;
    *) echo "MUTATION '${names[$i]}' failed, but not with \"${fragments[$i]}\":" >&2
       echo "${outputs[$i]}" >&2; exit 1 ;;
  esac
  for j in "${!names[@]}"; do
    [ "$i" = "$j" ] && continue
    case "${outputs[$i]}" in
      *"${fragments[$j]}"*)
        echo "MUTATION '${names[$i]}' also reported \"${fragments[$j]}\"," >&2
        echo "which belongs to '${names[$j]}' -- the checks are not distinguishing" >&2
        exit 1 ;;
    esac
  done
  echo "  mutation detected: ${names[$i]}"
done
# The count this harness declares, checked for equality; poc/lib/mutant.sh
# says why it is equality and not a floor.
declared=20
[ "${#names[@]}" -eq "$declared" ] || {
  echo "${#names[@]} mutations recorded, against the $declared this harness" >&2
  echo "declares. Either a mutate call has gone missing, or one was added" >&2
  echo "and the declared count was not raised with it." >&2; exit 1; }
echo "${#names[@]} mutations, each detected with its own distinct failure"
