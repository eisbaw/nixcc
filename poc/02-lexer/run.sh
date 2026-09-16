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
# Scratch work happens on a tmpfs inside a bubblewrap sandbox, which the kernel
# reclaims when this process exits: no cleanup, no trap, nothing to delete.
# This re-execs, so it comes before anything else. See poc/lib/sandbox.sh.
# shellcheck source-path=SCRIPTDIR source=../lib/sandbox.sh
. "$(dirname "$(readlink -f "$0")")/../lib/sandbox.sh"
cd "$(dirname "$0")"
poc=$PWD

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
# The ladder imports its contention guard from poc/lib, a SIBLING of this
# directory, and everything below runs COPIES of this directory elsewhere.
root=$(cd "$poc/.." && pwd)
[ -f "$root/lib/contention.py" ] || {
  echo "no contention guard at $root/lib -- the ladder cannot run" >&2; exit 1; }
# The mutation stage further down runs its copy as $work/mut, so the guard has
# to be $work/lib for that copy to import it.
cp -r "$root/lib" "$work/lib"
blinded=$work/blinded

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
# ours is not. Nothing else here can see that: the cases below force the
# guard's DECISION by moving its threshold, so with the measurement stubbed out
# to report an idle machine every one of them still passes. Which is why the
# stub is then applied, and has to be caught.
#
# What happens to each of its three outcomes is poc/lib/selftest.sh's, so that
# the three harnesses that call it cannot each decide differently.
# shellcheck source-path=SCRIPTDIR source=../lib/selftest.sh
. "$root/lib/selftest.sh"
nixcc_selftest "$root/lib" "$work"

mkdir "$blinded"; cp -r "$root/lib" "$blinded/lib"
sed -i 's|^    return (v\[0\].*|    return 0.0|' "$blinded/lib/contention.py"
grep -qx "    return 0.0" "$blinded/lib/contention.py" || {
  echo "HARNESS FAULT: busy_cpu_seconds is not where this expects it in" >&2
  echo "contention.py, so the blinding mutation changed nothing" >&2; exit 1; }
if python3 "$blinded/lib/selftest.py" "$blinded" > "$work/blinded.log" 2>&1; then
  echo "MUTATION NOT DETECTED: with the contention measurement stubbed out to" >&2
  echo "report a perfectly idle machine, the self-test still passed" >&2
  cat "$work/blinded.log" >&2; exit 1
fi
grep -q "SELF-TEST FAILED" "$work/blinded.log" || {
  echo "the blinded measurement failed, but not as a self-test failure:" >&2
  cat "$work/blinded.log" >&2; exit 1; }
echo "  guard: a blinded contention measurement is caught, not waved through"

# And the ESTIMATOR, for the same reason and by the same method. Every
# linearity verdict in this tree is a comparison against contention.py's
# step_ratio(), and nothing in the guard cases below can see it: they move the
# contention threshold, the tolerances and the baseline cliff, and with the
# median swapped for a minimum every one of them still passes either way.
# selftest.py check 0b is what notices, and this is what proves it notices.
# Once rather than in every harness -- poc/lib is shared, and so is the proof.
estimator=$work/estimator
mkdir "$estimator"; cp -r "$root/lib" "$estimator/lib"
sed -i 's|^    return statistics.median(per_round), tuple(per_round)$|    return min(per_round), tuple(per_round)|' \
  "$estimator/lib/contention.py"
grep -qx "    return min(per_round), tuple(per_round)" "$estimator/lib/contention.py" || {
  echo "HARNESS FAULT: step_ratio does not end where this expects it to in" >&2
  echo "contention.py, so the estimator mutation changed nothing" >&2; exit 1; }
if python3 "$estimator/lib/selftest.py" "$estimator" > "$work/estimator.log" 2>&1; then
  echo "MUTATION NOT DETECTED: with the linearity estimator changed from the" >&2
  echo "median of the per-round ratios to their minimum, the self-test passed" >&2
  cat "$work/estimator.log" >&2; exit 1
fi
grep -q "SELF-TEST FAILED" "$work/estimator.log" || {
  echo "the mutated estimator failed, but not as a self-test failure:" >&2
  cat "$work/estimator.log" >&2; exit 1; }
echo "  guard: a linearity estimator that is not the median is caught"

