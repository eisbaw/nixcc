#!/usr/bin/env bash
# The lburg-style tree matcher PoC: rules as data, bottom-up labelling with
# costs, reduction to RV32 assembly -- and then four independent ways of not
# believing it.
#
#   1. The DAGs are regenerated from their .c with lcc itself and diffed
#      against what is checked in, so "these are real lcc DAGs, not ones
#      invented to suit the rules" is re-proved on every run.
#   2. check.nix asserts which rule wins where and at what cost, and flips four
#      of those choices by changing a cost.
#   3. The emitted assembly is fed to riscv32-none-elf-as, linked, and RUN in
#      the Nix RV32I emulator; separately the same .c is compiled by the host
#      compiler and run. Both answers have to agree with each other AND with a
#      number written down in cases.nix.
#   4. Each of those is mutation-tested, including the harness itself.
#
# Stage 3 is not decoration and not redundant with stage 2. Stage 2 is a
# contract on the emitted TEXT: which rule won, at what cost, which lines came
# out and how many. A rule template can be changed to compute the wrong thing
# while satisfying every one of those -- `mv a1,%0' instead of `mv a1,%1' in
# the divide libcall divides x by itself, and stage 2 reports a clean pass.
# Stage 3 is the only semantic oracle here, which is why `checks.matcher' in
# the flake, being stage 2 only, is a weaker gate than `just poc-matcher'.
set -euo pipefail
# Scratch work happens on a tmpfs inside a bubblewrap sandbox, which the kernel
# reclaims when this process exits: no cleanup, no trap, nothing to delete.
# This re-execs, so it comes before anything else. See poc/lib/sandbox.sh.
# shellcheck source-path=SCRIPTDIR source=../lib/sandbox.sh
. "$(dirname "$(readlink -f "$0")")/../lib/sandbox.sh"
cd "$(dirname "$0")"
poc=$PWD

: "${LCC_SRC:?LCC_SRC is unset -- run this inside nix develop}"
: "${NIX_RISCV:?NIX_RISCV is unset -- run this inside nix develop}"
command -v rcc-rv32 >/dev/null || { echo "no rcc-rv32 on PATH" >&2; exit 1; }

cases=$(nix eval --impure --raw --expr \
  'builtins.concatStringsSep " " (map (c: c.name) (import '"$poc"'/cases.nix).functions)')
[ -n "$cases" ] || { echo "cases.nix lists no functions" >&2; exit 1; }

# --- 1. the DAGs are lcc's, not ours ------------------------------------
# Always through rcc-rv32, never raw `rcc -target=symbolic`: the raw oracle
# declares little_endian=0 (decision-004).
regenerated=0
for name in $cases argmul; do
  [ -f "ir/$name.c" ] || { echo "no ir/$name.c for case '$name'" >&2; exit 1; }
  rcc-rv32 < "ir/$name.c" > "$work/$name.sym"
  if ! diff -u "ir/$name.sym" "$work/$name.sym"; then
    echo "ir/$name.sym is not what lcc produces for ir/$name.c any more." >&2
    echo "Regenerate it and re-check the node numbers cases.nix refers to." >&2
    exit 1
  fi
  regenerated=$((regenerated + 1))
done
[ "$regenerated" -ge 4 ] || {
  echo "only $regenerated DAGs regenerated from lcc; the case list looks empty" >&2; exit 1; }
echo "$regenerated DAGs regenerated with rcc-rv32 and identical to what is checked in"

# --- 2. labelling, costs and the emitted text ---------------------------
# shellcheck disable=SC2016  # ${c.name} is Nix's interpolation, not bash's
sources=$(nix eval --impure --raw --expr \
  'builtins.concatStringsSep "; " (map (c: "${c.name} = '"$poc"'/ir/${c.name}.sym")
     (import '"$poc"'/cases.nix).functions)')
check_expr="import $poc/check.nix { sources = { $sources; }; }"
nix eval --impure --raw --expr "$check_expr"

nix eval --impure --raw --expr "(import $poc/must-fail.nix).summary"
bash "$poc/messages.sh" "$poc"

# --- 3. assemble, link, run, and compare against the host compiler ------
# `expect` is in cases.nix as well, so that two compilers agreeing on a wrong
# answer is still a failure.
# Assembling, linking and running one case is poc/03-matcher/build-and-run.sh,
# not a function here. Its header says why; the short version is that a
# function defined in run.sh is out of scope inside the mount namespace each
# mutation runs in, so as a function it was the last piece of the semantic
# path living in a file a mutation could reach and did not (task-041). Said
# that carefully: plenty of THIS file is still out of a mutation's reach --
# stage 1's DAG diff, the host-compiler cross-check, mutate()'s own
# distinctness loop -- because no mutation anywhere in poc/ edits a run.sh.

