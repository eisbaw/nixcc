---
id: TASK-013.03
title: 'cpp slice 3: #include'
status: To Do
assignee: []
created_date: '2026-09-16 17:28'
updated_date: '2026-09-17 09:38'
labels:
  - frontend
  - preprocessor
  - slice
dependencies:
  - TASK-070
  - TASK-013.02
parent_task_id: TASK-013
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The last preprocessor slice, blocked on task-070 because it cannot be built until header provenance and the purity question are settled.

Scope: both #include forms, the resolution strategy task-070 chooses, nesting, and include guards working as a consequence of slice 1 rather than as a special case.

WATCH THE MEMORY. A preprocessed translation unit pulling in real headers is far larger than anything measured so far: task-027 measured 142 kB of peak RSS per source line for many small functions and 359 kB for one large one, so 1 GB arrives around 2800 lines in a single function. Measure an include graph before assuming it fits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both #include forms resolve per task-070's decision
- [ ] #2 Nested includes and include guards work, the guards falling out of slice 1 rather than being special-cased
- [ ] #3 Runs inside nix flake check, where --impure is unavailable
- [ ] #4 Memory measured on a real multi-file include graph and recorded, not assumed
- [ ] #5 A C program using #include compiles from .c and RUNS end to end
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FORWARD-CARRIED from task-013.01 (slice 1), commits a063490 and 81ec8bb.

THE REFUSAL YOU REPLACE names both you and task-070: `#include' is refused in cpp.nix's directive dispatch, and must-fail.nix pins it twice -- once on the angle-bracket form and once on the quoted one, with different fragments -- each paired with a control that is the SAME directive inside a `#if 0' group, which is inert and must stay so.

THE INVARIANT YOU WILL BREAK, and it is not obvious from reading the code. The main loop `seq's the macro table rather than deep-forcing it, on the argument that its values cannot form a thunk chain as deep as the loop. What makes that true is NOT that they were deepSeq'd at definition -- after the seq they are still unforced -- but that a macro body closes over `groupAt k', over the single shared token list `lexer.lex src' produced once, and never over the previous step's state. So an unforced macro value is a depth-1 thunk however many steps have run. The day a macro body comes from an INCLUDED file's own token list, re-derive that. decision-001 says the symptom of getting it wrong is "stack overflow (possible infinite recursion)", not a slow test.

THE COST THAT WILL BITE YOU FIRST IS THE MACRO TABLE, and it is measured rather than predicted. It is one attrset updated with `//', which copies every binding it already holds: 3 MB of peak RSS above lexing the same file at 500 macros, 37 MB at 2000, 138 MB at 4000 -- task-072. One real header chain is a four-figure macro count. poc/08-cpp/memory.py's second ladder axis carries those numbers with a 100 MB ceiling on the top point, so it cannot get quietly worse, but it does not go away. Read task-072 before you write the include stack: it also records why bucketing on the first character and hashing the name are each wrong.

THE OTHER COST IS THE ONE THE FIRST AXIS MEASURES. Preprocessing costs 8.6 kB of peak RSS per output token and 1.19x what lexing the same source costs; the frontend behind it costs 142-359 kB per SOURCE LINE (decision-007) and reaches 1 GB at about 2800 lines in one function. An expanded include graph is the input to that, so the budget is the whole pipeline's peak, not this stage's.

WHAT THE LEXER DOES WITH A HEADER IT HAS NEVER SEEN. A skipped group is still LEXED here -- `#if 0' around text with an unterminated quote or a stray `@' in it throws, where a real cpp only needs valid pp-tokens. Nothing in the corpora does it because nothing in the corpora is a real header. That is the first thing to check against one, along with task-046's byte-above-127 refusal in a string literal, which is a poc/06-constants change and not yours.

AND THE PURITY QUESTION IS STILL task-070's. Everything in poc/08-cpp is a pure expression: `preprocess { src, file }' takes a STRING, which is exactly the shape that survives an attrset-of-headers answer with no readFile anywhere. If task-070 chooses that, the change here is an extra argument and nothing else; if it chooses the filesystem, the flake's checks output is where it breaks.

FORWARD-CARRIED from task-013.02 (slice 2).

