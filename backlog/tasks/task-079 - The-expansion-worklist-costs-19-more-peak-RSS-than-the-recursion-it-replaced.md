---
id: TASK-079
title: The expansion worklist costs 19% more peak RSS than the recursion it replaced
status: To Do
assignee: []
created_date: '2026-09-17 08:04'
updated_date: '2026-09-17 08:05'
labels:
  - frontend
  - preprocessor
  - perf
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured while implementing task-013.02, on poc/08-cpp/memory.py's own ladder input at 800 functions, same source, same machine, evaluator baseline subtracted:

  lexing only                                     195848 kB net
  slice 1's expander (recursive, commit 9165333)  232308 kB net -- 1.19x
  slice 2's expander (genericClosure worklist)    275792 kB net -- 1.41x

So the worklist is 19% dearer than the recursion for the same answer. What it bought is real -- constant frame depth on a macro chain of any length (task-071's shape), and the rescanning model function-like macros need at all -- but the cost is real too and is not a measurement artefact: it reproduces with the ladder input unchanged.

WHERE IT GOES. Per token of any line that names a macro, the worklist allocates four values where the recursion allocated one: the item carrying the token with its hide set and nesting level, the cursor, the genericClosure step item, and the one-element output list. A line that names NO macro already short-circuits to its own token list and costs nothing, and that is worth about 4%.

TWO THINGS THAT WERE TRIED AND DID NOT HELP, so nobody repeats them:

  * replacing the deepSeq-of-removeAttrs forcing with an explicit seq of the
    three fields, which removes one attrset copy per token: 312868 -> 312656 kB
    of peak RSS. Kept anyway, because it is no worse and says what it forces.
  * forcing each line record inside the outer loop, on the theory that every
    line's worklist stayed live as a thunk until the end of the file:
    312656 -> 313500 kB. The theory is wrong, and peak RSS here tracks total
    allocation rather than the live set. Reverted.

WHAT WOULD ACTUALLY WORK, and why it was not done in slice 2: batch a RUN of consecutive non-macro tokens into ONE worklist step instead of one step each. The indices of the macro names on a line are already computed for the short-circuit, so the next one is a lookup rather than a scan -- but resuming a run after an invocation has consumed part of the line, and keeping the open-parenthesis lookahead correct at the end of a run, is exactly the kind of change that hides a silent miscompile. Slice 1 already shipped two of those, both found by cross-model review. It wants its own task and its own mutation.

The ceilings in memory.py now sit at 14.0 kB per preprocessed token against 11.1-11.3 measured, and 1.95x against 1.64-1.65x. Both carried 35% headroom before and carry about 20% now, deliberately: the number should not be allowed to drift up quietly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A macro-free run of tokens costs one worklist step rather than one per token
- [ ] #2 The overhead on memory.py's ladder is measured again and the ceiling lowered to match, rather than left with slack
- [ ] #3 The change carries its own mutation, because batching a run is where an off-by-one stops being visible
<!-- AC:END -->