# And the same stub taken ALL THE WAY THROUGH, because the case above does not
# get there. Inside the sandbox a blinded copy fails at check -1, in 0.035 s,
# on the /proc cross-check -- long before check 1 sees it. That is a perfectly
# good catch and it is why the case above is cheap, but it leaves the thing
# selftest.py's header claims about RETAKING unproved: that a stubbed reading
# agrees with itself on every attempt, never counts as drift, and is reported
# as a failure rather than refused. NIXCC_SANDBOX is taken out of the
# environment so check -1 stands aside and check 1 is reached.
#
# MIN_WINDOW is cut to 0.5 s in this copy, and that is sound HERE and nowhere
# else: the reading is stubbed to a constant, so how long it is taken over
# cannot change it. It is what makes three full attempts cost about 6 s instead
# of 25.
blinded_deep=$work/blinded-deep
mkdir "$blinded_deep"; cp -r "$root/lib" "$blinded_deep/lib"
sed -i 's|^    return (v\[0\].*|    return 0.0|;
        s|^MIN_WINDOW = .*|MIN_WINDOW = 0.5|' "$blinded_deep/lib/contention.py"
for knob in "    return 0.0" "MIN_WINDOW = 0.5"; do
  grep -qx "$knob" "$blinded_deep/lib/contention.py" || {
    echo "HARNESS FAULT: could not set \`$knob' in contention.py, so the" >&2
    echo "blinding mutation is no longer what this stage thinks it is" >&2; exit 1; }
done
deep_status=0
env -u NIXCC_SANDBOX python3 "$blinded_deep/lib/selftest.py" "$blinded_deep" \
  > "$work/blinded-deep.log" 2>&1 || deep_status=$?
[ "$deep_status" = 1 ] || {
  echo "a stubbed contention measurement, reaching check 1, exited $deep_status;" >&2
  echo "a reading that disagrees with the machine while agreeing with ITSELF is" >&2
  echo "a broken measurement (exit 1), not an unanswerable question (exit 3):" >&2
  cat "$work/blinded-deep.log" >&2; exit 1; }
for want in "SELF-TEST FAILED" "2 of 2 retakes used" "on 3 of them the baseline"; do
  grep -q "$want" "$work/blinded-deep.log" || {
    echo "the blinded measurement failed, but never said \"$want\", so the" >&2
    echo "retakes it is supposed to have exhausted did not happen:" >&2
    cat "$work/blinded-deep.log" >&2; exit 1; }
done
echo "  guard: a stub agreeing with itself exhausts every retake and still fails"

