#!/usr/bin/env bash
# Criterion #3: the linemarkers this preprocessor emits are in the form lcc's
# input.c resynch() expects, so a C frontend consumes our output unchanged.
#
# WHY THIS IS NOT A TABLE OF EXPECTED TEXT. Nothing in this tree reads a
# linemarker: poc/07-parser carries the line number on the token and never
# sees a `#', and poc/03-matcher's listing parser treats every non-forest line
# as directive noise. So an emitter checked only against a string in a Nix
# table would be a rule describing itself -- task-053's finding, which existed
# because poc/03-matcher had three tables asserting what a rule EMITS and none
# asserting that anything ever CHOSE it.
#
# The consumer is therefore a real one. `rcc-rv32' is lcc's own frontend, the
# oracle this project already diffs against, and resynch() is the code
# decision-005 quotes. Fed our rendered output, rcc reports its diagnostics at
# the file and line the `#line' asked for -- or it does not, and that is a
# fact about lcc rather than about a table we wrote.
#
# TWO STAGES, and the second is the stronger:
#
#   1. DIAGNOSTIC POSITIONS. A stray `;' at file scope makes rcc warn "empty
#      declaration", and where it says that warning came from is the whole
#      answer. Each case moves it somewhere different.
#
#   2. THE WHOLE LISTING. For each program under run/, the IR lcc produces
#      from OUR preprocessed text is compared byte for byte with the IR our
#      own frontend produces from OUR token stream. Those are the two halves
#      of "the frontend consumes the output unchanged": lcc reads what we
#      wrote, and reads it as the same program we did.
#
#   frontend.sh POC_DIR WORK_DIR
set -euo pipefail
poc=${1:?usage: frontend.sh POC_DIR WORK_DIR}
work=${2:?usage: frontend.sh POC_DIR WORK_DIR}

command -v rcc-rv32 >/dev/null 2>&1 || {
  echo "no \`rcc-rv32' on PATH. This stage needs lcc's own frontend, which is" >&2
  echo "the only consumer of a linemarker in reach. Run inside \`nix develop'." >&2
  exit 2; }

render() {  # render FILE NAME
  nix eval --impure --raw --expr \
    "let c = import $poc/cpp.nix;
     in c.render (c.preprocess { src = builtins.readFile $1; file = \"$2\"; })"
}

# --- 1. where rcc says its diagnostics came from -------------------------
# Every case puts the same warning somewhere else, so a linemarker that was
# emitted at the wrong moment, with the wrong number or with no file name
# changes the answer rather than merely the wording.
names=(); sources=(); expects=()
add() { names+=("$1"); sources+=("$2"); expects+=("$3"); }

add "no directive at all: the file's own name and line" \
    'int f(void){ return 0; }
;
' \
    "one.c:2: warning: empty declaration"

add "a directive line is consumed, and the gap it leaves is closed" \
    '#define X 1
int f(void){ return X; }
;
' \
    "one.c:3: warning: empty declaration"

add "#line moves both the number and the file" \
    'int f(void){ return 0; }
#line 500 "zz.c"
;
' \
    "zz.c:500: warning: empty declaration"

add "the bare linemarker spelling resynch() reads" \
    'int f(void){ return 0; }
# 42 "in.c"
;
' \
    "in.c:42: warning: empty declaration"

add "a skipped group leaves a gap of its own" \
    '#if 0
int gone(void){ return 1; }
int also(void){ return 2; }
#endif
;
' \
    "one.c:5: warning: empty declaration"

add "a logical line spanning two physical ones still lands on the right line" \
    'int f(void){ return 1 + \
   2 + \
   3; }
;
' \
    "one.c:4: warning: empty declaration"

declared_positions=6
[ "${#names[@]}" -eq "$declared_positions" ] || {
  echo "${#names[@]} linemarker position cases, against the $declared_positions" >&2
  echo "this stage declares. Either one went missing or one was added without" >&2
  echo "raising the number." >&2; exit 1; }

# A fragment shared by two cases cannot tell them apart -- must-fail.nix makes
# the same check about its own diagnostics, for the same reason.
for i in "${!expects[@]}"; do
  for j in "${!expects[@]}"; do
    [ "$i" = "$j" ] && continue
    [ "${expects[$i]}" != "${expects[$j]}" ] || {
      echo "cases '${names[$i]}' and '${names[$j]}' expect the same text," >&2
      echo "so neither can tell itself from the other" >&2; exit 1; }
  done
done

mkdir "$work/lm"
for i in "${!names[@]}"; do
  printf '%s' "${sources[$i]}" > "$work/lm/one.c"
  render "$work/lm/one.c" "one.c" > "$work/lm/one.i"
  # rcc warns and carries on, so a non-zero status here means it could not
  # READ what we produced, which is a different and worse failure.
  # stderr to its own file: `> out 2>&1' would send the diagnostics INTO the
  # listing, and the check would then read an empty string and call it "rcc
  # said nothing". It did exactly that once.
  rcc-rv32 < "$work/lm/one.i" > "$work/lm/one.sym" 2> "$work/lm/one.err" || {
    err=$(cat "$work/lm/one.err")
    echo "rcc could not read our preprocessed output for '${names[$i]}':" >&2
    echo "$err" >&2; echo "--- what we handed it ---" >&2
    cat "$work/lm/one.i" >&2; exit 1; }
  err=$(cat "$work/lm/one.err")
  case "$err" in
    *"${expects[$i]}"*) ;;
    *) echo "'${names[$i]}': lcc's own frontend, reading our linemarkers, should" >&2
       echo "have said \"${expects[$i]}\"." >&2
       # On ONE line, and the first line only: a mutation is told apart from
       # another by what lcc said instead, so that text has to be greppable
       # as a fragment rather than spread over the next three lines.
       echo "  lcc said instead: $(printf '%s\n' "${err:-(nothing at all)}" | head -1)" >&2
       echo "--- what we handed it ---" >&2
       cat "$work/lm/one.i" >&2; exit 1 ;;
  esac
  echo "  rcc places the diagnostic: ${names[$i]}"
