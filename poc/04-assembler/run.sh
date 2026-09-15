#!/usr/bin/env bash
# The assembler PoC: items in, bytes out, every label resolved at layout time
# -- and then five independent ways of not believing it.
#
#   1. check.nix pins encodings, label ADDRESSES and section layouts, all
#      pure, and fails at evaluation time inside `nix flake check'.
#   2. Every program in progs/ is assembled by us AND by riscv32-none-elf-as,
#      linked at the same addresses, and the flat images are compared
#      byte-for-byte. Not a spot check: whole sections, padding included.
#   3. The same comparison on poc/03-matcher's REAL emitted output --
#      driver + runtime + compiled function, one translation unit, labels,
#      forward references, numeric local labels, an auipc pair to a .data
#      symbol and a call. That is the corpus task-003 handed forward.
#   4. That same image, assembled by us and not by binutils, is RUN in the Nix
#      RV32I emulator and its exit code checked against the number
#      poc/03-matcher/cases.nix writes down. With the differential this exact
#      it is not a strictly stronger oracle -- but it is the only stage with
#      no binutils anywhere in it, which is the path a `nix eval'-only
#      compiler has to take, and it is what task-004 extends.
#   5. must-fail.nix, messages.sh, and a mutation test over the assembler AND
#      the harness. A check that cannot fail is not a check.
#
# The ladder comes last and deliberately so: it is the only stage whose
# outcome depends on what else the machine is doing, and on a busy one it
# renders no verdict and exits 3.
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
command -v riscv32-none-elf-as >/dev/null || { echo "no riscv32-none-elf-as on PATH" >&2; exit 1; }

# --- 1. the pure checks ---------------------------------------------------
nix eval --impure --raw --expr "import $poc/check.nix { progs = $poc/progs; }"
nix eval --impure --raw --expr "(import $poc/must-fail.nix).summary"
bash "$poc/messages.sh" "$poc"

# --- 2 and 3. the differential against GNU as -----------------------------
# Every comparison goes through the same function, so a program added to
# progs/ and a function taken from poc/03-matcher are held to the same
# standard: the WHOLE image, ours against binutils'.
#
# -mno-relax and --no-relax throughout. With relaxation on, GNU shortens
# `call' to `jal' and `la' to `addi gp' after layout, which is a linker
# optimisation this assembler does not do; comparing against it would be
# comparing against a different program, not a different assembler.
#
# ld is told OUR .data base with -Tdata. That is a real limit on what this
# stage proves: if our dataBase were wrong, ld would be told the same wrong
# number and the images would still agree. Stage 4 is why that matters less
# than it sounds -- a wrong .data base moves the global the code loads.
assemble_ours() {          # $1 output dir, $2.. source .s files
  local out=$1; shift
  local paths=""
  for f in "$@"; do paths="$paths (/. + \"$f\")"; done
  nix eval --impure --json --expr "
    let a = import $poc/asm.nix { };
        p = import $poc/parse.nix { asm = a; };
        r = a.assemble { items = p.parseAll [$paths ]; };
    in { inherit (r) bytes dataBase textSize dataSize; }" > "$out/ours.json"
  python3 - "$out" <<'PY'
import json, sys
out = sys.argv[1]
r = json.load(open(f"{out}/ours.json"))
json.dump(r["bytes"], open(f"{out}/bytes.json", "w"))
# Hex with an 0x prefix: GNU ld's -Tdata reads a bare number as HEX, so
# passing 66048 put .data at 0x66048 and produced a 344 kB image.
open(f"{out}/database", "w").write("0x%x" % r["dataBase"])
PY
}

compare_with_gnu() {       # $1 name, $2 output dir, $3.. source .s files
  local name=$1 out=$2; shift 2
  cat "$@" > "$out/whole.s"
  riscv32-none-elf-as -march=rv32i -mno-relax -o "$out/whole.o" "$out/whole.s"
  riscv32-none-elf-ld --no-relax -Ttext=0x10000 -Tdata="$(cat "$out/database")" \
    -o "$out/whole.elf" "$out/whole.o" 2>/dev/null
  riscv32-none-elf-objcopy -O binary "$out/whole.elf" "$out/whole.bin"
  python3 "$poc/diff.py" "$out/bytes.json" "$out/whole.bin" "$name"
}