for name in $cases; do
  result=$(bash "$poc/build-and-run.sh" "$poc" "$name" "$work/exec/$name")
  read -r reason exitcode steps insns <<<"$(python3 -c '
import json, sys
r = json.loads(sys.argv[1])
print(r["reason"], r["exitCode"], r["steps"], r["insns"])' "$result")"
  [ "$reason" = exit ] || {
    echo "$name: the emulator stopped with reason '$reason', not a clean exit" >&2; exit 1; }

  # The host compiler, on the same .c, as an independent oracle.
  gcc -std=gnu89 -w -o "$work/host-$name" "$poc/drivers/$name.c" "$poc/ir/$name.c"
  host=$("$work/host-$name")
  want=$(nix eval --impure --raw --expr \
    "let c = builtins.head (builtins.filter (e: e.file == \"$name\")
       (import $poc/cases.nix).execution); in toString c.expect")

  python3 - "$name" "$exitcode" "$host" "$want" <<'PY'
import sys
name, got, host, want = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
if got != host & 0xffffffff:
    sys.exit(f"{name}: our RV32 code returned {got}, the host compiler's {host}")
if host != want:
    sys.exit(f"{name}: the host compiler returned {host}, but cases.nix expects {want} "
             f"-- the C, the driver and the expectation disagree")
PY
  echo "  $name: $insns instructions, $steps emulated, returned $exitcode (host agrees)"
done
echo "$(echo "$cases" | wc -w) cases assembled, linked, executed in the Nix RV32I emulator"