done

# --- 2. lcc's IR from our text against our IR from our tokens -------------
# The listing is the interface poc/03-matcher consumes, so two frontends
# agreeing on it byte for byte is the strongest form of "consumed unchanged"
# available here. Both sides start from the SAME preprocessing, which is what
# isolates the question to whether lcc read our text the way we meant it.
mkdir "$work/ir"
programs=("$poc"/run/*.c)
declared_programs=3
[ "${#programs[@]}" -eq "$declared_programs" ] || {
  echo "${#programs[@]} programs under $poc/run, against the $declared_programs" >&2
  echo "this stage declares" >&2; exit 1; }

lines=0
for src in "${programs[@]}"; do
  name=$(basename "$src")
  render "$src" "$name" > "$work/ir/$name.i"
  rcc-rv32 < "$work/ir/$name.i" > "$work/ir/$name.lcc" 2> "$work/ir/$name.err" || {
    echo "rcc-rv32 failed on our preprocessed $name:" >&2
    cat "$work/ir/$name.err" >&2; exit 1; }
  nix eval --impure --raw --expr \
    "let cc = import $poc/../07-parser/compile.nix; c = import $poc/cpp.nix;
     in cc.listingOfToks (c.tokensOf { src = builtins.readFile $src; file = \"$name\"; })" \
    > "$work/ir/$name.ours"
  # A listing that is EMPTY would compare equal to another empty one, which
  # is the shape of green-while-testing-nothing this tree keeps finding.
  n=$(wc -l < "$work/ir/$name.lcc")
  [ "$n" -ge 20 ] || {
    echo "lcc's IR for $name is only $n lines, which is too little to have" >&2
    echo "compiled the program; comparing it proves nothing" >&2; exit 1; }
  diff -u "$work/ir/$name.lcc" "$work/ir/$name.ours" || {
    echo "lcc and this frontend disagree about the program our preprocessor" >&2
    echo "produced from $name (left: lcc, right: ours)" >&2; exit 1; }
  lines=$((lines + n))
  echo "  lcc and nixcc agree on the IR of $name ($n lines)"
done

echo "linemarkers placed ${#names[@]} diagnostics for lcc's own resynch(), and lcc's IR"
echo "for ${#programs[@]} preprocessed programs matches ours over $lines listing lines"
