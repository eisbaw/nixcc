#!/usr/bin/env bash
# The C89 lexer PoC: hand-written token and line-number tables, byte-for-byte
# round-trip over real C89 sources, reject paths and their messages, a
# throughput ladder, and a mutation test of this harness against itself.
#
# The mutation stage is not decoration. An earlier harness in this repo printed
# "48 instructions compared / PASS" while comparing nothing at all, because
# zip() truncates and the count came from the table rather than from the work.
# So every check below is required to prove it can fail, and to fail
# differently from the others.
set -euo pipefail
cd "$(dirname "$0")"
poc=$PWD
work=$(mktemp -d)
keep=1                       # artifacts are kept unless we reach a clean pass
cleanup() {
  if [ "$keep" = 1 ]; then echo "artifacts kept in $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT

: "${LCC_SRC:?LCC_SRC is unset -- run this inside nix develop}"
src=$LCC_SRC/src
[ -d "$src" ] || { echo "no such directory: $src" >&2; exit 1; }

# --- 1. token tables, line numbers, round-trip over every lcc source ----
nix eval --impure --raw --expr \
  "import $poc/check.nix { sources = import $poc/sources.nix $src; }"

# --- 2. reject paths ----------------------------------------------------
nix eval --impure --raw --expr "(import $poc/must-fail.nix).summary"

bash "$poc/messages.sh" "$poc"

# --- 3. the ladder's inputs, and the guard that says whether it may speak -
# Ladder points are whole lcc sources concatenated until the line target is
# reached, never truncated: cutting a file at an arbitrary line can land inside
# a block comment or a string literal, and the lexer would then be measured on
# input it is right to reject.
mkdir "$work/ladder"
mapfile -t units < <(find "$src" -name '*.c' | sort)
[ "${#units[@]}" -ge 10 ] || {
  echo "only ${#units[@]} .c files under $src to build a ladder from" >&2; exit 1; }
ladder=()
for target in 1000 2000 4000 8000 16000; do
  out=$work/ladder/$target.c
  : > "$out"
  i=0
  while [ "$(wc -l < "$out")" -lt "$target" ]; do
    cat "${units[$((i % ${#units[@]}))]}" >> "$out"
    i=$((i + 1))
  done
  ladder+=("$out")
done
# Points 0, 1, 2 and 4: this ladder refuses to judge a span under 8x and the
# four cheapest only span 7.2x, so it is the second-largest point that gets
# dropped to keep these four cases cheap, not the largest.
# The ladder imports its contention guard from poc/lib, a SIBLING of this
# directory, and everything below runs COPIES of this directory elsewhere.
root=$(cd "$poc/.." && pwd)
[ -f "$root/lib/contention.py" ] || {
  echo "no contention guard at $root/lib -- the ladder cannot run" >&2; exit 1; }
# The mutation stage further down runs its copy as $work/mut, so the guard has
# to be $work/lib for that copy to import it.
cp -r "$root/lib" "$work/lib"
guard=$work/guard

# --- the contention guard: it measures, and it refuses in both directions ---
# The ladder below is only worth reading if it refuses to render a verdict
# when the machine was too busy for its numbers to mean anything -- and
# refuses in BOTH directions. The guard it used to have could only downgrade a
# FAIL, so a reading that passed under contention was reported as a clean pass
# with nothing said: the fail-open half of a check whose whole job is to police
# linearity.
#
# First, that the guard MEASURES. selftest.py puts a known number of busy cores
# on this machine and checks they are seen, and that a core burnt by a child of
# ours is not. Nothing else here can see that: the four cases below force the
# guard's DECISION by moving its threshold, so with the measurement stubbed out
# to report an idle machine all four still pass. Which is why the stub is then
# applied, and has to be caught.
python3 "$root/lib/selftest.py"

rm -rf "$guard"; mkdir -p "$guard"; cp -r "$root/lib" "$guard/lib"
sed -i 's|^    return (v\[0\].*|    return 0.0|' "$guard/lib/contention.py"
grep -qx "    return 0.0" "$guard/lib/contention.py" || {
  echo "HARNESS FAULT: busy_cpu_seconds is not where this expects it in" >&2
  echo "contention.py, so the blinding mutation changed nothing" >&2; exit 1; }
if python3 "$guard/lib/selftest.py" > "$work/blinded.log" 2>&1; then
  echo "MUTATION NOT DETECTED: with the contention measurement stubbed out to" >&2
  echo "report a perfectly idle machine, the self-test still passed" >&2
  cat "$work/blinded.log" >&2; exit 1
fi
grep -q "SELF-TEST FAILED" "$work/blinded.log" || {
  echo "the blinded measurement failed, but not as a self-test failure:" >&2
  cat "$work/blinded.log" >&2; exit 1; }
echo "  guard: a blinded contention measurement is caught, not waved through"

# Second, that the guard DECIDES the same way whichever verdict it interrupts.
# Two knobs: the threshold in contention.py says whether the machine counts as
# busy, and the tolerances in throughput.py say whether the reading counts as
# linear. Set wide the tolerances make any reading pass, set tight they make
# any reading fail, so both verdicts are reachable on any machine and none of
# this depends on how busy this one happens to be:
#
#                      contention discounted   contention declared
#   any reading fails  FAIL, exit 1            no verdict, exit 3
#   any reading passes PASS, exit 0            no verdict, exit 3
#
# The left column is the control: without it the right column could be green
# because the ladder had stopped measuring anything at all. The right column is
# one code path reached from two different readings -- once the machine counts
# as busy the tolerances are never consulted -- and that is the claim: WHICH
# verdict was about to be rendered makes no difference to the refusal.
#
# Contention is forced by moving the threshold rather than by loading the
# machine, because what is under test here is the decision; the measurement is
# what selftest.py just covered.
#
# $1 name, $2 threshold (cores), $3 both tolerances, $4 expected exit status,
# $5 and $6 fragments that must appear, $7 one that must not.
guard_case() {
  rm -rf "$guard"; mkdir -p "$guard"
  cp -r "$poc" "$guard/poc"; cp -r "$root/lib" "$guard/lib"
  # The real constants, in the real files, in a copy of the tree -- not a knob
  # added for the test, which could go stale while the checks kept passing.
  sed -i "s|^BUSY_FRACTION = .*|BUSY_FRACTION = $2|;
          s|^BUSY_CEILING = .*|BUSY_CEILING = $2|" "$guard/lib/contention.py"
  sed -i "s|^TOLERANCE = .*|TOLERANCE = $3|;
          s|^END_TO_END_TOLERANCE = .*|END_TO_END_TOLERANCE = $3|;
          s|^AC_SECONDS = .*|AC_SECONDS = 9999.0|" "$guard/poc/throughput.py"
  for knob in "$guard/lib/contention.py:BUSY_FRACTION = $2" \
              "$guard/lib/contention.py:BUSY_CEILING = $2" \
              "$guard/poc/throughput.py:TOLERANCE = $3" \
              "$guard/poc/throughput.py:END_TO_END_TOLERANCE = $3" \
              "$guard/poc/throughput.py:AC_SECONDS = 9999.0"; do
    grep -qx "${knob#*:}" "${knob%%:*}" || {
      echo "HARNESS FAULT: could not set \`${knob#*:}' in ${knob%%:*}." >&2
      echo "The file has changed shape, so this stage is no longer testing" >&2
      echo "the guard it claims to test" >&2; exit 1; }
  done
  local out status=0
  out=$(python3 "$guard/poc/throughput.py" "$guard/poc" "${ladder[0]}" "${ladder[1]}" "${ladder[2]}" "${ladder[4]}" 2>&1) || status=$?
  [ "$status" = "$4" ] || {
    echo "GUARD CASE '$1' exited $status, expected $4:" >&2
    echo "$out" >&2; exit 1; }
  for want in "$5" "$6"; do
    [ -n "$want" ] || continue
    case "$out" in
      *"$want"*) ;;
      *) echo "GUARD CASE '$1' never said \"$want\":" >&2
         echo "$out" >&2; exit 1 ;;
    esac
  done
  case "$out" in
    *"$7"*) echo "GUARD CASE '$1' said \"$7\", which is the one thing it must not:" >&2
            echo "$out" >&2; exit 1 ;;
  esac
  echo "  guard: $1"
}

