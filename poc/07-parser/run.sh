#!/usr/bin/env bash
# The C parser and DAG builder PoC: slice 1 of decision-007.
#
# What this proves, in the order the stages run:
#
#   1. check.nix -- every corpus listing is accepted by poc/03-matcher's own
#      listing parser, which re-checks node numbering, reference counts,
#      post-order and dangling `#n' from the CONSUMER's side; the corpus
#      produces exactly the declared set of opcodes; a discarded call is still
#      a listed root nothing references; and three C programs COMPILE FROM .c
#      AND RUN on the Nix RV32I emulator, printing what cases.nix independently
#      computes.
#   2. must-fail.nix -- the C outside slice 1 is refused, each reject paired
#      with a control that must still compile, so a frontend that threw on
#      everything could not pass.
#   3. messages.sh -- and each refusal says what it promised to say, which
#      builtins.tryEval cannot check because it discards the message.
#   4. oracle.py -- the listing AND lcc's stderr, diffed byte for byte against
#      rcc-rv32 over the whole corpus. This is criteria #2, #3 and #7.
#   5. memory.py -- what a source line costs with tokens, trees, dag nodes and
#      symbols all live, which decision-001 says is the constraint that decides
#      whether any of this scales.
#   6. A mutation test over the frontend AND this harness. This project has
#      shipped seven suites that reported success while verifying nothing, so
#      every check above is assumed broken until a mutation proves otherwise.
#
# NO TIMING LADDER, and so no contention self-test and no NO VERDICT path. The
# question this PoC has to answer about cost is a ceiling on peak RSS, not a
# ratio between two readings, and decision-008's argument is about ratios. The
# contention figure is printed by memory.py anyway so that a reading taken on a
# loaded machine does not log identically to one taken on an idle one.
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
: "${NIX_RISCV:?NIX_RISCV is unset -- run this inside nix develop}"

cpu="import (/. + \"$NIX_RISCV/rv32.nix\")"

# --- 1. the listings, the opcode population and three running programs ----
nix eval --impure --raw --expr "import $poc/check.nix { cpu = $cpu; }"

# --- 2. what is refused, and the controls that must still compile ---------
nix eval --impure --raw --expr "(import $poc/must-fail.nix).summary"

# --- 3. and what each refusal says ---------------------------------------
bash "$poc/messages.sh" "$poc"

# --- 4. the differential against lcc, IR and stderr alike ------------------
# Its own script, so that a mutation can reach it: a shell function defined
# here would be out of scope inside the mount namespace each mutation runs in.
python3 "$poc/oracle.py" "$poc"

# --- 5. what a source line costs ------------------------------------------
python3 "$poc/memory.py" "$poc"

# --- 6. mutation test ------------------------------------------------------
# Each mutation must make the suite fail, must produce its own fragment, and
# must produce NONE of the other fragments. That last condition is what proves
# the checks are distinguishing rather than all collapsing into one alarm.
#
# The mutated copy needs its sibling PoCs beside it: compile.nix reaches
# ../02-lexer for the token stream, ../06-constants for the constant evaluator
# and ../03-matcher for the listing parser; demo.nix reaches ../03-matcher,
# ../04-assembler and ../05-loop; and the assembler in turn reaches
# ../01-encoder. They are symlinked rather than copied --
# they are not what is being mutated, and a copy is a copy that could go stale.
mut=$work/poc/07-parser
mkdir -p "$work/poc"
for d in 01-encoder 02-lexer 03-matcher 04-assembler 05-loop 06-constants lib; do
  ln -s "$root/$d" "$work/poc/$d"
done

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

check="nix eval --impure --raw --expr 'import $mut/check.nix { cpu = $cpu; }'"
must_fail="nix eval --impure --raw --expr '(import $mut/must-fail.nix).summary'"
messages="bash $mut/messages.sh $mut"
oracle="python3 $mut/oracle.py $mut"
memory="python3 $mut/memory.py $mut"

# --- mutations of the frontend -------------------------------------------
# THE ONE CRITERION #3 RESTS ON. Start the per-forest node counter at one
# instead of zero and every node number shifts by one, while the opcodes, the
# operands and the shape of every tree stay exactly as they were. An
# opcode-only diff sees two identical listings. This is the mutation that says
# the numbering is in the comparison.
mutate "frontend: node numbering starts at one instead of zero" \
       "we  \"2' ASGNI4 #3 #4 4 4\"" \
       "sed -i 's|start = { s = s0; order = \[ \]; n = 0; };|start = { s = s0; order = [ ]; n = 1; };|' dag.nix" \
       "$oracle"

# And its partner: keep the numbering and drop the back-references. Same
# argument, other half of criterion #3.
mutate "frontend: a node stops printing the kids it refers to" \
       "we  \"1' ASGNI4 4 4\"" \
       "sed -i 's|kids = b.concatStringsSep \"\"|kids = \"\"; unusedKids = b.concatStringsSep \"\"|' listing.nix" \
       "$oracle"