# And the THIRD outcome, which is the one no stub can reach. Both of
# selftest.py's measuring checks difference a probe against a baseline taken
# seconds away from it, so both can be handed a question with no answer rather
# than one they fail: a background that STEPS between the two baseline readings
# puts half the step onto the probe and nothing tells them apart. That used to
# read as SELF-TEST FAILED -- a red gate for a measurement that was working
# perfectly -- and a gate that goes red for no reason is how people learn to
# discount red. It renders NO VERDICT now, and this is what says so.
#
# The controls are the three blocks above: a stub must still say SELF-TEST
# FAILED, twice over, and an honest run must still pass. Without them this case
# would be satisfied by a selftest.py that refused everything.
#
# TWENTY cores of imaginary background, which is far more than the wild failure
# showed, and the size is the point. Bracketing takes the MIDPOINT of the two
# baselines, so a step of d moves `added' by d/2 and not by d -- the first
# version of this stepped by 6, left `added' 0.6 cores clear of the band edge,
# and review measured it failing 2 runs in 11 on a transient. At 20 the reading
# lands about 6 cores outside the band and no transient this machine produces
# can carry it back in.
#
# Three knobs moved in the copy, all of them real constants in the real files,
# which is the same method the guard cases below use:
#
#   ATTEMPTS to 1   one window rather than three. The retakes exist to absorb a
#                   transient, and a step put there on purpose is not one.
#   the free-cores gate off
#                   it reads the REAL machine and raises a HARNESS FAULT when
#                   fewer than LOAD + 2 cores are free (task-042), so leaving
#                   it in would make this case red on a busy machine for a
#                   reason that has nothing to do with what it tests.
#   idle_window()   +20 cores from its fourth call on. With ATTEMPTS at 1 and
#                   the gate off, check 1's calls are the baseline before the
#                   probe, the probe, and the baseline after it -- so the
#                   fourth call is the trailing baseline. The step reaches
#                   later windows too, but check 1 refuses before check 2 can
#                   run, and the assertion below is what makes sure the step
#                   landed where this says rather than somewhere else.
drift=$work/drift
mkdir "$drift"; cp -r "$root/lib" "$drift/lib"
sed -i 's|^def idle_window():|def idle_window(_n=[0]):\n    _n[0] += 1|;
        s|^    return contention.busiest(|    return (20.0 if _n[0] >= 4 else 0.0) + contention.busiest(|;
        s|^if free < LOAD + 2:|if False:  # the free-cores gate, off in this copy|;
        s|^ATTEMPTS = .*|ATTEMPTS = 1|' "$drift/lib/selftest.py"
for knob in "_n\[0\] >= 4" "^if False:" "^ATTEMPTS = 1$"; do
  grep -q "$knob" "$drift/lib/selftest.py" || {
    echo "HARNESS FAULT: could not set \`$knob' in selftest.py. The file has" >&2
    echo "changed shape, so this stage is no longer stepping the baseline it" >&2
    echo "claims to step" >&2; exit 1; }
done
drift_status=0
python3 "$drift/lib/selftest.py" "$drift" > "$work/drift.log" 2>&1 || drift_status=$?
[ "$drift_status" = 3 ] || {
  echo "with the baseline stepped up by 20 cores between the two readings that" >&2
  echo "bracket the probe, the self-test exited $drift_status; a baseline that" >&2
  echo "moved that far under a 4-core probe is an unanswerable question, which" >&2
  echo "is exit 3:" >&2
  cat "$work/drift.log" >&2; exit 1; }
grep -q "NO VERDICT" "$work/drift.log" || {
  echo "the self-test exited 3 without saying NO VERDICT:" >&2
  cat "$work/drift.log" >&2; exit 1; }
if grep -q "SELF-TEST FAILED" "$work/drift.log"; then
  echo "the self-test rendered NO VERDICT and ALSO called itself broken; those" >&2
  echo "are the two outcomes this whole change exists to tell apart:" >&2
  cat "$work/drift.log" >&2; exit 1
fi
# And that the step landed BETWEEN the two baselines rather than on the probe.
# Without this the case can keep passing for the wrong reason: add or remove an
# idle_window() call above check 1 and the step moves onto the probe window, at
# which point the reading leaves the band through the CEILING instead and the
# three assertions above are all still satisfied. That is this tree's recurring
# failure -- a check reporting its cleanest line once it has stopped testing --
# so the printed spread is read back and required to be most of the step.
apart=$(sed -n 's/.*, \([0-9.]*\) apart).*/\1/p' "$work/drift.log" | head -1)
awk -v a="${apart:-0}" 'BEGIN { exit !(a >= 15) }' || {
  echo "the two baseline readings that bracket the probe came out ${apart:-no} " >&2
  echo "cores apart, and this stage steps one of them by 20. The step is not" >&2
  echo "landing between them any more, so whatever made this exit 3 was not" >&2
  echo "the thing under test:" >&2
  cat "$work/drift.log" >&2; exit 1; }
echo "  guard: a baseline that moves under the probe is NO VERDICT, not a failure"

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
# Arguments are NAME=VALUE in any order, because there are eight of them and
# three are optional; positionally this read as an unlabelled list of numbers
# and quoted fragments that nobody could check against the call site.
#
#   id=       names this case's own copy of the tree
#   desc=     what the case claims, echoed on success
#   busy=     BUSY_FRACTION and BUSY_CEILING, in cores
#   tol=      TOLERANCE and END_TO_END_TOLERANCE
#   cliff=    MIN_BASELINE_RATIO. Every case sets it, and that is load-bearing:
#             see below.
#   status=   the exit status the ladder must give
#   want=     a fragment the output must contain
#   want2=    a second one, optional
#   forbid=   one it must not contain
#
# WHY EVERY CASE PINS THE CLIFF. The ladder has two refusal paths: the one
# below the tolerances, which prints `unjudged' per step, and the cliff at the
# bottom, which refuses before any step is reached because the smallest point's
# CPU did not clear the evaluator's start-up baseline. Which one a run took
# used to depend on how loaded the machine really was -- these cases LIE about
# the threshold, so a genuinely busy machine took the cliff while the case was
# trying to test the other path. Four gate runs were lost to that being
# reported as a harness failure.
#
# The fix is to remove the variable rather than to accept both answers. The
# four contention cases set MIN_BASELINE_RATIO to 0.0, which makes the cliff
# `work < 0' -- unreachable unless a ladder point costs less than an empty
# eval -- so `unjudged' goes back to being required and those cases exercise
# require_quiet every time. The two cliff cases set it to 1e6, which makes
# every point too small on any machine, so the cliff is covered deterministically
# and separately. Accepting either fragment in either place would have let one
# case silently become a duplicate of the other with the suite still green.
guard_case() {
  local id='' desc='' busy='' tol='' cliff='' status='' want='' want2='' forbid='' arg
  for arg in "$@"; do
    case "$arg" in
      id=*) id=${arg#*=} ;;          desc=*) desc=${arg#*=} ;;
      busy=*) busy=${arg#*=} ;;      tol=*) tol=${arg#*=} ;;
      cliff=*) cliff=${arg#*=} ;;    status=*) status=${arg#*=} ;;
      want=*) want=${arg#*=} ;;      want2=*) want2=${arg#*=} ;;
      forbid=*) forbid=${arg#*=} ;;
      *) echo "HARNESS FAULT: guard_case got \`$arg', which is not NAME=VALUE" >&2
         exit 1 ;;
    esac
  done
  for arg in id desc busy tol cliff status want forbid; do
    [ -n "${!arg}" ] || {
      echo "HARNESS FAULT: guard_case was not given $arg=" >&2; exit 1; }
  done

  local guard=$work/guard-$id
  mkdir "$guard"                     # plain mkdir: a reused directory is a fault
  cp -r "$poc" "$guard/poc"; cp -r "$root/lib" "$guard/lib"
  # The real constants, in the real files, in a copy of the tree -- not a knob
  # added for the test, which could go stale while the checks kept passing.
  sed -i "s|^BUSY_FRACTION = .*|BUSY_FRACTION = $busy|;
          s|^BUSY_CEILING = .*|BUSY_CEILING = $busy|" "$guard/lib/contention.py"
  sed -i "s|^TOLERANCE = .*|TOLERANCE = $tol|;
          s|^END_TO_END_TOLERANCE = .*|END_TO_END_TOLERANCE = $tol|;
          s|^MIN_BASELINE_RATIO = .*|MIN_BASELINE_RATIO = $cliff|;
          s|^AC_SECONDS = .*|AC_SECONDS = 9999.0|" "$guard/poc/throughput.py"
  local knob
  for knob in "$guard/lib/contention.py:BUSY_FRACTION = $busy" \
              "$guard/lib/contention.py:BUSY_CEILING = $busy" \
              "$guard/poc/throughput.py:TOLERANCE = $tol" \
              "$guard/poc/throughput.py:END_TO_END_TOLERANCE = $tol" \
              "$guard/poc/throughput.py:MIN_BASELINE_RATIO = $cliff" \
              "$guard/poc/throughput.py:AC_SECONDS = 9999.0"; do
    grep -qx "${knob#*:}" "${knob%%:*}" || {
      echo "HARNESS FAULT: could not set \`${knob#*:}' in ${knob%%:*}." >&2
      echo "The file has changed shape, so this stage is no longer testing" >&2
      echo "the guard it claims to test" >&2; exit 1; }
  done
  # Points 0, 1, 2 and 4. Not the four cheapest: this ladder refuses a span
  # under 8x and the four cheapest only span 7.2x, so a case that dropped the
  # largest point would exit on the span fault and its expected status would
  # stop meaning anything.
  local out rc=0
  out=$(python3 "$guard/poc/throughput.py" "$guard/poc" \
        "${ladder[0]}" "${ladder[1]}" "${ladder[2]}" "${ladder[4]}" 2>&1) || rc=$?
  [ "$rc" = "$status" ] || {
    echo "GUARD CASE '$desc' exited $rc, expected $status:" >&2
    echo "$out" >&2; exit 1; }
  local frag
  for frag in "$want" "$want2"; do
    [ -n "$frag" ] || continue
    case "$out" in
      *"$frag"*) ;;
      *) echo "GUARD CASE '$desc' never said \"$frag\":" >&2
         echo "$out" >&2; exit 1 ;;
    esac
  done
  case "$out" in
    *"$forbid"*) echo "GUARD CASE '$desc' said \"$forbid\", which is the one thing it must not:" >&2
                 echo "$out" >&2; exit 1 ;;
  esac
  echo "  guard: $desc"
}