guard_case "a reading that fails still FAILs when contention is discounted" \
           1000.0 0.01 1 "but cost" "SUPERLINEAR" "NO VERDICT"
guard_case "a reading that fails under contention is no verdict, not a FAIL" \
           -1.0 0.01 3 "NO VERDICT" "unjudged" "but cost"
guard_case "a reading that passes still PASSes when contention is discounted" \
           1000.0 99.0 0 "PASS:" "" "NO VERDICT"
guard_case "a reading that passes under contention is no verdict, not a PASS" \
           -1.0 99.0 3 "NO VERDICT" "unjudged" "PASS:"
echo "the contention guard measures, and refuses a verdict in both directions"


# --- 4. mutation test ---------------------------------------------------
# Each mutation must make the suite fail, must produce its own fragment, and
# must produce NONE of the other fragments. That last condition is what proves
# the checks are distinguishing rather than all collapsing into one alarm.
mut=$work/mut
names=(); fragments=(); outputs=()

# $1 name, $2 fragment that must appear, $3 shell snippet that mutates $mut,
# $4 shell snippet that runs the mutated suite
mutate() {
  rm -rf "$mut"; cp -r "$poc" "$mut"
  ( cd "$mut" && eval "$3" )
  local out status=0
  out=$(cd "$mut" && eval "$4" 2>&1) || status=$?
  if [ "$status" = 0 ]; then
    echo "MUTATION NOT DETECTED: '$1' still passed:" >&2
    echo "$out" >&2
    exit 1
  fi
  names+=("$1"); fragments+=("$2"); outputs+=("$out")
}