# Common subexpression elimination is what makes `count=' mean anything. With
# node() always building a fresh node, `2. ADDRLP4 count=2 x' becomes two
# separate nodes and everything after it renumbers.
mutate "frontend: the dag stops sharing common subexpressions" \
       "lcc '2. INDIRI4 count=2 #3'" \
       "sed -i 's|if s.buckets ? \${key} then { inherit s; v = s.buckets.\${key}; }|if false then { inherit s; v = 0; }|' dag.nix" \
       "$oracle"

# A conversion's DESTINATION width is in the opcode and its SOURCE width is the
# node's first symbol. Drop the symbol and CVUI4 from an int and CVUI4 from a
# char become indistinguishable -- which is the trap the task-023/024/025 batch
# carried forward.
mutate "frontend: a conversion node loses its source width" \
       "we  '2. CVUI4 #3'" \
       "sed -i 's|node c.s op a.v null c.v|node c.s op a.v null null|' dag.nix" \
       "$oracle"

# lcc INVERTS a comparison whose branch is taken when it is false. Leave `<' as
# LTI4 where lcc emits GEI4 and every conditional in the corpus is wrong,
# silently, in a way the program would still run.
mutate "frontend: a false-label branch stops inverting its comparison" \
       "we  \"4' LTI4 #5 #7 2\"" \
       "sed -i 's|flip = { EQ = \"NE\"; NE = \"EQ\"; GT = \"LE\"; LT = \"GE\"; GE = \"LT\"; LE = \"GT\"; };|flip = { EQ = \"EQ\"; NE = \"NE\"; GT = \"GT\"; LT = \"LT\"; GE = \"GE\"; LE = \"LE\"; };|' dag.nix" \
       "$oracle"

# Forests span statements: stmt.c only flushes when nodecount is zero or over
# two hundred. Flush after every statement and the numbering restarts in the
# middle of what lcc keeps as one forest.
mutate "frontend: every statement gets a forest of its own" \
       "we  ' 2. ADDRLP4 count=2 x'" \
       "sed -i 's|if l.s.nodecount == 0 \|\| l.s.nodecount > 200|if true|' parse.nix" \
       "$oracle"

# simp.c folds 3 + 4 before the dag ever sees it.
mutate "frontend: constant addition stops folding" \
       "we  '4. CNSTI4 count=3 3'" \
       "sed -i 's|\"ADD+I\" = chain (ops.mk \"ADD\" \"I\") \[ (xfold addi (x: y: x + y)) swapRight (idR \"I\" 0) \];|\"ADD+I\" = chain (ops.mk \"ADD\" \"I\") [ swapRight (idR \"I\" 0) ];|' simp.nix" \
       "$oracle"

# ...and rewrites a multiply by a power of two into a shift.
mutate "frontend: multiplying by a power of two stops becoming a shift" \
       "we  '7. MULI4 #8 #9'" \
       "sed -i 's|if isCnst s l \"I\" \&\& cval s l > 0 \&\& ispow2 (cval s l) != 0|if false|' simp.nix" \
       "$oracle"

# A parameter read three times becomes a register, which changes whether lcc
# copies it on entry -- so this moves whole forests, not just a word.
mutate "frontend: a parameter is never promoted to a register" \
       "we  'callee a type=int sclass=auto scope=PARAM flags=0 offset=0 ref=4.000000'" \
       "sed -i 's|\&\& !r.addressed \&\& ty.isscalar r.type \&\& r.ref >= 3.0|\&\& !r.addressed \&\& ty.isscalar r.type \&\& r.ref >= 3000.0|' parse.nix" \
       "$oracle"

# The locals are laid out in reference-count order, and that order IS the frame
# layout: symbolic.c assigns offsets as it prints them.
mutate "frontend: the locals stop being sorted by reference count" \
       "lcc 'local hot type=int sclass=register scope=LOCAL flags=0 offset=0 ref=32.000000'" \
       "sed -i 's|sorted = sortByRef s10 locals nregs;|sorted = locals;|' parse.nix" \
       "$oracle"

# THE ONE CRITERION #7 RESTS ON. task-011 left the constant evaluator
# returning a `warnings' list that nothing printed. A parser that drops it
# compiles a silently clamped constant, and every other check here stays green.
mutate "frontend: diagnostics are recorded and never reported" \
       "lcc says:  '13: warning: result of unsigned comparison is constant" \
       "sed -i 's|^  warn = s: text: s // {|  warn = s: _text: s // {|;s|diags = s.diags ++ \[ { inherit (s) line; text = \"warning: \" + text; } \];|diags = s.diags;|' sym.nix" \
       "$oracle"

# lcc copies a parameter on entry when the callee symbol differs from the
# caller symbol. Skip it and the function is short one whole forest.
mutate "frontend: a register parameter is not copied in on entry" \
       "we  ' 2. ADDRLP4 n'" \
       "sed -i 's|if ps.sclass != qs.sclass \|\| ps.type != qs.type then|if false then|' listing.nix" \
       "$oracle"

