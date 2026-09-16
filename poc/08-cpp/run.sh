#!/usr/bin/env bash
# The minimal-C-preprocessor PoC: hand-written expansion, `#if' and
# line-number tables, reject paths and their messages, two programs
# preprocessed, compiled and RUN, lcc's own frontend reading our linemarkers,
# a token-stream differential against gcc -E over 43 translation units, and a
# mutation test of this harness against itself.
#
# The mutation stage is not decoration. An earlier harness in this repo printed
# "48 instructions compared / PASS" while comparing nothing at all, because
# zip() truncates and the count came from the table rather than from the work.
# So every check below is required to prove it can fail, and to fail
# differently from the others.
#
# NO TIMING LADDER HERE, and that is a decision rather than an omission. The
# preprocessor's loop is one genericClosure step per LOGICAL LINE -- the shape
# decision-001 sanctions, and poc/02-lexer already measures that shape linear
# over a 13.9x ladder -- so a timing ladder here would mostly re-measure the
# lexer, on a machine decision-008 says has to be quiet before the answer means
# anything. What IS this stage's own cost is MEMORY, and memory.py measures
# that instead: the same source lexed and preprocessed in one interleaved
# session, so the difference between them is what this stage adds. decision-008
# says plainly that the memory figures are unaffected by which core class ran
# them, so there is no contention self-test and no NO VERDICT path in this
# file.
set -euo pipefail
# Scratch work happens on a tmpfs inside a bubblewrap sandbox, which the kernel
# reclaims when this process exits: no cleanup, no trap, nothing to delete.
# This re-execs, so it comes before anything else. See poc/lib/sandbox.sh.
# shellcheck source-path=SCRIPTDIR source=../lib/sandbox.sh
. "$(dirname "$(readlink -f "$0")")/../lib/sandbox.sh"
cd "$(dirname "$0")"
poc=$PWD
root=$(cd "$poc/.." && pwd)

: "${NIX_RISCV:?NIX_RISCV is unset -- run this inside nix develop}"
command -v rcc-rv32 >/dev/null 2>&1 || {
  echo "no \`rcc-rv32' on PATH. The linemarker stage needs lcc's own frontend," >&2
  echo "which is the only consumer of a linemarker in reach, and the flake" >&2
  echo "builds it. Run this inside \`nix develop'." >&2
  exit 2; }
command -v gcc >/dev/null 2>&1 || {
  echo "no \`gcc' on PATH. The differential needs a real preprocessor to" >&2
  echo "compare against. Run this inside \`nix develop'." >&2
  exit 2; }

cpu="import (/. + (\"$NIX_RISCV\" + \"/rv32.nix\"))"

# --- 1. hand-written expansion, #if and line-number tables ---------------
nix eval --impure --raw --expr "import $poc/check.nix"

# --- 2. reject paths ----------------------------------------------------
nix eval --impure --raw --expr "(import $poc/must-fail.nix).summary"

bash "$poc/messages.sh" "$poc"

# --- 3. the programs, preprocessed, compiled and RUN ---------------------
nix eval --impure --raw --expr "import $poc/execute.nix { cpu = $cpu; }"

# --- 4. lcc's own frontend reading our linemarkers -----------------------
bash "$poc/frontend.sh" "$poc" "$work"

# --- 5. the differential against gcc -E ----------------------------------
python3 "$poc/oracle.py" "$poc" "$work"

# --- 6. what this stage costs, which on this project means memory --------
python3 "$poc/memory.py" "$poc"

# --- 7. mutation test ---------------------------------------------------
# Each mutation must make the suite fail, must produce its own fragment, and
# must produce NONE of the other fragments. That last condition is what proves
# the checks are distinguishing rather than all collapsing into one alarm.
#
# The mutated copy needs its siblings beside it, because cpp.nix reaches
# ../02-lexer, ../06-constants and ../07-parser by relative path. They are
# symlinked rather than copied: they are not what is being mutated, and a copy
# of them is a copy that could go stale.
mut=$work/poc/08-cpp
mkdir -p "$work/poc"
for dir in 01-encoder 02-lexer 03-matcher 04-assembler 05-loop 06-constants 07-parser lib; do
  # Checked rather than linked blind: a renamed sibling would otherwise become
  # a dangling link and surface as an inscrutable Nix import error from inside
  # a mutant, which is the hardest place in this tree to read a failure from.
  [ -d "$root/$dir" ] || {
    echo "no $root/$dir to link beside the mutated copy; the preprocessor" >&2
    echo "reaches its siblings by relative path, so a renamed one has to be" >&2
    echo "a named fault here rather than a Nix error inside a mutation." >&2
    exit 1; }
  ln -s "$root/$dir" "$work/poc/$dir"
