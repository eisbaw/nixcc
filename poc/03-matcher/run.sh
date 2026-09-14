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
cd "$(dirname "$0")"
poc=$PWD
work=$(mktemp -d)
keep=1                       # artifacts are kept unless we reach a clean pass
cleanup() {
  if [ "$keep" = 1 ]; then echo "artifacts kept in $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT

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
build_and_run() {
  local src=$1
  local name=$2
  local out
  out=$work/$(basename "$src")-$name
  mkdir -p "$out"
  nix eval --impure --raw --expr \
    "((import $src/emit.nix { }).compile
       ((import $src/parse.nix).parse (builtins.readFile $src/ir/$name.sym))).asm" \
    > "$out/$name.s"
  [ -s "$out/$name.s" ] || { echo "$name: the matcher emitted nothing" >&2; return 1; }

  riscv32-none-elf-as -march=rv32i -o "$out/fn.o" "$out/$name.s"
  riscv32-none-elf-as -march=rv32i -o "$out/rt.o" "$src/runtime.s"
  riscv32-none-elf-as -march=rv32i -o "$out/drv.o" "$src/drivers/$name.s"
  riscv32-none-elf-ld -Ttext=0x10000 -o "$out/prog.elf" "$out/drv.o" "$out/rt.o" "$out/fn.o" 2>/dev/null
  riscv32-none-elf-objcopy -O binary "$out/prog.elf" "$out/prog.bin"

  # The assembler is allowed to reject nothing silently: if it had produced an
  # empty .text the emulator would fault rather than pass, but say so here.
  local insns
  insns=$(riscv32-none-elf-objdump -d "$out/fn.o" | grep -cE '^\s+[0-9a-f]+:') || true
  [ "${insns:-0}" -ge 5 ] || {
    echo "$name: only ${insns:-0} instructions in the assembled object" >&2; return 1; }

  python3 -c "import json,sys; json.dump(list(open(sys.argv[1],'rb').read()), open(sys.argv[2],'w'))" \
    "$out/prog.bin" "$out/prog.json"

  nix eval --impure --json --expr "
    let cpu = import (/. + \"$NIX_RISCV/rv32.nix\");
        bytes = builtins.fromJSON (builtins.readFile $out/prog.json);
        final = cpu.run 200000 (cpu.load { inherit bytes; base = 65536; entry = 65536; });
    in { inherit (final) halted reason exitCode steps; insns = $insns; }"
}

for name in $cases; do
  result=$(build_and_run "$poc" "$name")
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

# --- 4. scale --------------------------------------------------------------
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
python3 "$poc/scale.py" "$poc" "${ladder[@]}"

# --- 5. mutation test ------------------------------------------------------
# Each mutation must make the suite fail, must produce its own fragment, and
# must produce NONE of the other fragments. That last condition is what proves
# the checks distinguish rather than all collapsing into one alarm. The
# harness is mutated too: a check that cannot fail is not a check.
mut=$work/mut
names=(); fragments=(); outputs=()

# $1 name, $2 fragment that must appear, $3 shell snippet that mutates $mut,
# $4 shell snippet that runs the mutated suite
mutate() {
  rm -rf "$mut"; cp -r "$poc" "$mut"
  ( cd "$mut" && eval "$3" )
  # A sed whose pattern no longer matches edits nothing and the suite then
  # passes, which reads as "not detected" when the truth is "not applied".
  # Renaming a binding in the code under test is enough to cause it.
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
       "should have been refused but compiled fine" \
       "sed -i 's|^else if deadNt != \[ \] then|else if false then|' burg.nix" \
       "$must_fail"

mutate "matcher: diagnostics lose their detail" \
       "the message does not contain" \
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
rm -rf "$mut"; cp -r "$poc" "$mut"
sed -i 's|mv a0,%0\\nmv a1,%1\\ncall __divsi3|mv a0,%0\\nmv a1,%0\\ncall __divsi3|' "$mut/rules.nix"
grep -q 'mv a1,%0' "$mut/rules.nix" || {
  echo "the divide-by-itself mutation did not apply; rules.nix has changed shape" >&2; exit 1; }
if ! eval "$matcher_check" >/dev/null 2>&1; then
  echo "the divide-by-itself mutation was caught by check.nix, so it no longer" >&2
  echo "demonstrates that the execution stage catches what the pure checks cannot" >&2
  exit 1
fi
broken=$(build_and_run "$mut" expr)
got=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["exitCode"])' "$broken")
[ "$got" != 72 ] || {
  echo "MUTATION NOT DETECTED: the divide libcall divides x by itself and the" >&2
  echo "emulator still returned 72; the execution stage is measuring nothing" >&2; exit 1; }
echo "  mutation detected: matcher: the divide libcall divides x by itself" \
     "(execution only -- check.nix passed it, the emulator returned $got not 72)"

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

keep=0
