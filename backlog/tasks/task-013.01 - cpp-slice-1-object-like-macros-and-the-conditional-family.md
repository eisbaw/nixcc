---
id: TASK-013.01
title: 'cpp slice 1: object-like macros and the conditional family'
status: Done
assignee: []
created_date: '2026-09-16 17:27'
updated_date: '2026-09-16 19:56'
labels:
  - frontend
  - preprocessor
  - slice
dependencies:
  - TASK-011
parent_task_id: TASK-013
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
First preprocessor slice, and deliberately the one that needs no header provenance decision -- it operates on a single translation unit with no #include.

Scope: line splicing (backslash-newline), #define of object-like macros, #undef, #ifdef/#ifndef/#else/#elif/#endif, #if with constant-expression evaluation including defined(), and #line. Plus the linemarker output the frontend already expects.

Ends with something that RUNS: a C file using object-like macros and conditional compilation compiles and executes through the existing pipeline.

Note the lexer already handles backslash-newline continuations, and task-002 left a forward-carried note about a divergence there worth checking. Constant-expression evaluation should reuse poc/06-constants rather than growing a second integer evaluator -- and remember Nix integer overflow THROWS (decision-001), which is why that module detects by comparison before the multiply.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Object-like #define and #undef expand correctly, including a macro whose body references another macro
- [x] #2 The full conditional family works, with #if constant-expression evaluation covering defined(), integer arithmetic and C operator precedence
- [x] #3 Emits '# n "file"' linemarkers in the form lcc's input.c resynch() expects, so the frontend consumes the output unchanged
- [x] #4 Differential against gcc -E on a corpus, comparing TOKEN STREAMS rather than whitespace
- [x] #5 A C program using macros and conditional compilation compiles from .c and RUNS end to end
- [x] #6 Harness mutation-tested: breaking the preprocessor and breaking the harness each fail distinctly
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
DESIGN (decided before writing code, so the cross-model review can argue with the reasoning rather than the diff):