WHAT YOU INHERIT. poc/08-cpp does the whole of `#define' now -- object-like and function-like, `#', `##', the blue paint -- and `#include' is the only directive left refused. That refusal names you and decision-010, and it lives in `directive' in cpp.nix; must-fail.nix pins both halves of its text.

THE EXPANDER IS NO LONGER RECURSIVE, and that changes the shape of your problem. `expandItems' is a genericClosure worklist over a cursor: a position in the input list plus a stack of frames holding replacement lists still being rescanned. The whole thing runs per LOGICAL LINE, and `preprocess' still runs one outer step per logical line off the lexer's `bol' flag.

THE INVARIANT YOU WILL BREAK IS STILL THE ONE SLICE 1 NAMED. The outer loop only `seq's the macro table, not `deepSeq's it, and what makes that safe is that a macro body closes over `groupAt k' -- over the single shared token list `lexer.lex src' produced once -- and never over the previous step's state. The moment a macro body comes from an INCLUDED file's own token list, re-check it. Slice 2 added one thing here: `defineIn' now forces the compiled replacement plan eagerly, because `##' at either end and a `#' with no parameter after it are constraint violations of the `#define' itself and gcc reports them whether or not the macro is used.

THREE THINGS THAT ARE NOW YOUR PROBLEM RATHER THAN A CURIOSITY.

  * task-080, THE HIDE SET IS MISSING ITS INTERSECTION. Not include's problem
    directly, but it is the one place this expander knowingly disagrees with
    gcc, it is pinned in cases.nix, and a header full of macro machinery is
    where it will first be noticed.

  * task-072, THE MACRO TABLE. It is one attrset updated with `//', so n defines copy n^2/2 bindings: 4 MB above lexing at 500 macros, 40 MB at 2000, 138 MB at 4000 (memory.py's second ladder, with a 100 MB ceiling on the top point). Slice 2 made each entry BIGGER -- a parameter list and a compiled plan -- and moved the 2000-macro point from 37 to 40 MB. One real header chain is a four-figure macro count. This arrives as "the preprocessor got slow" with nothing to bisect against unless it is fixed first.

  * task-077, AN INVOCATION MUST FIT ON ONE LOGICAL LINE. This is the limit most likely to bite a real header: `va_start(ap,\n v)' is ordinary C. The fix is described in task-077 and it is a change to the LINE MODEL, not to the expander -- the gather already knows how to read past its list, but the step must then report how far it consumed, the state must carry that, and a line record ends up holding tokens from more than one physical line. The eight-plus relocation cases and frontend.sh's check that lcc's resynch() agrees with our markers are all computed against one-record-per-logical-line.

  * task-079, THE WORKLIST COSTS 19% MORE PEAK RSS than the recursion it replaced. Measured with the ladder input held fixed, so it is the expander and not the input. Include multiplies the token count, so it multiplies this too.

WHAT THE DIFFERENTIAL LOOKS LIKE NOW. oracle.py runs `gcc -std=c89 -E -P -ffreestanding' over 22 corpus files under poc/08-cpp/cpp/ plus the 26 preprocessor-free units under poc/07-parser/c/, and compares token streams; 48 units, 3161 tokens. Four of those corpus files are slice 2's -- funclike.c, stringify.c, paste.c, bluepaint.c. For `#include' the corpus has to grow a MULTI-FILE case, and gcc has to be given the same -I as we give ourselves or the oracle is answering a different question. `-ffreestanding' is already there and is what stops gcc pulling in stdc-predef.h.

AND THE ONE DECISION-010 ALREADY MADE FOR YOU: the header set is a PARAMETER, not a fixed location, so `nix flake check' passes the flake-relative path and `just run' passes the same path from its impure eval. cpp.nix's `preprocess' takes `{ src, file ? "<stdin>" }' today; the header set is the third field, and poc/07-parser/demo.nix and run.nix are the two callers that have to pass it.

ONE MORE, SMALL BUT REAL: poc/02-lexer refuses a stray `\' outright ("unexpected character"), where a real preprocessor treats it as a preprocessing token of its own. No corpus file has one yet. A real header might.
<!-- SECTION:NOTES:END -->