guard_case id=fail-judged busy=1000.0 tol=0.01 cliff=0.0 status=1 \
  want="but cost" want2="SUPERLINEAR" forbid="NO VERDICT" \
  desc="a reading that fails still FAILs when contention is discounted"
guard_case id=fail-refused busy=-1.0 tol=0.01 cliff=0.0 status=3 \
  want="NO VERDICT" want2="unjudged" forbid="but cost" \
  desc="a reading that fails under contention is no verdict, not a FAIL"
guard_case id=pass-judged busy=1000.0 tol=99.0 cliff=0.0 status=0 \
  want="PASS:" forbid="NO VERDICT" \
  desc="a reading that passes still PASSes when contention is discounted"
guard_case id=pass-refused busy=-1.0 tol=99.0 cliff=0.0 status=3 \
  want="NO VERDICT" want2="unjudged" forbid="PASS:" \
  desc="a reading that passes under contention is no verdict, not a PASS"

# And the cliff itself, forced rather than waited for, because the complaint
# this answers was that its two causes were reported as one. Which cause the
# ladder names has to depend on whether the machine counted as busy, and each
# case forbids the other's fragment, so the two are told apart rather than
# merely both mentioned.
guard_case id=cliff-quiet busy=1000.0 tol=99.0 cliff=1000000.0 status=2 \
  want="too small to measure" want2="wants a bigger smallest point" \
  forbid="NO VERDICT" \
  desc="a ladder point too small to measure on a quiet machine is a harness fault"