1. THE CPP WORKS ON TOKENS, NOT TEXT. poc/02-lexer already lexes raw C89 (it keeps '#', '//' and backslash-newline, which lcc's own lexer rejects), and its tokens carry kind/text/line/ws -- the three things the parser reads. A text-in/text-out preprocessor would re-lex everything and pay 4 kB/token twice; memory is the binding constraint (decision-007, 142-359 kB of peak RSS per source line in the frontend). So cpp.nix consumes 'lexer.lex src' and produces a token list that poc/07-parser/compile.nix can take directly.

2. LOGICAL LINES COME FROM THE LEXER, NOT FROM A SECOND SCANNER. A directive is a '#' that is the first token on a logical line, and the line ends at the first newline that is outside a comment and not part of a backslash-newline splice. lex.nix's triviaStep is the only state machine in the tree that already knows which of those a newline is; recomputing it by re-scanning each token's 'ws' would be a second definition of one fact. So lex.nix gains two derived flags per token, 'bol' and 'glue', computed where the information already exists. Measured against gcc: 'int a; /* x\n */ #define A 1' is NOT a directive (gcc passes it through), while '#define B /* c\n */ 7' IS one directive -- both fall out of the single rule above.

3. LINE SPLICING, HONESTLY. The lexer splices backslash-newline BETWEEN tokens, not in phase 2 (task-008), so directive continuation -- the case that actually matters -- already works. A splice that joins two token characters ('ab\<nl>cd' -> one identifier in ISO C) is REFUSED naming task-008, not silently mislexed. That is the 'glue' flag. Full phase-2 splicing would need a text pass before the lexer plus an offset->line map to keep line numbers exact, and decision-001 says memory, not asymptotics, is what this project spends.

4. #if REUSES poc/06-constants. evalICON turns a lexeme into {value,type}; what is new here is the EXPRESSION, by recursive descent (depth tracks nesting, not input length). Arithmetic is C89's: long/unsigned long, which on RV32 is 32 bits, so every result is reduced mod 2^32 -- and the multiply is done in 16-bit halves because Nix integer overflow THROWS (decision-001). No shift operators in Nix, so << and >> go through a power-of-two table. defined() is resolved BEFORE expansion; remaining identifiers become 0; && || ?: short-circuit so '#if 0 && (1/0)' does not divide.

5. MACRO EXPANSION is recursive with a hide set, which for object-like macros bounds the depth by the number of distinct macros rather than by input length. Verified against gcc: '#define F F' gives F, and '#define G H' + '#define H G' gives G.

6. LINEMARKERS GET A REAL CONSUMER. Nothing in this tree reads '# n "file"', so an emitter nothing consumes would be untestable (the task-053 trap). cpp.render emits lcc's form and the harness feeds it to rcc-rv32 -- lcc's own input.c resynch() -- then checks that rcc's diagnostics carry the line and file the #line directive asked for. Breaking the emitter changes rcc's stderr.

7. WIRING. poc/07-parser/demo.nix routes through cpp, so 'just run FILE ARG' compiles and runs a .c with #define and #if. compile.run stays on raw tokens for the parser's own suite, so the parser's memory ladder is not moved by this task.

8. REFUSALS, EACH NAMING A TASK: #include -> task-013.03; function-like #define, '#' stringify, '##' paste -> task-013.02; every other directive -> task-014; a token-joining splice -> task-008; a float in #if -> decision-006/task-015.

DELIVERABLES: poc/08-cpp/{cpp.nix,cases.nix,check.nix,must-fail.nix,messages.sh,oracle.py,run.sh}, a cpp corpus, a 'poc-cpp' recipe, a flake check, README correction.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RESULT: a C file with #define and #if in it compiles and runs. `just run poc/08-cpp/run/macros.c 10' prints 192; table.c with 7 prints 408. The README no longer says input must already be preprocessed, because it no longer must. Landed in a063490 (the lexer's half) and 81ec8bb (the preprocessor).

GATE, run to completion after every change above: `nix develop --command just e2e' -> 8 PoC(s) passed. Mutation counts 12 / 62 / 28 / 37 / 20 / 75 / 36 (lexer / matcher / assembler / loop / constants / parser / cpp). The lexer's went 10 -> 12 and the parser's must-fail 37 -> 38; both are this task's.

WHAT THE STAGES MEASURED, not adjectives:
  * 33 expansion cases, 49 #if expressions, 8 line-number and linemarker cases, 4 macro-table cases: 398 tokens produced.
  * 35 refusals, each with its own control and its own diagnostic text.
  * 43 translation units diffed against gcc -E as TOKEN STREAMS, 2661 tokens -- 17 written for the directives, plus poc/07-parser's 26 preprocessor-free units, because a preprocessor must be the identity on a file with no directives.
  * 6 diagnostics placed by rcc-rv32 reading our linemarkers, and lcc's IR for two preprocessed programs matching ours over 180 listing lines.
  * 4 program runs on the Nix RV32I machine, 1670-1820 instructions each.
  * memory: 8.6 kB of peak RSS per preprocessed token, 1.19x what lexing the same source costs.

THE DECISION EVERYTHING ELSE FOLLOWS FROM: IT WORKS ON TOKENS. poc/02-lexer already lexes raw C89 and its tokens carry kind/text/line/ws, which is everything poc/07-parser reads. A text-in/text-out preprocessor would lex the unit, print it and lex it again at 4 kB of peak RSS per token. So compile.nix grew `runToks'/`listingOfToks' -- doors that lex nothing -- demo.nix routes through them, and `render' exists only for gcc and rcc.

TWO FLAGS IN THE LEXER RATHER THAN A SECOND SCANNER HERE. A directive is a # that is first on a LOGICAL line, and the line ends at the first newline outside a comment and not half of a splice. triviaStep is the only place that already knows which a newline is. Both halves were measured against gcc -E, not read off the standard: `int a; /* x<nl> */ #define A 1' is NOT a directive to gcc, `#define B /* c<nl> */ 7' IS one, and a leading comment still leaves the file's first # a directive.

LINE SPLICING, HONESTLY, because this is the scope item that is part done and part refused. A continuation BETWEEN tokens or inside a block comment works and needed nothing. The three places where between-tokens splicing differs VISIBLY from ISO C's phase 2 are all refused naming task-008, because each would otherwise compile something the standard does not say: one joining two token characters (ab\\<nl>cd is one identifier in phase 2), one ending a // comment (phase 2 carries the comment onto the next line, so the standard discards a line we were compiling), and one inside a string literal ("ab\\<nl>cd" IS "abcd"; we kept the newline and poc/06-constants decoded it as an unrecognised escape worth 10). The last two were SILENT MISCOMPILES and were found by review, not by me. Neither pattern occurs in lcc's 34 sources or in any corpus here -- measured before changing anything. Full phase 2 is still not done; task-008 now carries both cases.

#if ARITHMETIC IS C89's AND GCC'S IS NOT. 6.8.1 widens signed types to long, 4 bytes on RV32, so everything is modulo 2^32; gcc has used intmax_t since C99. Five cases differ and are pinned in cases.nix rather than in the differential, where the reference would have to be wrong for them to pass. The other 44 rows of the #if table were cross-checked against gcc one by one before being written down, and agreed.

WHAT THE REVIEWS FOUND, because none of it was found by me:
  * The header claimed expansion depth is bounded by distinct macros and not by file size. False -- the number of distinct macros IS bounded by file size. With the cap lifted, a chain of 3000 expands and 6000 dies with max-call-depth exceeded. MAX_NEST is load-bearing, and task-071 carries what removes it.
  * The macro table is one attrset updated with //, which copies every binding it holds: 3 MB above lexing at 500 macros, 37 MB at 2000, 138 MB at 4000. poc/07-parser/store.nix's finding wearing an attrset hat. memory.py now has a second ladder AXIS for it with a ceiling on the top point, and task-072 carries the fix and why the two obvious remedies are each wrong.
  * memory.py with an empty LADDER printed its cleanest line after measuring nothing -- the shape poc/lib/mutant.sh argues against, in the one file that had not adopted it. Now a declared count. The same hole is still in poc/07-parser/memory.py, untouched.
  * const.evalICON CLAMPS a constant too big for its type and records why in `warnings', and this stage dropped them: #if 4294967296 == 4294967295 took the TRUE arm. Now refused, in #if and in #line.
  * 6.8.1's skipped-group rule was applied to three directives out of five; #else and #endif checked their operands even inside a group that was not being compiled.
  * messages.sh died silently under pipefail when a refusal threw with no `error:' line -- at exactly the point whose job is to report a missing diagnostic. Fixed here and in poc/07-parser's copy.
  * render's foldl' with acc ++ [x] was decision-001's quadratic trap defended by a paragraph. It is a map over an index now; the paragraph was longer than the fix.
  * The deepSeq in the main loop named st's four fields by hand, so a fifth -- task-013.03's include stack -- would be silently unforced, and decision-001 says the symptom is stack overflow rather than a red test. It subtracts the macro table now instead of enumerating the rest.
  * Two sites manufactured tokens and each remembered a different subset of the lexer's shape; definedIcon never set `nextLine' at all. One mkTok now.

LIMITS, none of them hidden:
  * A skipped group is still LEXED. #if 0 around text containing an unterminated quote or a stray @ throws, where a real cpp only needs valid pp-tokens. Nothing in the corpora does it, and slice 1 has no #include to bring one in.
  * #define defined is refused (C89 forbids it); #undef defined is not, and is harmless.
  * An object-like body containing # is refused naming task-013.02. gcc allows it, where it means nothing. That is an over-refusal, deliberately: a # reaching the parser is reported as unpreprocessed input.
  * A macro cannot reconstruct a compound assignment through poc/02-lexer's ws == "" peek, because every expanded token gets one space. No real program asks for it.
  * The macro table's cost above: real today only for a hand-written file with thousands of defines, and task-013.03 is where it becomes real.

ALL SIX CRITERIA MET. Nothing was reticked to match what was built; the scope line about line splicing is the one place the work is part done and part refused, and it says so above rather than being spelled as done.

CROSS-MODEL REVIEW ROUND, commit c59a551. codex found nine defects that 39 mutations, a 44-unit differential and two same-model reviews all passed. Two were silent miscompiles. That is the finding, and it is about the review design rather than about any one of them.

FIXED -- TWO SILENT MISCOMPILES:
  * A backslash-newline inside a block comment's terminator. ISO C's phase 2 runs BEFORE comments are recognised, so `*\\<newline>/' is `*/' and ends the comment; what follows it is code. This scanner ran on to the next terminator and swallowed it. Reproduced: gcc returns 2 on the reviewer's input and we returned 1, with no diagnostic. Refused now, naming task-008. Nothing downstream could have caught it -- a comment sets `solid', so `checkGlue' is structurally blind to it, which is the part worth remembering: the flag was designed against the case I already knew about.
  * An expansion pasting onto the token AFTER it. Manufactured tokens got a leading space; the original token following one kept its empty `ws'. `#define P +' used as `a P+ +2' rendered `a ++ +2', which increments a, where gcc renders `a + + +2', which does not -- both compile. The fix is not a rule about macros: `render' now asks, at every boundary it writes with nothing between, whether those two lexemes still lex as those two lexemes. That is the same question `checkGlue' asks, so `staysApart' moved to module level and there is one answer to it. Our TOKEN stream was never wrong, which is exactly why the gcc differential could not see it; the render round-trip in oracle.nix can, and cpp/adjacent.c is now in the corpus so it does.

FIXED -- A TEST THAT ASSERTED NOTHING, the fourth time in this project. Both operands of the unsigned-division case were positive, so signed and unsigned division agree and the conversion was never exercised; the corpus reused the same pair. Review demonstrated it by swapping the branch and watching every check pass. It needed a NEGATIVE left operand -- and a second case that does not reach its bit pattern through `wrap', or the wrap mutation breaks it too and the two cannot be told apart. `'\\377'' is that value, because plain char is signed on this target.

FIXED -- a function-like #define hidden behind a continuation was accepted as object-like, letting an explicitly out-of-scope feature through instead of refusing it with task-013.02. `glue' already means "adjacent after phase 2", so it joins the emptiness test.

FILED RATHER THAN FIXED, each referenced from the line it describes: task-073 (a file opening with a continuation dies with `elemAt called with index -1' -- the first token is the one place `bol' does not come from trivia, which the comment I wrote above checkGlue got wrong), task-074 (the #if parser's depth tracks OPERATORS, not nesting, so a 3000-term #if overflows -- decision-001 forbids that outright and my comment claimed an exemption it does not have), task-075 (#line 010 is 8 here and 10 to gcc, because evalICON reads the C spelling and the standard wants a decimal digit sequence), task-076 (a directive's extent is its last TOKEN, so trailing trivia that spans lines puts everything after it one line early).

GATE after all of it: 8 PoC(s) passed. Mutations 13 / 62 / 28 / 37 / 20 / 75 / 39. Differential 44 units, 2723 tokens. 52 #if cases, 36 cpp refusals, 23 lexer refusals.

WHAT THE CROSS-MODEL PASS CONFIRMED rather than faulted, recorded so it is not re-litigated: the differential does compare token streams, the five #if width divergences reproduce and are honestly pinned, and the macro-table memory agrees with the quadratic shape declared.

NOT MINE: cpp-example.c at the repo root appeared during the review window. It compiles and runs through this pipeline -- `just run cpp-example.c 4' prints 84 -- but I did not write it and left it uncommitted.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Slice 1 of the preprocessor: line splicing, object-like #define/#undef, the whole conditional family with #if constant-expression evaluation including defined(), #line, and the linemarkers lcc's resynch() reads. A .c file with directives in it now compiles and RUNS -- the README's "input must already be preprocessed" is gone.

It works on TOKENS rather than text, because poc/02-lexer already lexes raw C89 and re-lexing costs 4 kB of peak RSS per token. The lexer gained two derived flags so the rule about what ends a logical line has one definition, measured against gcc -E on both sides of the question.

Verified by 43 translation units diffed against gcc -E as token streams, by rcc-rv32 -- lcc's own frontend -- reading our linemarkers and reporting where its diagnostics came from, and by two programs compiled from .c and executed on the Nix RV32I machine. 36 mutations, each detected distinctly.

Two silent miscompiles were found by review and closed: a backslash-newline ending a // comment, and one inside a string literal. Two limits are measured and filed rather than left to be discovered: the expansion depth cap (task-071) and the macro table's copy-per-define cost (task-072).

#if arithmetic is C89's, in 32-bit long, where gcc's is 64-bit. Five cases differ, are pinned in cases.nix rather than in the differential, and are stated in the README.
<!-- SECTION:FINAL_SUMMARY:END -->