lexer_check="nix eval --impure --raw --expr \
  \"import $mut/check.nix { sources = import $mut/sources.nix $src; }\""
must_fail="nix eval --impure --raw --expr '(import $mut/must-fail.nix).summary'"
# The throughput stage is mutated against the four smallest ladder points --
# the minimum it accepts. It is by far the slowest check here, and the guards
# these mutations trip fire on the first point they reach.
bench_check="python3 $mut/throughput.py $mut ${ladder[0]} ${ladder[1]} ${ladder[2]} ${ladder[3]}"

mutate "lexer: wrong punctuator name" \
       "expected \`ID:a' \`LSHIFT:<<'" \
       "sed -i 's|\"<<\" = \"LSHIFT\";|\"<<\" = \"WRONG\";|' lex.nix" \
       "$lexer_check"

mutate "lexer: inter-token trivia dropped" \
       "round-trip produced different bytes" \
       "sed -i 's|ws = slice from p;|ws = \"\";|' lex.nix" \
       "$lexer_check"

mutate "lexer: line numbers never advance" \
       "expected \`1:ID' \`2:ID'" \
       "sed -i 's|then s.line + 1 else s.line;|then s.line else s.line;|' lex.nix" \
       "$lexer_check"

mutate "lexer: numeric constants never validated" \
       "should have been rejected but lexed fine" \
       "sed -i 's|^      numberKind = text: line:|      numberKind = text: line: \"ICON\"; unusedNumberKind = text: line:|' lex.nix" \
       "$must_fail"

mutate "lexer: diagnostics lose their detail" \
       "the message does not contain" \
       "sed -i 's|invalid numeric constant \`\${text}.|lexical error|' lex.nix" \
       "bash $mut/messages.sh $mut"

mutate "harness: expected token lists emptied" \
       "expects only 0 tokens in total" \
       "sed -i 's|{ inherit what src expect; }|{ inherit what src; expect = [ ]; }|' cases.nix" \
       "$lexer_check"

mutate "harness: round-trip corpus arrives empty" \
       "only 0 source files to round-trip" \
       "true" \
       "nix eval --impure --raw --expr 'import $mut/check.nix { sources = [ ]; }'"

mutate "harness: reject table emptied" \
       "must-fail tables shrank to 0 rejects" \
       "sed -i 's|}) rejects;|}) [ ];|' must-fail.nix" \
       "$must_fail"

mutate "harness: the benchmark stops forcing the tokens" \
       "produced only 1 tokens" \
       "sed -i 's|toString (b.length toks)|toString 1|' bench.nix" \
       "$bench_check"

mutate "harness: the benchmark lexes the wrong input" \
       "but the file is" \
       "sed -i 's|b.readFile (/. + path)|\"int x;\"|' bench.nix" \
       "$bench_check"

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
echo "${#names[@]} mutations, each detected with its own distinct failure"

# --- 5. the ladder itself ------------------------------------------------
# Last, and deliberately so. This is the one stage whose outcome depends on
# what else the machine is doing, and on a busy one it renders no verdict and
# exits 3 -- which under `set -e' would take every check after it down with it.
# None of those need a quiet machine, so none of them should be lost to one.
#
# Exit 3 is neither a pass nor a failure, and has to read that way here too or
# the distinction dies at its first caller.
status=0
python3 "$poc/throughput.py" "$poc" "${ladder[@]}" || status=$?
if [ "$status" = 3 ]; then
  echo "NO VERDICT: this machine was too busy for the ladder to measure on." >&2
  echo "Everything above this line ran and passed; nothing about the lexer's" >&2
  echo "linearity was shown either way. Re-run on an idle machine for that." >&2
fi
[ "$status" = 0 ] || exit "$status"

keep=0
