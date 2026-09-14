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

# --- 3. throughput ------------------------------------------------------
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
python3 "$poc/throughput.py" "$poc" "${ladder[@]}"

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

keep=0