# `j = i++' lists the load as a forest root of its own, which is dag.c's RIGHT
# special case and the one place a pointer comparison in lcc is on the INDIR's
# KID rather than on the INDIR.
mutate "frontend: the postfix-increment load stops being a listed root" \
       "lcc \"12' INDIRI4 count=2 #2\"" \
       "sed -i 's|\&\& tr.gen s0 k0 == \"INDIR\" \&\& tr.kid s0 k0 0 == tr.kid s0 k1 0|\&\& false|' dag.nix" \
       "$oracle"

# foldcond removes the entry test of a counted for-loop. Without it the listing
# carries a jump and a label lcc does not emit.
mutate "frontend: a counted for-loop keeps its entry test" \
       "we  ' 2. ADDRGP4 10'" \
       "sed -i 's|    if !ok1 then { s = s0; v = 0; }|    if true then { s = s0; v = 0; }|' parse.nix" \
       "$oracle"

# A float constant has to be REFUSED, with the decision and the task named --
# decision-006 says a frontend that quietly accepts `double' is worse than one
# that refuses it.
mutate "frontend: a floating constant is quietly accepted" \
       "should have been refused but compiled fine: a floating constant" \
       "sed -i 's|^    else if k == \"FCON\" then|    else if k == \"FCON\" then (let c = tr.cnsttree s0 ty.inttype 0; in { s = advance c.s; v = c.v; }) else if false then|' parse.nix" \
       "$must_fail"

# ...and the refusal has to keep SAYING so. task-011 handed this slice the
# question of how a Nix throw carries a source position; the answer taken was
# that the parser throws at the site that knows the token.
mutate "frontend: the float refusal stops naming the decision behind it" \
       "the message does not contain" \
       "sed -i 's|decision-006, task-015|a later wave|' parse.nix" \
       "$messages"

# A program that compiles to correct IR and then runs wrong is the class of
# defect an IR diff cannot see, which is why decision-007 makes every slice
# run something.
mutate "frontend: the emitted listing is correct but the program misbehaves" \
       "wanted \`55" \
       "sed -i 's|(it.insn \"li\" \[ \"a0\" arg \])|(it.insn \"li\" [ \"a0\" (arg - 1) ])|' demo.nix" \
       "$check"

# `const int c = 7;' only compiles because enode.c's asgn() strips the
# qualifier off the symbol's type around the assignment -- asgntree() refuses
# an assignment to a const identifier, and an initialiser is one.
mutate "frontend: a const local with an initialiser is refused" \
       "assignment to const identifier" \
       "sed -i 's|s1 = sy.modsym s0 p (q: q // { type = ty.unqual q.type; });|s1 = s0;|' trees.nix" \
       "$oracle"

# A volatile load is built with newnode rather than node, so two reads of the
# same volatile object stay two dag nodes. Nothing but the listing shows it.
mutate "frontend: a volatile load is common-subexpression-eliminated" \
       "we  '7. ADDI4 #8 #8'" \
       "sed -i 's|if ty.isvolatile kty then newnode a.s op a.v null null|if false then newnode a.s op a.v null null|' dag.nix" \
       "$oracle"

# --- mutations of the harness ---------------------------------------------
# The one that matters most: with lcc replaced by `cat', the oracle's input
# comes back as its own output and no node line is in it. A differential that
# would still pass with the reference removed is not a differential.
mutate "harness: the oracle stops consulting lcc at all" \
       "this form was never compared" \
       "sed -i 's|^ORACLE = \"rcc-rv32\"|ORACLE = \"cat\"|' oracle.py" \
       "$oracle"

mutate "harness: the oracle stops reading lcc's stderr" \
       "diagnostic lines were compared" \
       "sed -i 's|want, want_err = run.stdout, run.stderr|want, want_err = run.stdout, \"\"|' oracle.py" \
       "$oracle"

mutate "harness: the corpus is emptied" \
       "the corpus holds 0 files" \
       "sed -i 's|^  corpus = \[|  corpus = [ ]; unusedCorpus = [|' cases.nix" \
       "$check"

mutate "harness: the declared opcode population is emptied" \
       "which cases.nix does not declare" \
       "sed -i 's|^  opcodes = \[|  opcodes = [ ]; unusedOpcodes = [|' cases.nix" \
       "$check"

mutate "harness: the expected program output stops being computed" \
       "printed \`55" \
       "sed -i 's|^  sumTo = n: b.foldl|  sumTo = _: 999; unusedSumTo = n: b.foldl|' cases.nix" \
       "$check"

mutate "harness: the reject table is emptied" \
       "must-fail tables hold 0 rejects" \
       "sed -i 's|^  rejects = \[|  rejects = [ ]; unusedRejects = [|' must-fail.nix" \
       "$must_fail"

mutate "harness: the memory ladder is shrunk below where it measures anything" \
       "measuring an evaluation that compiled nothing" \
       "sed -i 's|^SIZES = \[8, 32, 128\]|SIZES = [1]|' memory.py" \
       "$memory"

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
declared=26
[ "${#names[@]}" -eq "$declared" ] || {
  echo "${#names[@]} mutations recorded, against the $declared this harness" >&2
  echo "declares. Either a mutate call has gone missing, or one was added" >&2
  echo "and the declared count was not raised with it." >&2; exit 1; }
echo "${#names[@]} mutations, each detected with its own distinct failure"