progs=()
for f in "$poc"/progs/*.s; do progs+=("$(basename "$f" .s)"); done
[ "${#progs[@]}" -ge 5 ] || {
  echo "only ${#progs[@]} programs in progs/ -- the differential corpus looks empty" >&2
  exit 1; }
for name in "${progs[@]}"; do
  mkdir -p "$work/progs/$name"
  assemble_ours "$work/progs/$name" "$poc/progs/$name.s"
  compare_with_gnu "$name" "$work/progs/$name" "$poc/progs/$name.s"
done
echo "${#progs[@]} programs in progs/ assembled identically to GNU as"

# --- 3. poc/03-matcher's real output --------------------------------------
matcher=$root/03-matcher
[ -f "$matcher/emit.nix" ] || { echo "no poc/03-matcher to take a corpus from" >&2; exit 1; }
cases=$(nix eval --impure --raw --expr \
  "builtins.concatStringsSep \" \" (map (c: c.name) (import $matcher/cases.nix).functions)")
[ -n "$cases" ] || { echo "poc/03-matcher/cases.nix lists no functions" >&2; exit 1; }

ran=0
for name in $cases; do
  out=$work/matcher/$name
  mkdir -p "$out"
  nix eval --impure --raw --expr \
    "((import $matcher/emit.nix { }).compile
       ((import $matcher/parse.nix).parse (builtins.readFile $matcher/ir/$name.sym))).asm" \
    > "$out/fn.s"
  [ -s "$out/fn.s" ] || { echo "$name: the matcher emitted nothing" >&2; exit 1; }
  assemble_ours "$out" "$matcher/drivers/$name.s" "$out/fn.s" "$matcher/runtime.s"
  compare_with_gnu "$name" "$out" "$matcher/drivers/$name.s" "$out/fn.s" "$matcher/runtime.s"

  # --- 4. run what WE assembled, with no binutils in the path -------------
  result=$(nix eval --impure --json --expr "
    let cpu = import (/. + \"$NIX_RISCV/rv32.nix\");
        bytes = builtins.fromJSON (builtins.readFile $out/bytes.json);
        final = cpu.run 200000 (cpu.load { inherit bytes; base = 65536; entry = 65536; });
    in { inherit (final) reason exitCode steps; }")
  want=$(nix eval --impure --raw --expr \
    "let c = builtins.head (builtins.filter (e: e.file == \"$name\")
       (import $matcher/cases.nix).execution); in toString c.expect")
  python3 - "$name" "$result" "$want" <<'PY'
import json, sys
name, got, want = sys.argv[1], json.loads(sys.argv[2]), int(sys.argv[3])
if got["reason"] != "exit":
    sys.exit(f"{name}: the emulator stopped with reason {got['reason']!r}, not a clean exit")
if got["steps"] < 10:
    sys.exit(f"{name}: the emulator ran {got['steps']} steps; nothing was executed")
if got["exitCode"] != want & 0xffffffff:
    sys.exit(f"{name}: our assembled program returned {got['exitCode']}, "
             f"poc/03-matcher/cases.nix expects {want}")
print(f"  {name}: ran in the Nix emulator, returned {got['exitCode']} in {got['steps']} steps")
PY
  ran=$((ran + 1))
done
[ "$ran" -ge 4 ] || { echo "only $ran matcher functions went through; the corpus looks empty" >&2; exit 1; }
echo "$ran of poc/03-matcher's functions assembled identically to GNU as and executed"

# --- the ladder's inputs, generated here and measured at the end ----------
# Generated now rather than in stage 6 because the mutation stage below needs
# them: a harness check on the ladder has to run the ladder.
#
# Sized against the evaluator's own start-up, not against taste. `nix eval' of
# an empty expression costs about 0.03 s CPU here and the shared guard wants a
# ladder point to cost at least three times that net of it. At 250 blocks the
# smallest point measured 0.132 s -- a net 0.097 s against a 0.105 s floor --
# and `just e2e' refused the ladder as unmeasurable, correctly, after several
# standalone runs had scraped past. 500 blocks measures 0.22 s, about 7x.
mkdir -p "$work/ladder"
ladder=()
for blocks in 500 1000 2000 4000; do
  python3 "$poc/ladder.py" "$blocks" "$work/ladder/$blocks.s"
  [ -s "$work/ladder/$blocks.s" ] || { echo "ladder.py produced nothing for $blocks" >&2; exit 1; }
  ladder+=("$work/ladder/$blocks.s")
done

# --- 5. mutation test -----------------------------------------------------
# Each mutation must make the suite fail, must produce its own fragment, and
# must produce NONE of the other fragments -- that last condition is what
# proves the checks distinguish rather than all collapsing into one alarm. The
# harness is mutated too.
#
# The mutated copy needs poc/01-encoder beside it, because asm.nix imports
# ../01-encoder/encode.nix, and poc/lib beside it, because scale.py imports the
# shared contention guard from its own parent's sibling.
mut=$work/poc/04-assembler
mkdir -p "$work/poc"
cp -r "$root/01-encoder" "$work/poc/01-encoder"
cp -r "$root/lib" "$work/poc/lib"

names=(); fragments=(); outputs=()

# $1 name, $2 fragment that must appear, $3 snippet that mutates $mut,
# $4 snippet that runs the mutated suite
mutate() {
  # A tmpfs of its own for every mutation, so no state can survive from the
  # last one -- by construction, rather than by a remove that has to have
  # worked. poc/lib/mutant.sh does the copy, the apply and the run inside it,
  # and hands back the mutated suite's own exit status.
  local out status=0
  out=$(bwrap --dev-bind / / --tmpfs "$mut" --die-with-parent -- \
        bash "$root/lib/mutant.sh" "$poc" "$mut" "$3" "$4" 2>&1) || status=$?
  case "$status" in
    120) echo "HARNESS FAULT: could not copy $poc for mutation '$1'" >&2; exit 1 ;;
    121) echo "HARNESS FAULT: mutation '$1' did not apply cleanly:" >&2
         echo "$out" >&2; exit 1 ;;
    122) echo "HARNESS FAULT: mutation '$1' changed nothing -- its pattern no longer matches" >&2
         exit 1 ;;
  esac
  if [ "$status" = 0 ]; then
    echo "MUTATION NOT DETECTED: '$1' still passed:" >&2
    echo "$out" >&2
    exit 1
  fi
  names+=("$1"); fragments+=("$2"); outputs+=("$out")
}

pure_check="nix eval --impure --raw --expr \"import $mut/check.nix { progs = $mut/progs; }\""
must_fail="nix eval --impure --raw --expr '(import $mut/must-fail.nix).summary'"

# The differential, on ONE program, against a mutated assembler. `data' is the
# program that carries alignment padding and a symbol-valued .word, so it is
# the one whose bytes move for the mutations the pure checks cannot see. It
# runs the MUTATED diff.py, so that breaking the comparison is itself testable.
# Exported, and $mut with it, because mutate() now runs each mutation in a
# child bash inside a mount namespace of its own -- so a function defined here
# is not in scope there unless it is put in the environment.
gnu_diff() {
  local name=$1
  # Under $mut, which is a tmpfs created fresh for this one mutation: nothing
  # from a previous differential can be in it, and nothing from this one
  # outlives the process.
  local out=$mut/gnu-diff-$name
  mkdir -p "$out"
  nix eval --impure --json --expr "
    let a = import $mut/asm.nix { };
        p = import $mut/parse.nix { asm = a; };
        r = a.assemble { items = p.parseFile (/. + \"$mut/progs/$name.s\"); };
    in { inherit (r) bytes dataBase; }" > "$out/ours.json"
  python3 - "$out" <<'PYEOF'
import json, sys
out = sys.argv[1]
r = json.load(open(f"{out}/ours.json"))
json.dump(r["bytes"], open(f"{out}/bytes.json", "w"))
# Hex with an 0x prefix: GNU ld's -Tdata reads a bare number as HEX, so
# passing 66048 put .data at 0x66048 and produced a 344 kB image.
open(f"{out}/database", "w").write("0x%x" % r["dataBase"])
PYEOF
  riscv32-none-elf-as -march=rv32i -mno-relax -o "$out/whole.o" "$mut/progs/$name.s"
  riscv32-none-elf-ld --no-relax -Ttext=0x10000 -Tdata="$(cat "$out/database")" \
    -o "$out/whole.elf" "$out/whole.o" 2>/dev/null
  riscv32-none-elf-objcopy -O binary "$out/whole.elf" "$out/whole.bin"
  python3 "$mut/diff.py" "$out/bytes.json" "$out/whole.bin" "$name"
}
export -f gnu_diff
export mut
diff_check="gnu_diff data"

# --- the assembler ---
mutate "asm: the PC-relative base is the next instruction, not the branch's own" \
       "offset 0: branches to itself" \
       "sed -i 's@          pc = addrAt i;@          pc = addrAt i + 4;@' asm.nix" \
       "$pure_check"

mutate "asm: the lui/addi split drops the +0x800 correction" \
       "without +0x800 this would be hi=0" \
       "sed -i 's@hi = b.bitAnd ((u + 2048) / 4096) 1048575;@hi = b.bitAnd (u / 4096) 1048575;@' asm.nix" \
       "$pure_check"

mutate "asm: the lui/addi split drops the 20-bit fold the correction carries out of" \
       "the correction carries into bit 32" \
       "sed -i 's@hi = b.bitAnd ((u + 2048) / 4096) 1048575;@hi = (u + 2048) / 4096;@' asm.nix" \
       "$pure_check"

mutate "asm: li always uses lui+addi, so a value addi alone holds costs two" \
       "0x7ff: the largest that addi alone holds" \
       "sed -i 's@    if s >= -2048 && s <= 2047 then@    if false then@' asm.nix" \
       "$pure_check"

# The one genuinely variable-length instruction: if its length and its
# encoding stop coming from the same helper, address assignment and the bytes
# disagree, and every address after it is wrong.
mutate "asm: li is sized as one word however many it encodes to" \
       "was placed as 4 bytes but encoded to 8" \
       "sed -i 's@      n = a: b.length (liParts (a0 a) (a1 a));@      n = _: 1;@' asm.nix" \
       "$pure_check"

mutate "asm: the swapping pseudo-branches stop swapping their operands" \
       "bge with the operands reversed" \
       'sed -i "s@encode.bge (a1 a) (a0 a) (ctx.branchOff (a2 a))@encode.bge (a0 a) (a1 a) (ctx.branchOff (a2 a))@" asm.nix' \
       "$pure_check"

mutate "asm: the auipc pair measures its delta from the wrong instruction" \
       "delta 0: addi 0, from the auipc's pc" \
       "sed -i 's@        let hl = hiLo (ctx.pcrel (a1 a)); in@        let hl = hiLo (ctx.pcrel (a1 a) - 4); in@' asm.nix" \
       "$pure_check"

mutate "asm: a section is not padded out to its own alignment" \
       ".text is 44 bytes, expected 48" \
       "sed -i 's@      textSize = alignUp final.textOff final.textAlign;@      textSize = final.textOff;@' asm.nix" \
       "$pure_check"

# Checked through messages.sh, not must-fail.nix, and the difference is the
# point: the encoder's own `fits "B-imm"' still throws when this guard is
# removed, so the branch is never MIScompiled either way. What is lost is the
# diagnostic -- which label, how far, and what to do about it -- and a
# refusal whose whole value is its message has to be tested on its message.
mutate "asm: an out-of-range branch loses its diagnostic and falls through to the encoder" \
       "'a branch four bytes past the forward limit' threw, but the message does not contain" \
       "sed -i 's@            if d < -4096 || d > 4094 then@            if d < -99999999 || d > 99999999 then@' asm.nix" \
       "bash $mut/messages.sh $mut"

# --- symbol expressions (task-023) ---
# `msg+8' is one operand with two halves, and every one of these breaks a
# different half while the other still works -- which is what makes them
# distinguishable rather than four spellings of "the offset is wrong".
mutate "asm: a symbol expression's displacement is dropped" \
       "\`tbl+8' (the third word of tbl)" \
       "sed -i 's@then -mag else mag;@then 0 else 0;@' asm.nix" \
       "$pure_check"

mutate "asm: a symbol expression's sign is ignored, so sym-N means sym+N" \
       "\`tbl-4' (backwards, which is" \
       "sed -i 's@then -mag else mag;@then mag else mag;@' asm.nix" \
       "$pure_check"

# The feature itself, taken back out: `tbl+8' stops being an expression and
# becomes a symbol nothing defines, which is exactly the refusal task-023
# started from.
#
# Say what is NOT aimed at here: `symexprWords', the fourteen pinned
# encodings. Every mutation that would move those words also moves an address
# in `symbolExpressions', which check.nix reports first and deliberately so --
# a wrong base explains a wrong encoding and not the other way round. So that
# table is carried by the address pins beside it and by the byte-for-byte
# differential against GNU as above, not by a mutation of its own.
mutate "asm: symbol expressions are not recognised at all, as before task-023" \
       "was asked for the address of \`tbl+8'" \
       "sed -i 's@        if m == null then null@        if true then null@' asm.nix" \
       "$pure_check"

mutate "asm: a name that is both a label and an expression is resolved silently" \
       "assembled fine: an operand that is both a label this unit defines" \
       "sed -i 's@        if whole != null && expr != null && whole != expr then@        if false then@' asm.nix" \
       "$must_fail"

mutate "asm: a leading-zero displacement is read as decimal instead of refused" \
       "assembled fine: a leading-zero displacement" \
       "sed -i 's@        else if e.leadingZero then@        else if false then@' asm.nix" \
       "$must_fail"

# The range diagnostics report the target's ADDRESS. Reading it out of
# `symbols' answers for a plain label and not for an expression, so only a
# case whose target IS an expression can see this, and only messages.sh can
# see that the message stopped naming the right address. The mutation defaults
# to zero rather than letting the lookup fail, because an `attribute missing'
# is not a message this project wrote and matching on it would be matching on
# nix's internals.
mutate "asm: an out-of-range diagnostic reads the target address out of the symbol table" \
       "'a branch out of range whose target is a symbol expression' threw, but the message does not contain" \
       "sed -i 's@(lookup where \"branches to\" sym)@(symbols.\${sym} or 0)@' asm.nix" \
       "bash $mut/messages.sh $mut"

# The refusal's whole value is that it names the BASE. Removing the clause
# leaves a refusal that is still a refusal, so only messages.sh sees it.
mutate "asm: an undefined base is reported as the whole expression" \
       "'a symbol expression whose base symbol nothing defines' threw, but the message does not contain" \
       "sed -i 's@            + (if e != null then@            + (if false then@' asm.nix" \
       "bash $mut/messages.sh $mut"

mutate "parse: a symbol expression in .data is refused by the text front end" \
       "is neither a number nor a symbol" \
       "sed -i 's@-+A-Za-z0-9@-A-Za-z0-9@' parse.nix" \
       "$pure_check"

mutate "asm: a label defined twice is accepted" \
       "assembled fine: the same label defined twice" \
       "sed -i 's@    else if duplicated != \[ \] then@    else if false then@' asm.nix" \
       "$must_fail"

# Only the differential sees this one: padding bytes are not instructions, so
# no encoding assertion looks at them, and GNU as puts nops there.
mutate "asm: alignment padding in a code section is zero-filled" \
       "differs from GNU as at byte" \
       "sed -i 's@    if sec != @    if true || sec != @' asm.nix" \
       "$diff_check"

# --- the harness ---
mutate "harness: the PC-relative word table is emptied" \
       "the PC-relative word table has 0 entries" \
       "sed -i 's@^  pcrelWords = \[@  pcrelWords = [ ]; unusedPcrelWords = [@' cases.nix" \
       "$pure_check"

mutate "harness: the li table is emptied" \
       "the li table has 0 cases" \
       "sed -i 's@^  liCases = \[@  liCases = [ ]; unusedLiCases = [@' cases.nix" \
       "$pure_check"

mutate "harness: the symbol-expression address table is emptied" \
       "symbol-expression address table has 0 entries" \
       "sed -i 's@^  symbolExpressions = \[@  symbolExpressions = [ ]; unusedSymbolExpressions = [@' cases.nix" \
       "$pure_check"

mutate "harness: the symbol-expression word table is emptied" \
       "symbol-expression word table has 0 entries" \
       "sed -i 's@^  symexprWords = \[@  symexprWords = [ ]; unusedSymexprWords = [@' cases.nix" \
       "$pure_check"

mutate "harness: the label-address table is emptied" \
       "the symbol-address table has 0 entries" \
       "sed -i 's@^  symbols = \[@  symbols = [ ]; unusedSymbols = [@' cases.nix" \
       "$pure_check"

mutate "harness: a mnemonic loses its only occurrence in the corpus" \
       "implemented but never assembled by progs/" \
       "sed -i '/fence/d' progs/pseudo.s" \
       "$pure_check"

mutate "harness: the must-fail control cases are dropped" \
       "must-fail tables shrank" \
       "sed -i 's@^  controls = \[@  controls = [ ]; unusedControls = [@' must-fail.nix" \
       "$must_fail"

# The ladder is a harness too, and a harness that measures the wrong input
# reports a number about nothing. Run against the real ladder, but it faults
# on the first point, so it costs one evaluation rather than twenty.
scale_check="python3 $mut/scale.py $mut ${ladder[0]} ${ladder[1]} ${ladder[2]} ${ladder[3]}"

mutate "harness: the ladder measures something other than the file it reports" \
       "but the file is" \
       "sed -i 's@  text = b.readFile (/. + path);@  text = \"\\tnop\\n\";@' bench.nix" \
       "$scale_check"

mutate "harness: the differential is handed an empty image" \
       "we produced only 0 bytes" \
       "sed -i 's@        ours = json.load(fh)@        ours = json.load(fh)[:0]@' diff.py" \
       "$diff_check"

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
echo "${#names[@]} mutations, each detected with its own failure"

# --- 6. the ladder --------------------------------------------------------
# Last, because this is the one stage whose outcome depends on what else the
# machine is doing. On a busy one it renders no verdict and exits 3, which
# under `set -e' would take every check after it down with it -- so there are
# none after it.
# The guard measures, and it refuses in both directions; poc/lib/selftest.py
# is what proves it MEASURES, and poc/03-matcher/run.sh is what proves it
# DECIDES symmetrically. Neither is repeated here -- one copy of a check is
# the point of poc/lib -- but the self-test is cheap and catches a guard that
# has stopped seeing load at all, which would silently make this ladder's
# verdict meaningless.
python3 "$root/lib/selftest.py" "$work"

status=0
python3 "$poc/scale.py" "$poc" "${ladder[@]}" || status=$?
if [ "$status" = 3 ]; then
  echo "NO VERDICT: this machine was too busy for the ladder to measure on." >&2
  echo "Everything above this line ran and passed; nothing about the assembler's" >&2
  echo "linearity was shown either way. Re-run on an idle machine for that." >&2
fi
[ "$status" = 0 ] || exit "$status"