guard_case id=cliff-busy busy=-1.0 tol=99.0 cliff=1000000.0 status=3 \
  want="NO VERDICT" want2="cannot be told apart" \
  forbid="wants a bigger smallest point" \
  desc="the same point on a busy machine says it cannot tell the two apart"
echo "the contention guard measures, refuses a verdict in both directions, and"
echo "names which of the two things it refused for"


# --- 4. mutation test ---------------------------------------------------
# Each mutation must make the suite fail, must produce its own fragment, and
# must produce NONE of the other fragments. That last condition is what proves
# the checks are distinguishing rather than all collapsing into one alarm.
mut=$work/mut
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

# The two flags a preprocessor reads and nothing else here looks at. Both
# mutants round-trip perfectly and produce exactly the right tokens on exactly
# the right lines; the line-start table is the only thing in this directory
# that can see them at all.
mutate "lexer: a newline in ordinary whitespace stops ending a logical line" \
       "a trailing newline ends the last line, so EOI starts one: expected" \
       "sed -i 's@          s // { inherit line; solid = true; nlAt = s.nlAt || nl; }@          s // { inherit line; solid = true; }@' lex.nix" \
       "$lexer_check"

mutate "lexer: a continuation that glues two tokens is not flagged" \
       "a continuation and nothing else glues two tokens together: expected" \
       "sed -i 's@          glue = tv.spliced \&\& !tv.solid;@          glue = false;@' lex.nix" \
       "$lexer_check"

# The splice that changes where a block comment ENDS, which is the one of the
# three phase-2 cases that hides best: the comment sets `solid', so nothing
# downstream can see it, and the symptom is a swallowed expression rather
# than a lexical error.
mutate "lexer: a continuation before a comment terminator is not refused" \
       "a backslash-newline before a comment terminator" \
       "sed -i 's@ch (i + 2) == \"/\" then@false then@' lex.nix" \
       "$must_fail"

# Named by CASE rather than by the sentence must-fail prints: another
# mutation makes a different reject lex fine, and the two cannot be told
# apart by a fragment they both produce.
mutate "lexer: numeric constants never validated" \
       "hexadecimal prefix with no digits" \
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

# The one mutation here that changes the INVOCATION rather than the tree, so
# it says so: check.nix is handed an empty corpus rather than being edited.
mutate "harness: round-trip corpus arrives empty" \
       "only 0 source files to round-trip" \
       "true" \
       "nix eval --impure --raw --expr 'import $mut/check.nix { sources = [ ]; }'" \
       no

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
# The count this harness declares, checked for equality; poc/lib/mutant.sh
# says why it is equality and not a floor.
declared=13
[ "${#names[@]}" -eq "$declared" ] || {
  echo "${#names[@]} mutations recorded, against the $declared this harness" >&2
  echo "declares. Either a mutate call has gone missing, or one was added" >&2
  echo "and the declared count was not raised with it." >&2; exit 1; }
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
nixcc_selftest_verdict "$status"
[ "$nixcc_verdict" = 0 ] || exit "$nixcc_verdict"