# --- 4. the ladder's inputs, and the guard that says whether it may speak --
# Ladder points are whole lcc test files concatenated, never truncated: the
# listing format numbers nodes per forest, so cutting one in half would leave
# dangling back-references and measure the parser's error path.
mkdir "$work/sym" "$work/ladder"
nodes_in() { grep -cE "^ ?[0-9]+[.'] " "$1" || true; }
sized=()
for f in "$LCC_SRC"/tst/*.c; do
  bn=$(basename "$f" .c)
  case "$bn" in front|paranoia|yacc) continue ;; esac
  gcc -E -P -std=gnu89 -nostdinc -I"$LCC_SRC/include/x86/linux" "$f" > "$work/sym/$bn.i" 2>/dev/null || continue
  rcc-rv32 < "$work/sym/$bn.i" > "$work/sym/$bn.sym" 2>/dev/null || continue
  n=$(nodes_in "$work/sym/$bn.sym")
  # One lcc test file (cq.c) is 21134 nodes, five times the whole rest of the
  # corpus put together. Left in, it overshoots every ladder target below it
  # and collapses the span to nothing, so units are capped and cycled instead.
  [ "$n" -le 1000 ] || continue
  sized+=("$(printf '%08d %s' "$n" "$work/sym/$bn.sym")")
done
[ "${#sized[@]}" -ge 10 ] || {
  echo "only ${#sized[@]} lcc test files became usable ladder units" >&2; exit 1; }
mapfile -t units < <(printf '%s\n' "${sized[@]}" | sort | cut -d' ' -f2)

ladder=()
for target in 5000 10000 20000 40000; do
  out=$work/ladder/$target.sym
  : > "$out"
  i=0
  while [ "$(nodes_in "$out")" -lt "$target" ]; do
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
# to report an idle machine every one of them still passes. Which is why the stub is then
# applied, and has to be caught.
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

# Second, that the guard DECIDES the same way whichever verdict it interrupts.
# Two knobs: the threshold in contention.py says whether the machine counts as
# busy, and the tolerances in scale.py say whether the reading counts as
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
# Arguments are NAME=VALUE in any order. The same function, the same reasoning
# and the same argument names as in poc/02-lexer/run.sh, which carries the long
# version of WHY EVERY CASE PINS THE CLIFF -- in short, these cases lie about
# the contention threshold, so the cliff at the bottom of the ladder has to be
# put beyond reach (cliff=0.0) or driven deliberately (cliff=1000000.0), never
# left to whatever the machine happens to be doing.
#
#   id= desc= busy= tol= cliff= status= want= [want2=] forbid=
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
          s|^MIN_BASELINE_RATIO = .*|MIN_BASELINE_RATIO = $cliff|" "$guard/poc/scale.py"
  local knob
  for knob in "$guard/lib/contention.py:BUSY_FRACTION = $busy" \
              "$guard/lib/contention.py:BUSY_CEILING = $busy" \
              "$guard/poc/scale.py:TOLERANCE = $tol" \
              "$guard/poc/scale.py:END_TO_END_TOLERANCE = $tol" \
              "$guard/poc/scale.py:MIN_BASELINE_RATIO = $cliff"; do
    grep -qx "${knob#*:}" "${knob%%:*}" || {
      echo "HARNESS FAULT: could not set \`${knob#*:}' in ${knob%%:*}." >&2
      echo "The file has changed shape, so this stage is no longer testing" >&2
      echo "the guard it claims to test" >&2; exit 1; }
  done
  local out rc=0
  out=$(python3 "$guard/poc/scale.py" "$guard/poc" "${ladder[@]}" 2>&1) || rc=$?
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

# And the cliff at the bottom of the ladder, driven rather than waited for. The
# cause it names has to depend on whether the machine counted as busy, and each
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


# --- 5. mutation test ------------------------------------------------------
# Each mutation must make the suite fail, must produce its own fragment, and
# must produce NONE of the other fragments. That last condition is what proves
# the checks distinguish rather than all collapsing into one alarm. The
# harness is mutated too: a check that cannot fail is not a check.
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
    # A run snippet that checks a CONTROL before making its claim says so with
    # 9, and is named here for the reason poc/lib/mutant.sh names 120-123: a
    # non-zero status from a mutated suite means "detected" everywhere else, so
    # a snippet whose control has gone would be recorded as the strongest
    # result this harness has for its weakest reason. It did go red without
    # this arm -- the CONTROL LOST text does not contain any mutation's
    # fragment, so the distinctness loop caught it -- but the headline then
    # read "the checks are not distinguishing", which is not what happened, and
    # it stayed true only as long as nobody put the fragment into that message.
    9)   echo "CONTROL LOST for mutation '$1'. It checks a property before it" >&2
         echo "claims anything, and that property no longer holds, so the claim" >&2
         echo "was never made:" >&2
         echo "$out" >&2; exit 1 ;;
  esac
  if [ "$status" = 0 ]; then
    echo "MUTATION NOT DETECTED: '$1' still passed:" >&2
    echo "$out" >&2
    exit 1
  fi
  names+=("$1"); fragments+=("$2"); outputs+=("$out")
}

# The same source list stage 2 uses, so a case added to cases.nix is mutated
# as well as checked.
# The \" survive `eval' below and reach nix as ordinary quotes.
mut_list=$(for c in $cases; do printf '{ name = \\"%s\\"; value = %s/ir/%s.sym; } ' "$c" "$mut" "$c"; done)
matcher_check="nix eval --impure --raw --expr \"import $mut/check.nix { sources = builtins.listToAttrs [ $mut_list ]; }\""
must_fail="nix eval --impure --raw --expr '(import $mut/must-fail.nix).summary'"
# The scale stage is mutated against the four smallest ladder points, the
# minimum it accepts; the guards these mutations trip fire on the first point.
scale_check="python3 $mut/scale.py $mut ${ladder[0]} ${ladder[1]} ${ladder[2]} ${ladder[3]}"

mutate "matcher: the cheapest rule is not the one kept" \
       "expected reg_subi@3, got reg_subi@4" \
       "sed -i 's@ || c.cost < m.\${c.nt}.cost@@' burg.nix" \
       "$matcher_check"

mutate "matcher: a kid's cost does not count towards its parent's" \
       "expected reg_muli_libcall@12, got reg_muli_libcall@10" \
       "sed -i 's|cost = r.cost + b.foldl. (a: c: a + c) 0 costs;|cost = r.cost;|' burg.nix" \
       "$matcher_check"

mutate "matcher: an addressing mode is priced out of ever being folded in" \
       "expected addr_addp@1, got addr_from_reg@2" \
       "sed -i '/addr_addp/ s|cost = 0|cost = 9|' rules.nix" \
       "$matcher_check"

mutate "matcher: a common subexpression is recomputed at every use" \
       "is missing \`lw s11,-56(s0)', \`add s2,s2,s11', \`ble s10,s2,.Lf_2'" \
       "sed -i 's@(node.count > 1 || mustHold)@mustHold@' burg.nix" \
       "$matcher_check"

mutate "matcher: MULI4 becomes a hardware multiply RV32I has not got" \
       "which RV32I has not got" \
       "sed -i 's|tmpl = \"mv a0,%0\\\\nmv a1,%1\\\\ncall __mulsi3\\\\nmv %c,a0\\\\n\";|tmpl = \"mul %c,%0,%1\\\\n\";|' rules.nix" \
       "$matcher_check"

# shellcheck disable=SC2016  # the ${...} below are Nix source being edited, not bash
mutate "matcher: the prologue stops saving one of the registers the body uses" \
       "that its prologue never saves" \
       'sed -i "s@tsw \${r},\${toString (slotOf r)}(sp)\") saved@tsw \${r},\${toString (slotOf r)}(sp)\") (b.tail saved)@" emit.nix' \
       "$matcher_check"

# shellcheck disable=SC2016  # as above
mutate "matcher: the epilogue stops restoring one of the registers the prologue saved" \
       "never restores them in its epilogue" \
       'sed -i "s@tlw \${r},\${toString (slotOf r)}(sp)\") saved@tlw \${r},\${toString (slotOf r)}(sp)\") (b.tail saved)@" emit.nix' \
       "$matcher_check"

mutate "matcher: the emitter produces each statement twice" \
       "instructions where 41 are expected" \
       "sed -i 's|body = b.concatLists (map (s: s.code) selected);|body = b.concatLists (map (s: s.code ++ s.code) selected);|' emit.nix" \
       "$matcher_check"

mutate "matcher: every argument is passed in a0" \
       "is missing \`mv a1,s1'" \
       "sed -i 's|argReg = i:|argReg = _i: let i = 0; in|' emit.nix" \
       "$matcher_check"

mutate "matcher: a value is held in a register across a branch target" \
       "must be the first instruction after" \
       'sed -i "s@st = prev.st // { cse = { }; nextCse = 0; clearedAt = item.name; };@st = prev.st;@" burg.nix' \
       "$matcher_check"

# lcc folds `tbl[1]' into one node, `ADDRGP4 tbl+4' (task-023). The rule table
# takes that symbol verbatim and poc/04-assembler resolves the displacement at
# layout time, so the one thing the matcher has to do is not lose it.
mutate "matcher: a global's constant displacement is dropped on the way to the assembler" \
       "is missing \`la s1,tbl+4'" \
       "sed -i 's@else sym)@else b.head (b.split \"[+]\" sym))@' emit.nix" \
       "$matcher_check"

# --- char and short (task-024) ---
# RV32I puts the sign in the LOAD, so lb and lbu are the whole difference
# between -1 and 255 for the same byte. The rule table is what decides that,
# which is why this is checked against the table and not against emitted text.
mutate "matcher: a signed byte is loaded with lbu, so it stops being signed" \
       "INDIRI1 must be lowered by rule \`reg_indiri1'" \
       "sed -i '/reg_indiri1/ s@\"lb @\"lbu @' rules.nix" \
       "$matcher_check"

# The row with the least else holding it: lowering INDIRU4 to `lbu' passes
# every other check in the suite AND returns the right answer, because
# ir/chars.c only ever loads an unsigned int it just stored a small value to.
mutate "matcher: an unsigned int is loaded a byte at a time" \
       "INDIRU4 must be lowered by rule \`reg_indiru'" \
       "sed -i '/reg_indiru\"/ s@\"lw @\"lbu @' rules.nix" \
       "$matcher_check"

mutate "matcher: a byte store becomes a word store, which writes three bytes too many" \
       "ASGNI1 must be lowered by rule \`stmt_asgni1'" \
       "sed -i '/stmt_asgni1/ s@\"sb @\"sw @' rules.nix" \
       "$matcher_check"

# lcc writes a conversion's SOURCE width in the node's symbol and its
# destination in the opcode, so CVII4 from one byte and CVII4 from two are the
# same opcode and different shift amounts. Drop the predicate and the byte's
# rule answers for the halfword.
mutate "matcher: a widening conversion ignores the width it is converting FROM" \
       "expected reg_cvii4_2@5, got reg_cvii4_1@5" \
       "sed -i 's@when = { srcSize = 1; };@when = null;@' rules.nix" \
       "$matcher_check"

# The two table-validation guards this change added. Neither can be reached by
# compiling anything: they are properties of the TABLE, so the only way to see
# them fail is to switch them off and watch must-fail.nix stop refusing.
mutate "matcher: two predicates in one \`when' are accepted, and only one applied" \
       "compiled fine: two predicates in one" \
       "sed -i 's@^else if multiWhen != \[ \] then@else if false then@' burg.nix" \
       "$must_fail"

mutate "matcher: a fragment rule may hand its users the register its kid used" \
       "compiled fine: a fragment rule producing a register" \
       "sed -i 's@^else if aliasing != \[ \] then@else if false then@' burg.nix" \
       "$must_fail"

# --- a discarded call result (task-025) ---
# burg.nix decides "this calls something" by matching the table's own
# callMarkers against the emitted TEXT. A call rule the markers do not match
# looks to it like code that leaves the argument registers alone.
#
# Aimed at `stmt_callv_indirect', which NOTHING else in the suite covers: no
# corpus case calls a void function through a pointer, so with this guard
# switched off the same mutation passes clean. Mutating a rule the corpus
# exercises would have been caught by the emitted-assembly check instead, and
# would have proved nothing about this guard.
mutate "matcher: a call rule's emitted text stops looking like a call" \
       "rule \`stmt_callv_indirect' is a rule for CALLV" \
       "sed -i '/stmt_callv_indirect/ s@\"jalr %0@\"jr %0@' rules.nix" \
       "$matcher_check"

# Criterion 4's own guard: when a discarded result STILL cannot be compiled --
# take both `stmt' rows away and `stmt: reg' takes the node -- the refusal has
# to name the C and not the template. Only messages.sh can see that it stopped.
mutate "matcher: a refused discarded call names the template and not the call" \
       "'a discarded call result with no statement rule to take it' threw, but the message does not contain" \
       "sed -i 's@              if isCall node@              if false@' burg.nix" \
       "bash $mut/messages.sh $mut"

# The population of call rules is DERIVED from the opcode, and this is what
# says so: a row added to the table and mentioned nowhere else is still
# checked. The hand-written list this replaced could not do it -- it was
# exactly this rule, added and forgotten, that passed the first version clean.
mutate "matcher: a call rule is added to the table and forgotten everywhere else" \
       "rule \`stmt_callp_direct' is a rule for CALLP4" \
       "sed -i '/stmt_calli_indirect/a\\    { id = \"stmt_callp_direct\"; nt = \"stmt\"; op = \"CALLP4\"; kids = [ \"acon\" ]; cost = 4; tmpl = \"jal %0\\n\"; }' rules.nix" \
       "$matcher_check"

# --- the bitwise, unary and unsigned rows (task-051) ---
# EVERY ONE OF THESE COMPILES, ASSEMBLES AND RUNS. What makes them wrong is
# that RV32I reads a 32-bit pattern two different ways and these rows pick the
# other one, so each is invisible on any operand below 2^31 -- which is why
# ir/unsig.c's data has bit 31 set and why these mutations exist at all.
mutate "matcher: an unsigned right shift becomes an arithmetic one" \
       "RSHU4 must be lowered by rule \`reg_rshu_imm'" \
       "sed -i '/reg_rshu_imm/ s@\"srli @\"srai @' rules.nix" \
       "$matcher_check"

mutate "matcher: an unsigned divide calls the signed routine" \
       "DIVU4 must be lowered by rule \`reg_divu_libcall'" \
       "sed -i 's@call __udivsi3@call __divsi3@' rules.nix" \
       "$matcher_check"

mutate "matcher: an unsigned remainder calls the signed routine" \
       "MODU4 must be lowered by rule \`reg_modu_libcall'" \
       "sed -i 's@call __umodsi3@call __modsi3@' rules.nix" \
       "$matcher_check"

mutate "matcher: an unsigned ordering branch becomes its signed twin" \
       "GEU4 must be lowered by rule \`stmt_geu4'" \
       "sed -i '/stmt_geu4/ s@\"bgeu @\"bge @' rules.nix" \
       "$matcher_check"

# The one the mnemonic table deliberately CANNOT see. GTU4 and LTU4 both emit
# `bltu' and differ only in which operand comes first, so `lowerings' has no
# row for either and the emitted text is the whole assertion.
mutate "matcher: the unsigned greater-than rule stops swapping its operands" \
       "is missing \`bltu s2,s1,.Lwide_4'" \
       "sed -i '/stmt_gtu4/ s@bltu %1,%0@bltu %0,%1@' rules.nix" \
       "$matcher_check"

# An opcode left with no rule, rather than a rule made wrong: the table is
# meant to REFUSE such an opcode by name, and that has to keep being true as
# rows are added.
#
# Other checks WOULD go red here -- `emitted' lists `xori s2,s2,-1' and the
# executed answer depends on `~x'. What this mutation demonstrates is that
# they do not get the chance: labelling fails first and names the opcode, which
# is the difference between "the answer was wrong" and "this target cannot
# compile that". The guard ordering in check.nix is what makes that true, and
# this is the only thing holding it.
#
# The row is RETARGETED at an opcode nothing emits rather than deleted,
# because deleting it trips the rule-count floor first and the suite then
# reports a harness fault instead of the refusal this is about. Both are red;
# only one of them is evidence.
mutate "matcher: an opcode is left with no rule at all" \
       "no rule labels BCOMU4" \
       "sed -i '/id = \"reg_bcomu\"/ s@op = \"BCOMU4\"@op = \"BCOMX4\"@' rules.nix" \
       "$matcher_check"

# THE REGISTER FORMS. Review found five of these rows selectable by nothing
# in the corpus and asserted by nothing but a mnemonic table describing them:
# the register forms of both unsigned shifts and of `|', the unsigned zero and
# the wide unsigned constant. ir/unsig.c now reaches all five, and these are
# what say so -- each was run against the old corpus first and passed clean.
mutate "matcher: an unsigned right shift by a register becomes an arithmetic one" \
       "RSHU4 must be lowered by rule \`reg_rshu_reg'" \
       "sed -i '/reg_rshu_reg/ s@\"srl @\"sra @' rules.nix" \
       "$matcher_check"

mutate "matcher: an unsigned left shift by a register shifts the other way" \
       "LSHU4 must be lowered by rule \`reg_lshu_reg'" \
       "sed -i '/reg_lshu_reg/ s@\"sll @\"srl @' rules.nix" \
       "$matcher_check"

mutate "matcher: an unsigned or against a register becomes an and" \
       "BORU4 must be lowered by rule \`reg_boru_reg'" \
       "sed -i '/reg_boru_reg/ s@\"or @\"and @' rules.nix" \
       "$matcher_check"

# An unsigned zero is the zero register and no instruction at all. A rule
# naming any OTHER register still reduces, still assembles and still runs --
# `s0' is the frame pointer, which is never zero -- so what catches it is the
# emitted text and, because ir/unsig.c stores the zero and then tests it, the
# answer.
mutate "matcher: an unsigned zero is read out of the frame pointer" \
       "is missing \`sw zero,-64(s0)'" \
       "sed -i '/reg_zerou/,/}/ s@tmpl = \"zero\";@tmpl = \"s0\";@' rules.nix" \
       "$matcher_check"

# lcc prints an unsigned constant in hexadecimal from 32768 up, so this is
# also the only node in the corpus that hands poc/04-assembler a `0x...'
# operand. `lui' is chosen over a nonsense mnemonic because it is a real
# instruction that takes the same two operands and truncates the low twelve
# bits -- the plausible mistake, not an obvious one.
mutate "matcher: a wide unsigned constant is materialised with lui alone" \
       "is missing \`li s4,0xdeadbeef'" \
       "sed -i '/reg_cnstu_wide/ s@\"li %c,%a@\"lui %c,%a@' rules.nix" \
       "$matcher_check"

mutate "matcher: the unsigned multiply stops sharing __mulsi3 with the signed one" \
       "MULU4 must be lowered by rule \`reg_mulu_libcall'" \
       "sed -i '/reg_mulu_libcall/,/}/ s@call __mulsi3@call __umulsi3@' rules.nix" \
       "$matcher_check"

# THE PAIRING TABLE, which is the only check that reads the I-typed and
# U-typed halves of the rule table against EACH OTHER.
#
# Aimed at ADDU4 because it is a pair that must AGREE and that NO other table
# mentions: no `lowerings' row, no `libcalls' row, no line in any
# `present'/`absent' list. With the pairing table gone this edit selects the
# same rule at the same cost and emits the same number of instructions, so
# nothing else in check.nix has anything to say about it -- which is the only
# way to aim at a check rather than past it.
mutate "matcher: unsigned addition quietly becomes subtraction" \
       "must emit same code and do not" \
       "sed -i '/reg_addu_reg/ s@\"add @\"sub @' rules.nix" \
       "$matcher_check"

mutate "harness: the signed/unsigned pairing table is emptied" \
       "pairs only 0 of the I-typed" \
       "sed -i 's@^  pairs = \[@  pairs = [ ]; unusedPairs = [@' cases.nix" \
       "$matcher_check"

mutate "harness: the opcode-lowering table is emptied" \
       "opcode lowerings, fewer than the" \
       "sed -i 's@^  lowerings = \[@  lowerings = [ ]; unusedLowerings = [@' cases.nix" \
       "$matcher_check"

# Only messages.sh can see this one. With the table check off, an unknown
# predicate reaches `holds' and still throws -- so must-fail.nix is satisfied
# and the diagnostic is the one thing that changed.
mutate "matcher: an unknown rule predicate is caught by the labeller, not the table" \
       "'a predicate the matcher does not implement' threw, but the message does not contain" \
       "sed -i 's@^else if unknownWhen != \[ \] then@else if false then@' burg.nix" \
       "bash $mut/messages.sh $mut"

mutate "harness: the opcode-coverage table is emptied" \
       "turns the opcode-coverage check into a no-op" \
       "sed -i 's|^  requiredOps = \[|  requiredOps = [ ]; unusedOps = [|' cases.nix" \
       "$matcher_check"

mutate "harness: the libcall table is emptied" \
       "names only 0 libcall lowerings" \
       "sed -i 's|^  libcalls = \[|  libcalls = [ ]; unusedLibcalls = [|' cases.nix" \
       "$matcher_check"

mutate "harness: the no-multiplier table is emptied" \
       "stops the check that RV32I has no multiplier" \
       "sed -i 's|^  forbiddenMnemonics = \[|  forbiddenMnemonics = [ ]; unusedForbidden = [|' cases.nix" \
       "$matcher_check"

mutate "harness: the after-a-label assertions are emptied" \
       "after-a-label assertions, fewer than the" \
       "sed -i 's|follows = \[ { label|follows = [ ]; unusedFollows = [ { label|' cases.nix" \
       "$matcher_check"

mutate "matcher: a bad rule table is accepted instead of refused" \
       "compiled fine: a declared nonterminal no rule can produce" \
       "sed -i 's|^else if deadNt != \[ \] then|else if false then|' burg.nix" \
       "$must_fail"

mutate "matcher: diagnostics lose their detail" \
       "'two rules share an id' threw, but the message does not contain" \
       'sed -i "s@is used twice@is not allowed@" burg.nix' \
       "bash $mut/messages.sh $mut"

mutate "harness: the labelling expectations are emptied" \
       "only 0 labelling expectations" \
       "sed -i 's|^  selections = \[|  selections = [ ]; unusedSelections = [|' cases.nix" \
       "$matcher_check"

mutate "harness: the cost duels stop perturbing anything" \
       "cost duels failed" \
       "sed -i 's|^      winner = \"reg_lshi_imm\"; loser = \"reg_lshi_reg\"; penalty = 5;|      winner = \"reg_lshi_imm\"; loser = \"reg_lshi_reg\"; penalty = 0;|' cases.nix" \
       "$matcher_check"

mutate "harness: the DAGs arrive empty" \
       "the corpus DAGs hold 0 nodes in total" \
       "for f in ir/*.sym; do sed -i \"/^ \\?[0-9]*[.']/d\" \$f; done" \
       "$matcher_check"

mutate "harness: the must-fail control cases are dropped" \
       "must-fail tables shrank" \
       "sed -i 's|^  controls = \[|  controls = [ ]; unusedControls = [|' must-fail.nix" \
       "$must_fail"

mutate "harness: the scale driver stops forcing the label tables" \
       "nothing was labelled" \
       "sed -i 's|b.foldl. (a: id: a + b.length (b.attrNames labels.\${id})) 0 forest.order|0|' bench.nix" \
       "$scale_check"

mutate "harness: the scale driver measures a different file" \
       "but the file is" \
       "sed -i 's|text = b.readFile (/. + path);|text = \"progend\";|' bench.nix" \
       "$scale_check"

# Stage 3 gets its own mutation, because what it catches is by definition what
# the stages above cannot: this one makes the divide libcall divide x by
# itself, which changes no line check.nix asserts and no instruction count, so
# check.nix reports a clean pass. Without it, "the emulator runs the code"
# would be the one unpinned claim in the suite -- and it is the only semantic
# oracle in it.
#
# It goes through poc/lib/mutant.sh like every other mutation here, which is
# what gives it a tmpfs of its own (task-041). It used to interleave with a
# shell function defined in this file, could not be handed to mutant.sh at all,
# and made do with a directory used once.
#
# Its run snippet carries its own CONTROL, and in front of the claim rather
# than after it. The property being demonstrated is "check.nix passes this and
# the emulator does not", so if check.nix ever starts catching the mutation the
# demonstration is void. The snippet then says CONTROL LOST and CANNOT produce
# the fragment below, so a lost control shows up as a red suite rather than as
# a detection -- ordering it the other way round would let the harness report
# its strongest result for its weakest reason.
#
# The expectation comes out of cases.nix rather than being written here as 72,
# so that the corpus stays the one place the answer lives.
# No guard on this eval: `set -e' aborts the harness if it fails, and a
# `--raw' eval of `toString c.expect' that succeeds cannot print nothing. The
# stage-3 loop above does the same lookup with no guard either.
expr_want=$(nix eval --impure --raw --expr \
  "let c = builtins.head (builtins.filter (e: e.file == \"expr\")
     (import $poc/cases.nix).execution); in toString c.expect")
# Assemble, link, run, and hold the answer to what cases.nix says. Shared by
# the two mutations below, which is why it is a variable: one of them breaks
# the compiler and one breaks this oracle, and they have to be judged by the
# same thing or neither proves the other is live.
#
# Two distinct diagnostics rather than one. A program that never reached the
# exit syscall and a program that exited with the wrong number are different
# failures, and the mutation stage requires every mutation to be told apart
# from every other by the text it produces.
exec_check="bash $mut/build-and-run.sh $mut expr $mut/exec > $mut/exec.json
python3 -c \"
import json, sys
r = json.load(open(sys.argv[1]))
if r['reason'] != 'exit':
    sys.exit('expr: the emulator stopped with reason %r rather than exiting'
             % (r['reason'],))
if r['exitCode'] != $expr_want:
    sys.exit('expr: the emulator returned %s, but cases.nix expects $expr_want'
             % (r['exitCode'],))
\" $mut/exec.json"
# The control, in front of the claim. nix's own message is kept rather than
# thrown away: `nix eval' failing means check.nix caught the mutation OR
# check.nix broke for a reason of its own, and discarding stderr would leave
# this asserting the first with no way to tell.
semantic_run="control=\$($matcher_check 2>&1 >/dev/null) || {
  echo 'CONTROL LOST: check.nix no longer PASSES the divide-by-itself mutation,'
  echo 'so it no longer demonstrates what executing the code sees and the pure'
  echo 'checks cannot. Either check.nix now catches it -- aim it somewhere'
  echo 'check.nix still cannot see -- or check.nix itself is broken. Its own'
  echo 'diagnostic, which is what tells those apart:'
  echo \"\$control\"
  exit 9
}
$exec_check"

mutate "matcher: the divide libcall divides x by itself" \
       "but cases.nix expects $expr_want" \
       "sed -i 's|mv a0,%0\\\\nmv a1,%1\\\\ncall __divsi3|mv a0,%0\\\\nmv a1,%0\\\\ncall __divsi3|' rules.nix" \
       "$semantic_run"

# And the oracle itself, which is the half of poc/04-assembler's precedent that
# moving the function does not give you for free. gnu-diff.sh is reachable by a
# mutation AND has one aimed at it (`the differential is handed an empty
# image'); build-and-run.sh was reachable and had none, so "the mutated copy is
# the one that runs" was argued rather than shown. Cut the emulator's step
# budget to 20 and the program cannot reach its exit syscall -- which only
# shows up if the mutated copy is what ran.
mutate "harness: the semantic oracle stops running the program to completion" \
       "rather than exiting" \
       "sed -i 's|cpu.run 200000|cpu.run 20|' build-and-run.sh" \
       "$exec_check"

# THE SECOND THING ONLY EXECUTION CAN SEE, and it is in a different file from
# the first: runtime.s. check.nix never reads it -- it checks that DIVU4's rule
# CALLS __udivsi3 and has nothing to say about what __udivsi3 then does -- so
# without this the runtime routines task-051 added would be pinned by nothing
# but the answer they happen to produce today.
#
# `bltu' -> `blt' inside the unsigned divide and remainder. On ir/unsig.c's
# operands, where the divisor is 9, the two comparisons agree and the mutation
# is invisible; ir/udiv.c exists to divide by 0x80000001, where a signed
# comparison makes `remainder < divisor' false at every iteration, so the
# subtract happens every time instead of none and the quotient saturates. Which
# is the argument for that file being in the corpus at all.
#
# The sed is anchored on `/^__udivsi3:/,$' and not on the label number the
# unsigned loops happen to use: the two signed routines contain the same
# instruction with a different forward label, and an anchor on `2f' would
# quietly start corrupting all four the day somebody renumbered them -- which
# the comment in runtime.s saying the loops are identical positively invites.
udiv_want=$(nix eval --impure --raw --expr \
  "let c = builtins.head (builtins.filter (e: e.file == \"udiv\")
     (import $poc/cases.nix).execution); in toString c.expect")
udiv_exec_check="bash $mut/build-and-run.sh $mut udiv $mut/uexec > $mut/uexec.json
python3 -c \"
import json, sys
r = json.load(open(sys.argv[1]))
if r['reason'] != 'exit':
    sys.exit('udiv: the emulator stopped with reason %r instead of exiting'
             % (r['reason'],))
if r['exitCode'] != $udiv_want:
    sys.exit('udiv: the emulator returned %s, but cases.nix expects $udiv_want'
             % (r['exitCode'],))
\" $mut/uexec.json"
udiv_semantic_run="control=\$($matcher_check 2>&1 >/dev/null) || {
  echo 'CONTROL LOST: check.nix no longer PASSES a change confined to runtime.s,'
  echo 'which it does not read. Either something now makes it read runtime.s --'
  echo 'in which case this mutation no longer demonstrates what only execution'
  echo 'can see -- or check.nix is broken for a reason of its own. Its own'
  echo 'diagnostic, which is what tells those apart:'
  echo \"\$control\"
  exit 9
}
$udiv_exec_check"

mutate "runtime: the unsigned divide and remainder compare as signed" \
       "but cases.nix expects $udiv_want" \
       "sed -i '/^__udivsi3:/,\$ s|bltu\tt1,a1|blt\tt1,a1|' runtime.s" \
       "$udiv_semantic_run"

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
declared=51
[ "${#names[@]}" -eq "$declared" ] || {
  echo "${#names[@]} mutations recorded, against the $declared this harness" >&2
  echo "declares. Either a mutate call has gone missing, or one was added" >&2
  echo "and the declared count was not raised with it." >&2; exit 1; }
echo "${#names[@]} mutations, each detected with its own distinct failure"

# --- 6. the ladder itself ------------------------------------------------
# Last, and deliberately so. This is the one stage whose outcome depends on
# what else the machine is doing, and on a busy one it renders no verdict and
# exits 3 -- which under `set -e' would take every check after it down with it.
# None of those need a quiet machine, so none of them should be lost to one.
#
# Exit 3 is neither a pass nor a failure, and has to read that way here too or
# the distinction dies at its first caller.
status=0
python3 "$poc/scale.py" "$poc" "${ladder[@]}" || status=$?
if [ "$status" = 3 ]; then
  echo "NO VERDICT: this machine was too busy for the ladder to measure on." >&2
  echo "Everything above this line ran and passed; nothing about the labeller's" >&2
  echo "linearity was shown either way. Re-run on an idle machine for that." >&2
fi
nixcc_selftest_verdict "$status"
[ "$nixcc_verdict" = 0 ] || exit "$nixcc_verdict"

