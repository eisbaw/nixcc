#!/usr/bin/env bash
# The closed loop: a C program compiled, assembled and RUN inside one `nix
# eval', printing a string through the write syscall and exiting through the
# exit syscall.
#
# Five stages, and the last two are the ones that decide whether the first
# three mean anything:
#
#   1. provenance.sh regenerates hello.sym from hello.c with lcc and diffs it,
#      so "this IR is real compiler output" is re-proved rather than claimed.
#   2. check.nix runs the whole chain, compares the loaded machine's RAM
#      byte-for-byte against the image the assembler produced, pins what the
#      program printed and what it exited with, cross-checks every branch
#      offset against the symbol table, and runs ten deliberately malformed
#      programs that must each halt with their own reported FAULT -- each
#      beside a control that must still run with its output pinned. It is
#      pure, so `nix flake check' runs it too.
#   2b. must-fail.nix and messages.sh cover what check.nix cannot see: the
#      throws that happen before there is a demo to look at, held to their
#      diagnostic TEXT, because builtins.tryEval never hands back a message.
#   3. closed-loop.sh runs the demo in ONE `nix eval' with a PATH holding
#      exactly one binary -- nix -- and refuses to render a verdict if the
#      cross assembler, linker or objcopy is reachable from it after all.
#   4. measure.py reports what the loop costs in memory, which decision-001
#      says is the constraint that decides whether this scales.
#   5. A mutation test over the loop AND the harness. This project has shipped
#      four suites that reported PASS while verifying nothing, so every check
#      above is assumed broken until a mutation proves otherwise.
#
# There is no timing ladder here and so no NO VERDICT exit: nothing in this
# PoC compares two timings.
set -euo pipefail
cd "$(dirname "$0")"
poc=$PWD
root=$(cd "$poc/.." && pwd)
work=$(mktemp -d)
keep=1                       # artifacts are kept unless we reach a clean pass
cleanup() {
  if [ "$keep" = 1 ]; then echo "artifacts kept in $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT

: "${NIX_RISCV:?NIX_RISCV is unset -- run this inside nix develop}"

pure_check() {               # $1 the PoC directory to check
  nix eval --impure --raw --expr \
    "import $1/check.nix { cpu = import (/. + \"$NIX_RISCV/rv32.nix\"); }"
}

# --- 1. the IR is what lcc produces ---------------------------------------
bash "$poc/provenance.sh" "$poc"

# --- 2. the pure verdict ---------------------------------------------------
pure_check "$poc"
nix eval --impure --raw --expr "(import $poc/must-fail.nix).summary"
bash "$poc/messages.sh" "$poc"

# --- 3. one eval, nothing but nix on PATH ---------------------------------
bash "$poc/closed-loop.sh" "$poc"

# --- 4. what it costs ------------------------------------------------------
python3 "$poc/measure.py" "$poc"

# --- 5. mutation test ------------------------------------------------------
# Each mutation must make the suite fail, must produce its own fragment, and
# must produce NONE of the other fragments -- that last condition is what
# proves the checks distinguish rather than all collapsing into one alarm. The
# harness is mutated as well as the thing it checks.
#
# The mutated copy needs its sibling PoCs beside it, because demo.nix reaches
# ../03-matcher and ../04-assembler by relative path. They are symlinked
# rather than copied: they are not what is being mutated, and a copy of them
# is a copy that could go stale.
mut=$work/poc/05-loop
mkdir -p "$work/poc"
for sib in 01-encoder 03-matcher 04-assembler lib; do
  ln -s "$root/$sib" "$work/poc/$sib"
done

names=(); fragments=(); outputs=()

# $1 name, $2 fragment that must appear, $3 snippet that mutates $mut,
# $4 snippet that runs the mutated suite
mutate() {
  rm -rf "$mut"; cp -r "$poc" "$mut"
  ( cd "$mut" && eval "$3" )
  # A sed whose pattern no longer matches edits nothing, and the suite then
  # passes, which reads as "not detected" when the truth is "not applied".
  if diff -rq "$poc" "$mut" >/dev/null; then
    echo "HARNESS FAULT: mutation '$1' changed nothing -- its pattern no longer matches" >&2
    exit 1
  fi
  local out status=0
  out=$(cd "$mut" && eval "$4" 2>&1) || status=$?
  if [ "$status" = 0 ]; then
    echo "MUTATION NOT DETECTED: '$1' still passed:" >&2
    echo "$out" >&2
    exit 1
  fi
  # Only the text from the LAST `error:' onwards is kept, for the reason
  # poc/04-assembler/messages.sh gives: nix prints the source around each
  # frame, and check.nix's source contains the message templates of every
  # other check in it, so comparing against everything nix printed would let
  # one mutation claim another's fragment. Output with no `error:' line at all
  # -- a shell stage, or python -- is kept whole.
  names+=("$1"); fragments+=("$2")
  outputs+=("$(printf '%s\n' "$out" |
    awk '/^ *error: /{buf = ""} {buf = buf $0 "\n"} END{printf "%s", buf}')")
}

provenance_check="bash $mut/provenance.sh $mut"
closed_loop="bash $mut/closed-loop.sh $mut"
mutated_check="nix eval --impure --raw --expr \"import $mut/check.nix { cpu = import (/. + \\\"$NIX_RISCV/rv32.nix\\\"); }\""
measure_check="python3 $mut/measure.py $mut"
must_fail="nix eval --impure --raw --expr '(import $mut/must-fail.nix).summary'"
messages_check="bash $mut/messages.sh $mut"

# --- the demo itself ---
mutate "driver: hello() is told the vector is one element shorter than it is" \
       "wrote \`1..10 = 45" \
       "sed -i 's@(it.insn \"li\" \[ \"a1\" n \])@(it.insn \"li\" [ \"a1\" (n - 1) ])@' driver.nix" \
       "$mutated_check"

# The VECTOR, not the message. hello() reads the vector with `lw', which
# faults on a misaligned address; it writes the message with `sb', which has
# no alignment rule at all now that task-024 exists.
mutate "driver: the vector stops being word-aligned" \
       "which is not word-aligned" \
       "sed -i 's@      (it.label \"vec\")@      (it.bytes [ 0 ]) (it.label \"vec\")@' driver.nix" \
       "$mutated_check"

# The demo is the evidence that task-023, task-024 and task-025 are closed,
# and the way that stops being true is not a regression in the compiler -- it
# is hello.c drifting back into something that does not use them.
mutate "harness: a task drops out of the demonstrates table" \
       "says nothing about task-024" \
       "sed -i 's@^      \"task-024\" = {@      \"unused-024\" = {@' cases.nix" \
       "$mutated_check"

# The emitted-line pin is compared against what the matcher really produced for
# hello.c, not against a copy of itself: ask for a word store and the check
# says so. Mutating hello.c instead would take hello.sym with it, and the
# provenance stage would report that first.
mutate "harness: an emitted-line pin is not one the demo actually emits" \
       "hello.c no longer demonstrates task-024" \
       "sed -i 's@emits = \"sb s\[0-9\]+@emits = \"sw s[0-9]+@' cases.nix" \
       "$mutated_check"

# The task-025 pin is the one that had to be rebuilt: `call wr' is emitted
# whether the result is used or not, so a must-contain pin on it passed on the
# very program it forbade. This asks the IR instead -- a listed CALLI4 nothing
# references -- and the mutation makes it ask about an opcode hello.c has not
# got, which is what a pin looking at the wrong thing would do.
mutate "harness: the discarded-call pin asks about an opcode the demo has not got" \
       "hello.c no longer demonstrates task-025" \
       "sed -i 's@discardedCall = \"CALLI4\";@discardedCall = \"CALLV\";@' cases.nix" \
       "$mutated_check"

mutate "demo: the machine is entered four bytes past _start" \
       "the machine was entered at 0x" \
       "sed -i 's@    entry = base;@    entry = base + 4;@' demo.nix" \
       "$mutated_check"

# --- the fault table, which is what proves the emulator stage can fail ---
mutate "cases: a malformed program stops being malformed" \
       "ran to a CLEAN EXIT with status" \
       "sed -i 's@(it.insn \"li\" \[ \"a7\" 1234 \])@(it.insn \"li\" [ \"a7\" 93 ])@' cases.nix" \
       "$mutated_check"

mutate "cases: a control program faults instead of running" \
       "it is the case that must still RUN" \
       "sed -i 's@(it.insn \"li\" \[ \"t0\" (ramSize - 4) \])@(it.insn \"li\" [ \"t0\" (ramSize + 4) ])@' cases.nix" \
       "$mutated_check"

mutate "cases: a control program exits with something other than what it claims" \
       "exited 8, expected 7" \
       "sed -i 's@items = it.program (it.exitWith 7);@items = it.program (it.exitWith 8);@' cases.nix" \
       "$mutated_check"

mutate "cases: the program that never stops claims to exit cleanly" \
       "no longer covers budget" \
       "sed -i 's@      reason = \"budget\";@      reason = \"exit\";@' cases.nix" \
       "$mutated_check"

# --- the harness ---
mutate "harness: the fault table is emptied" \
       "the fault table has 0 programs" \
       "sed -i 's@^  faults = \[@  faults = [ ]; unusedFaults = [@' cases.nix" \
       "$mutated_check"

mutate "harness: the control table is emptied" \
       "the control table has 0 programs" \
       "sed -i 's@^  controls = \[@  controls = [ ]; unusedControls = [@' cases.nix" \
       "$mutated_check"

mutate "harness: the compiled function's labels are no longer recognised as its own" \
       "branches to its own labels, fewer than" \
       "sed -i 's@    labelPrefix = \".Lhello_\";@    labelPrefix = \".Lnothing_\";@' cases.nix" \
       "$mutated_check"

# The cross-check that makes "resolved from a symbol table" a measurement: the
# distance the symbol table implies, decoded back out of the assembled word.
# Bend the decoder and the two must stop agreeing.
mutate "harness: the branch immediate is decoded four bytes off" \
       "but the assembled word encodes" \
       "sed -i 's@      sext 13 (field w 8 4 \* 2@      sext 13 (4 + field w 8 4 * 2@' check.nix" \
       "$mutated_check"

mutate "harness: the expected total is not the one the program computes" \
       "expected \`1..10 = 56" \
       "sed -i \"s@0 vector;@1 vector;@\" driver.nix" \
       "$mutated_check"

mutate "harness: the required fault classifications are emptied" \
       "required-fault-classification list has 0 entries" \
       "sed -i 's@^  requiredReasons = \[@  requiredReasons = [ ]; unusedReasons = [@' cases.nix" \
       "$mutated_check"

mutate "harness: the required-symbol list is emptied" \
       "required-symbol list has 0 entries" \
       "sed -i 's@^  requiredSymbols = \[@  requiredSymbols = [ ]; unusedSymbols = [@' cases.nix" \
       "$mutated_check"

mutate "harness: the demo's address table is emptied" \
       "address table has 0 entries" \
       "sed -i 's@^    symbols = { _start = base;.*@    symbols = { };@' cases.nix" \
       "$mutated_check"

mutate "harness: a control stops pinning what it printed" \
       "pins no stdout, so nothing would notice if it started writing" \
       "sed -i '0,/^      stdoutBytes = \[ \];$/s///' cases.nix" \
       "$mutated_check"

mutate "harness: the compiled-branch floor is set where no image can fall below it" \
       "which no image can fall below" \
       "sed -i 's@    minCompiledBranches = 3;@    minCompiledBranches = 0;@' cases.nix" \
       "$mutated_check"

# The whole-image comparison, at the two places the first version of it --
# which read one WORD -- let something through: a byte changed in the middle,
# and a byte appended to the end.
mutate "demo: one byte in the middle of the image is not the byte the assembler produced" \
       "differs from the assembled image at byte" \
       "sed -i 's@    inherit (image) bytes;@    bytes = map (i: if i == 400 then 0 else builtins.elemAt image.bytes i) (builtins.genList (i: i) (builtins.length image.bytes));@' demo.nix" \
       "$mutated_check"

mutate "demo: the emulator is handed one byte more than the assembler produced" \
       "but the assembler produced an image of" \
       "sed -i 's@    inherit (image) bytes;@    bytes = image.bytes ++ [ 0 ];@' demo.nix" \
       "$mutated_check"

mutate "demo: the shared runtime is left out of the image" \
       "which nothing in this unit defines" \
       "sed -i 's@    ++ parse.parseFile (matcher + \"/runtime.s\");@    ++ [ ];@' demo.nix" \
       "$mutated_check"

mutate "cases: a required symbol is one the runtime does not define" \
       "must: every unit the demo is composed of has to be in it" \
       "sed -i 's@    \"__mulsi3\" \"h\" \"g\"@    \"__mulsi3\" \"h\" \"nosuchsymbol\"@' cases.nix" \
       "$mutated_check"

mutate "cases: a pinned address is not where the driver actually puts it" \
       "\`wr' is at 0x" \
       "sed -i 's@wr = base + 28;@wr = base + 32;@' cases.nix" \
       "$mutated_check"

# Criterion 7's own two guards. Neither can be reached by mutating the
# compiler -- emit.nix always produces both directions -- so they are reached
# by breaking the filter that classifies them, which is the only way to see
# either of them fail at all.
mutate "harness: no branch is classified as forward" \
       "goes FORWARD to a label defined later" \
       "sed -i 's@  forward = b.filter (br: br.delta > 0) compiledBranches;@  forward = b.filter (br: br.delta > 99999999) compiledBranches;@' check.nix" \
       "$mutated_check"

mutate "harness: no branch is classified as backward" \
       "goes BACKWARD, so nothing shows a backward reference" \
       "sed -i 's@  backward = b.filter (br: br.delta < 0) compiledBranches;@  backward = b.filter (br: br.delta < -99999999) compiledBranches;@' check.nix" \
       "$mutated_check"

# --- the harnesses that are not check.nix ---
mutate "must-fail: the message-layout guard stops refusing" \
       "should have been refused but went through fine" \
       "sed -i 's@    if b.stringLength prefix != 8 then@    if false then@' driver.nix" \
       "$must_fail"

mutate "must-fail: the control cases are dropped" \
       "must-fail tables shrank" \
       "sed -i 's@^  controls = \[@  controls = [ ]; unusedControls = [@' must-fail.nix" \
       "$must_fail"

mutate "messages: a refusal keeps refusing but stops saying why" \
       "threw, but the message does not contain" \
       "sed -i 's@which is \${toString (b.stringLength digits)} digits; hello() converts exactly two@is the wrong length@' driver.nix" \
       "$messages_check"


mutate "provenance: the checked-in IR stops being what lcc produces" \
       "is not what lcc produces for hello.c any more" \
       "sed -i 's@^maxoff=8@maxoff=16@' hello.sym" \
       "$provenance_check"

mutate "closed loop: the single-eval stage compares the output it was given" \
       "the program wrote [49, 46" \
       "sed -i 's@(it.insn \"li\" \[ \"a1\" n \])@(it.insn \"li\" [ \"a1\" (n - 1) ])@' driver.nix" \
       "$closed_loop"

mutate "closed loop: the toolchain is left reachable from the guarded PATH" \
       "is still reachable from the guarded PATH" \
       "sed -i \"s|^guarded=.*|guarded=\\\$PATH|\" closed-loop.sh" \
       "$closed_loop"

mutate "harness: the memory measurement measures something other than the demo" \
       "measuring an evaluation that ran nothing" \
       "sed -i \"s@in toString d.report.steps@in toString 1@\" measure.py" \
       "$measure_check"

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
# A floor on the mutation table itself, set at what is actually here: two
# mutations could be deleted silently under a slacker one, and a table of
# mutations is a table like any other.
[ "${#names[@]}" -ge 34 ] || { echo "only ${#names[@]} mutations were tried" >&2; exit 1; }
echo "${#names[@]} mutations, each detected with its own failure"

keep=0
