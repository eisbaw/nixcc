---
id: TASK-013
title: Minimal C preprocessor in Nix
status: To Do
assignee: []
created_date: '2026-09-14 20:04'
updated_date: '2026-09-16 01:30'
labels:
  - frontend
  - preprocessor
dependencies:
  - TASK-002
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Per decision-005. Scope: #include (both forms), object-like and function-like #define, #undef, #if/#ifdef/#ifndef/#elif/#else/#endif with constant-expression evaluation, and #line. Deliberately NOT lcc/cpp's compatibility baggage.

Without this the project's headline claim -- Nix alone compiles C with no external toolchain -- is false, so this is a deliverable rather than a nicety.

Binding constraints from decision-001 and task-002: no traversal with input-proportional depth; never one substring per token against a whole-file haystack (superlinear, invisible below ~300kB); deepSeq inside every loop or the symptom is stack overflow rather than slowness. Task-002 left a forward-carried note about a backslash-newline divergence -- read it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Emits '# n "file"' linemarkers in the form lcc's input.c resynch() expects, so the frontend consumes our output unchanged
- [ ] #2 Function-like macro expansion handles nested and recursive invocations without re-expanding a macro inside its own expansion
- [ ] #3 Constant-expression evaluation in #if covers defined(), integer arithmetic, and the C operator precedence lcc's frontend agrees with
- [ ] #4 Differential test against a real cpp (gcc -E or lcc/cpp) on a corpus of headers, comparing token streams rather than whitespace
- [ ] #5 Loop shape obeys decision-001; linearity demonstrated on a real multi-file include graph, not asserted
- [ ] #6 Harness is mutation-tested: breaking the preprocessor and breaking the harness each fail distinctly
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-004: the preprocessor is now the FIRST of the three
missing frontend stages, and its output is what the closed loop would consume.

poc/05-loop runs the whole chain from lcc's IR listing to program output
inside one `nix eval' with nothing but nix on PATH. The IR is produced OUTSIDE
that eval by rcc-rv32, so today's real entry point is a .sym file. This task,
the parser and the DAG builder are what stand between a .c file and that
point, and this one comes first because #include means the preprocessor
decides how much text the two stages after it ever see.

Two things poc/05-loop makes concrete for AC #5:

  * MEASURE IN LIVE VALUES, NOT SECONDS. The closed loop costs about 43.5 kB
    of peak RSS per emulated instruction, on top of 4 kB/token lexing. A
    preprocessor that expands an include graph holds the expanded token stream
    live while the parser runs over it; the budget is the whole pipeline's
    peak, not this stage's own.
  * THE HARNESS BAR. poc/05-loop's mutation stage trims nix's output to the
    text after the LAST `error:' line before matching a fragment, because nix
    prints the SOURCE around each frame and check.nix's source contains the
    message templates of every other check in it. Without the trim one
    mutation can claim another's fragment and the suite reports that its
    checks distinguish when they do not. poc/04-assembler/messages.sh found
    this first; copy the awk rather than rediscovering it.

Also relevant to AC #1: nothing downstream reads linemarkers yet. poc/03-matcher's
IR parser treats every non-forest line as directive noise against an explicit
allowlist, so a linemarker format nothing consumes will not be caught by the
existing suite -- the differential in AC #4 is the only thing that would.

FORWARD-CARRIED from task-027 (slice 1), commit 9330404.

THE PARSER NOW NAMES YOU. A `#' at file scope is refused with: "parse: \`#' -- this frontend is fed raw C and has no preprocessor yet; decision-005 chose to write one in Nix and task-013 is where it lives". That is the FIRST error a real user hits, so it was worth spelling out; when this task lands, that arm in poc/07-parser/parse.nix's `program' comes out.

WHAT THE SEAM LOOKS LIKE. poc/07-parser/compile.nix takes a SOURCE STRING and lexes it itself (`lexer.lex src'). A preprocessor that produced a token stream rather than text would slot in there -- but note that the parser reads `ws' off each token to make lcc's `*cp != '='' peek (task-002's no-compound-assignment-tokens decision), and it reads `line' for every diagnostic. Any stage between the lexer and the parser has to preserve both or the stderr differential (criterion #7 of task-027) goes red.

THE SIZE YOU HAVE TO FIT IN. Measured on the frontend as it stands: 142 kB of peak RSS per source line for a file of many small functions and 359 kB for one large function, so the 1 GB mark arrives at about 2800 source lines in one function. A preprocessed translation unit that includes real headers is well past that. This is the number decision-005 should be re-read against before scoping #include.

FORWARD-CARRIED from task-028 (slice 2), because the preprocessor's output is
now consumed by something that can tell it is wrong.

WHAT CHANGED FOR YOU. The frontend handles string literals end to end, and
that means three things the preprocessor will meet.

1. ADJACENT LITERALS ARE JOINED BY THE PARSER, not by the lexer. poc/02-lexer
   emits one SCON token per literal, poc/06-constants decodes one literal's
   units with NO terminator, and poc/07-parser/parse.nix's SCON arm
   concatenates the run and appends EXACTLY ONE 0 -- lcc's scon() in that
   order. A preprocessor that pastes `"ab" "cd"' into a single `"abcd"' token
   would still be correct; one that emitted `"ab\0" "cd"' would not. If `#'
   stringification (`#x') lands, it produces a literal token and joins with
   its neighbours by that rule and no other.

2. THE LITERAL'S BYTES ARE A BYTE LIST, NOT A NIX STRING, all the way from
   the lexeme to the .data (decision-001: a Nix string cannot hold a NUL, and
   `"a\0b"' is perfectly good C). If the preprocessor ever needs to
   MANIPULATE a literal's content -- stringification and token pasting both
   do -- it works on the lexeme text, which is fine, but anything that wants
   the VALUE must go through poc/06-constants' evalSCON and get units back.

3. A SOURCE BYTE ABOVE 127 IN A LITERAL STILL THROWS (task-046). `\NNN' and
   `\xNN' reach every byte. A preprocessor that reads real-world headers will
   meet UTF-8 in a comment (fine, the lexer discards comments) and in a string
   literal (not fine). That is the first thing to check against a real header,
   and it is a poc/06-constants change, not yours.

WHAT THE FRONTEND STILL SAYS WHEN IT MEETS A `#'. poc/07-parser/parse.nix's
`program' refuses it by name: "this frontend is fed raw C and has no
preprocessor yet; decision-005 chose to write one in Nix and task-013 is where
it lives". That refusal is covered by poc/07-parser/must-fail.nix, so when the
preprocessor lands, that case has to change with it rather than quietly start
failing.

AND THE PRACTICAL ONE. The whole corpus under poc/07-parser/c/ and run/ is
preprocessor-free C by construction -- no `#include', no `#define' -- because
the frontend cannot take anything else. That is 29 translation units of C this
project already compiles and diffs against lcc byte for byte, which makes it
the obvious first differential for a preprocessor: run it through, and the
output must be the input.
<!-- SECTION:NOTES:END -->
