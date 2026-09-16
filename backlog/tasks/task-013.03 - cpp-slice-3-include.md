---
id: TASK-013.03
title: 'cpp slice 3: #include'
status: To Do
assignee: []
created_date: '2026-09-16 17:28'
updated_date: '2026-09-16 19:16'
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
<!-- SECTION:NOTES:END -->