done

names=(); fragments=(); outputs=()

# $1 name, $2 fragment that must appear, $3 shell snippet that mutates $mut,
# $4 shell snippet that runs the mutated suite
# $5 optional: "no" if $3 changes the INVOCATION rather than the tree
mutate() {
  # A tmpfs of its own for every mutation, so no state can survive from the
  # last one -- by construction, rather than by a remove that has to have
  # worked. poc/lib/mutant.sh does the copy, the apply and the run inside it.
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
message_check="bash $mut/messages.sh $mut"
execute_check="nix eval --impure --raw --expr 'import $mut/execute.nix { cpu = $cpu; }'"
frontend_check="bash $mut/frontend.sh $mut \$(mktemp -d)"
oracle_check="python3 $mut/oracle.py $mut \$(mktemp -d)"
memory_check="python3 $mut/memory.py $mut"

# --- mutations of the preprocessor ---
#
# A NOTE ON FRAGMENTS. check.nix reports EVERY failing case, which is what a
# human wants and what makes distinctness hard: a mutation that breaks the
# conditional stack breaks forty cases and its output then contains forty case
# names. So a fragment here is the case's own sentence, chosen to belong to a
# case that no OTHER mutation breaks -- and the distinctness loop at the end
# is what proves that choice rather than this paragraph.

mutate "cpp: a macro is not expanded at all" \
       "a macro with a one-token body: expected" \
       "sed -i 's@^  expandList = macros: ts:.*@  expandList = _: ts: ts;@' cpp.nix" \
       "$table_check"

# NOT "loops forever": without the hide set the expansion of a self-referential
# macro runs until the nesting cap, so the symptom is the CAP's diagnostic.
mutate "cpp: the hide set stops hiding, so a macro re-expands inside itself" \
       "nested more than 200 macros deep" \
       "sed -i 's@if !(invokes macros t) || hidden ? \${t.text} then \[ t \]@if !(invokes macros t) then [ t ]@' cpp.nix" \
       "$table_check"

# The symptom is not a wrong macro table but a THROW: with the entry still
# there, the case that redefines the name after undefining it is a
# redefinition with a different replacement list, which C89 6.8.3 forbids.
mutate "cpp: #undef leaves the macro defined" \
       "is redefined with a different replacement list" \
       "sed -i 's@st // { macros = b.removeAttrs st.macros \[ (oneName \"#undef\" args dline) \]; }@st // { macros = st.macros; }@' cpp.nix" \
       "$table_check"

# With the arms inverted, a `#if 0' group goes LIVE -- and one of the
# expansion cases fences off text that is not a parsable `#if' expression at
# all, so the mutant dies there rather than reaching a case comparison. That
# is the right symptom to pin: it is what `#if 0' fencing is FOR.
mutate "cpp: a conditional emits the arm it should have skipped" \
       "is not a value in a \`#if' expression" \
       "sed -i 's@          active = live st \&\& taken;@          active = live st \&\& !taken;@' cpp.nix" \
       "$table_check"

# An #elif chain that forgets which arm was taken emits SEVERAL arms rather
# than one, which is a different defect from choosing the wrong one.
# The fragment is the two arms the mutant emits where one was wanted, not
# the case's name: a preprocessor that expanded no macros at all also fails
# this case, and the pair has to be told apart by what came OUT.
mutate "cpp: #elif forgets that an earlier arm already fired" \
       "\`ID:b' \`;:;' \`INT:int' \`ID:c'" \
       "sed -i 's@take = frame.parentActive \&\& !frame.taken@take = frame.parentActive@' cpp.nix" \
       "$table_check"

mutate "cpp: a skipped group is preprocessed anyway" \
       "\`#include' is task-013.03" \
       "sed -i 's@^        else if skipping then st\$@        else if false then st@' cpp.nix" \
       "$table_check"

# With `defined' expanded along with everything else it becomes an ordinary
# identifier, so it is replaced by 0 and `0 (0)' is left over -- the mutant
# never reaches a case comparison.
mutate "cpp: the operand of defined() is macro-expanded first" \
       "is left over at the end of the \`#if' expression" \
       "sed -i 's@(resolveDefined st.macros args)@args@g' cpp.nix" \
       "$table_check"

# The case this picks is the only one that separates the conversion from the
# WRAP: `sgn' consults the operand's own signedness, so a mutant that stops
# converting still gets every case where both operands agree.
mutate "cpp: an unsigned operand no longer drags the comparison with it" \
       "a signed value above INT_MAX compares equal to its unsigned twin" \
       "sed -i 's@^      cmp = f: x: y: let u = x.u || y.u; in@      cmp = f: x: y: let u = false; in@' cpp.nix" \
       "$table_check"

mutate "cpp: the right shift of a negative value truncates instead of flooring" \
       "a right shift of a negative value is arithmetic, not a division" \
       "sed -i 's@^  floorDiv = x: y: let q = x / y; in if x - q \* y < 0 then q - 1 else q;@  floorDiv = x: y: x / y;@' cpp.nix" \
       "$table_check"

mutate "cpp: #if arithmetic stops wrapping at 32 bits" \
       "an unsigned add wraps to zero rather than growing a 33rd bit" \
       "sed -i 's@^  wrap = n:@  wrap = n: n; unusedWrap = n:@' cpp.nix" \
       "$table_check"

# The multiply is the one operation that cannot be done the naive way at all:
# with the halves removed, a product of two values near 2^32 is past Nix's
# 63-bit ceiling and the evaluator THROWS. That is the failure decision-001's
# whole shape exists to avoid, and no other mutation reaches it.
mutate "cpp: the multiply forms a product Nix cannot hold" \
       "integer overflow" \
       "sed -i 's@^    wrap (a0 \* b0 + cross \* 65536);@    wrap (x * y);@' cpp.nix" \
       "$table_check"

mutate "cpp: && stops short-circuiting, so a guarded division by zero is evaluated" \
       "\`/' by zero in a \`#if' expression" \
       "sed -i 's@go { v = if acc.v == 0 then 0 else (if r.v == 0 then 0 else 1); u = false; inherit (r) i; }@go { v = if r.v == 0 then 0 else (if acc.v == 0 then 0 else 1); u = false; inherit (r) i; }@' cpp.nix" \
       "$table_check"

mutate "cpp: #line no longer moves the numbering" \
       "#line moves the numbering of every line after it: the line numbers are" \
       "sed -i 's@delta = num - (endLine + 1);@delta = 0;@' cpp.nix" \
       "$table_check"

# With no marker at all rcc never learns the file name, so it reports a bare
# line number -- which is what tells this apart from a marker that is present
# and wrong.
mutate "cpp: no linemarker is ever emitted" \
       "lcc said instead: 2: warning: empty declaration" \
       "sed -i 's@          marker = prev == null || prev.file != l.file || prev.line + 1 != l.line;@          marker = false;@' cpp.nix" \
       "$frontend_check"

# The marker's NUMBER, as opposed to its presence. lcc's resynch() reads `# n'
# as the number of the NEXT line, so an off-by-one is invisible to anything
# that does not make lcc say where it thinks it is.
mutate "cpp: the linemarker names its own line instead of the next one" \
       "lcc said instead: one.c:1: warning: empty declaration" \
       "sed -i 's@toString l.line@toString (l.line - 1)@' cpp.nix" \
       "$frontend_check"

# This one CANNOT be caught by the differential, and the reason is worth
# stating: `a <<= 2' and `a << = 2' lex to the same four tokens, so a
# `kind:text' comparison sees no difference at all. What the difference
# changes is what lcc's parser does with them, and the only check that holds
# it is the exact rendered text in cases.nix's relocation table.
mutate "cpp: render loses the adjacency that keeps \`<<=' one operator" \
       "the rendered output is" \
       "sed -i 's@            if t.ws != \"\" then \" \" + t.text@            if true then \" \" + t.text@' cpp.nix" \
       "$table_check"

# THE OTHER HALF OF THE SAME PROPERTY, and the one that was missing: a token
# that had NO whitespace before it keeps none, unless the token now in front
# of it arrived from an expansion and would paste. `#define P +' in `a P+ +2'
# renders `a ++ +2' without this -- a program that compiles and increments
# `a', where `a + + +2' does not. The token streams are identical either way,
# so only the render round-trip can see it.
mutate "cpp: render lets an expansion paste onto the token after it" \
       "our own render, re-lexed, against our token stream" \
       "sed -i 's@            else if staysApart (b.elemAt ts (j - 1)) t then t.text@            else if true then t.text@' cpp.nix" \
       "$oracle_check"

mutate "cpp: an unsigned divide stops converting its operands" \
       "an unsigned divide converts without needing the wrap" \
       "sed -i 's@let d = divisor \"/\" y; in if u then x.v / d.v else@let d = divisor \"/\" y; in if false then x.v / d.v else@' cpp.nix" \
       "$table_check"

mutate "cpp: a function-like #define hidden behind a continuation is accepted" \
       "'a function-like macro across a continuation' did not throw" \
       "sed -i 's@(first.ws == \"\" || first.glue)@(first.ws == \"\")@' cpp.nix" \
       "$message_check"

mutate "cpp: a directive line is emitted as ordinary tokens" \
       "our token stream against gcc -E" \
       "sed -i 's@        if isDirective then { key = k; st = directive st ts (here ts); out = \[ \]; }@        if false then { key = k; inherit st; out = [ ]; }@' cpp.nix" \
       "$oracle_check"

mutate "cpp: a phase-2 splice inside a token is lexed as two tokens instead of refused" \
       "'a continuation that joins two token characters' did not throw" \
       "sed -i 's@          joined = b.filter@          joined = b.filter (_: false) (b.genList (i: i) 0); unusedJoined = b.filter@' cpp.nix" \
       "$message_check"

mutate "cpp: #include is quietly ignored instead of naming the slice that will do it" \
       "'#include with angle brackets' did not throw" \
       "sed -i 's@^        else if what == \"include\" then\$@        else if what == \"include\" then st else if false then@' cpp.nix" \
       "$message_check"

mutate "cpp: a function-like #define is accepted as an object-like one" \
       "'a function-like macro' did not throw" \
       "sed -i 's@else if body != \[ \] \&\& first.kind == \"(\" \&\& (first.ws == \"\" || first.glue) then@else if false then@' cpp.nix" \
       "$message_check"

mutate "cpp: the refusal of an unimplemented directive stops naming task-014" \
       "threw, but its diagnostic does not contain" \
       "sed -i 's@is tracked in task-014@is not implemented@' cpp.nix" \
       "$message_check"

# An `#else' that never fires means the macro it defines is never defined,
# and the program then does not COMPILE -- which is a different failure from
# computing the wrong number, and worth having its own mutation.
mutate "cpp: an #else never fires, so the macro it defines never exists" \
       "undeclared identifier \`EXTRA'" \
       "sed -i 's@          taken = if live st then taken else true;@          taken = true;@' cpp.nix" \
       "$execute_check"

# And the one that changes the ANSWER rather than breaking the compile: with
# no `#elif' arm able to fire, table.c falls through to its `#else' and
# multiplies by 1000 instead of 11.
mutate "cpp: no #elif arm can fire, so the program runs and prints the wrong number" \
       "wanted \`408" \
       "sed -i 's@^                \&\& evalExpr@                \&\& false \&\& evalExpr@' cpp.nix" \
       "$execute_check"

# --- mutations of the harness ---
mutate "harness: the expansion table is emptied" \
       "0 expansion cases, against the" \
       "sed -i 's@^  expansions = \[@  expansions = [ ]; unusedExpansions = [@' cases.nix" \
       "$table_check"

mutate "harness: the #if table is emptied" \
       "0 \`#if' cases, against the" \
       "sed -i 's@^  conditions = \[@  conditions = [ ]; unusedConditions = [@' cases.nix" \
       "$table_check"

mutate "harness: the line-number table is emptied" \
       "0 relocation cases, against the" \
       "sed -i 's@^  relocations = \[@  relocations = [ ]; unusedRelocations = [@' cases.nix" \
       "$table_check"

mutate "harness: the reject table is emptied" \
       "must-fail holds 0 cases" \
       "sed -i 's@^  cases = \[@  cases = [ ]; unusedCases = [@' must-fail.nix" \
       "$must_fail"

mutate "harness: must-fail stops actually preprocessing anything" \
       "these controls should have preprocessed but threw" \
       "sed -i 's@  goes = src: (b.tryEval (b.deepSeq (cpp.tokensOf { inherit src; file = \"t.c\"; }) true)).success;@  goes = src: b.stringLength src == 0;@' must-fail.nix" \
       "$must_fail"

# The one that matters most: with gcc replaced by `cat', the corpus comes back
# as its own text with every directive still in it. A differential that would
# still pass with the reference removed is not a differential.
mutate "harness: the differential stops consulting a real preprocessor" \
       "left a directive line in its output" \
       "sed -i 's@^ORACLE = \"gcc\"@ORACLE = \"cat\"@;s@^FLAGS = .*@FLAGS = []@' oracle.py" \
       "$oracle_check"

mutate "harness: the differential's corpus shrinks" \
       "cpp corpus files were handed in, against the" \
       "sed -i 's@corpus = sorted((poc / \"cpp\").glob(\"\*.c\"))@corpus = sorted((poc / \"cpp\").glob(\"*.c\"))[:3]@' oracle.py" \
       "$oracle_check"

mutate "harness: the differential stops comparing the preprocessor-free units" \
       "preprocessor-free translation units were handed in" \
       "sed -i 's@    identity = sorted((poc.parent / \"07-parser\" / \"c\").glob(\"\*.c\"))@    identity = sorted((poc.parent / \"07-parser\" / \"c\").glob(\"*.c\"))[:5]@' oracle.py" \
       "$oracle_check"

mutate "harness: the programs are no longer run, only compiled" \
       "printed \`' and exited" \
       "sed -i 's@      p // { inherit (d) report; })@      p // { report = { stdout = \"\"; exitCode = 0; steps = 0; }; })@' execute.nix" \
       "$execute_check"

# The two ladder mutations name the FLOOR they trip rather than the sentence
# they share, because both axes report the same shape of fault.
mutate "harness: the memory ladder's sizes are cut below where anything shows" \
       "point at 2 functions produced" \
       "sed -i 's@^LADDER = .*@LADDER = [2, 3]@' memory.py" \
       "$memory_check"

mutate "harness: the macro-table axis is cut below where the table costs anything" \
       "point at 5 macros produced" \
       "sed -i 's@^MACRO_LADDER = .*@MACRO_LADDER = [5, 20]@' memory.py" \
       "$memory_check"

# The ladder's whole argument is the DIFFERENCE between two evaluations of the
# same text. Point both of them at the preprocessor and the difference is
# zero, which would read as a preprocessor that costs nothing -- so the
# ladder checks that the two sides produced different streams at all.
# Both sides pointed at the preprocessor: the macro axis then has a "lexed"
# point that is 4000 directive tokens short, which is what notices first.
mutate "harness: the memory ladder compares the preprocessor with itself" \
       "lexed point at 500 macros produced" \
       "sed -i 's@        if stage == \"lexed\":@        if False:@' memory.py" \
       "$memory_check"

mutate "harness: lcc's listing is no longer diffed against ours" \
       "is only 0 lines" \
       "sed -i 's@  rcc-rv32 < \"\$work/ir/\$name.i\" > \"\$work/ir/\$name.lcc\"@  : < \"\$work/ir/\$name.i\" > \"\$work/ir/\$name.lcc\"@' frontend.sh" \
       "$frontend_check"

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
declared=39
[ "${#names[@]}" -eq "$declared" ] || {
  echo "${#names[@]} mutations recorded, against the $declared this harness" >&2
  echo "declares. Either a mutate call has gone missing, or one was added" >&2
  echo "and the declared count was not raised with it." >&2; exit 1; }
echo "${#names[@]} mutations, each detected with its own distinct failure"
