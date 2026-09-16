---
id: TASK-008
title: Decide the C preprocessor strategy
status: Done
assignee: []
created_date: '2026-09-14 18:47'
updated_date: '2026-09-16 19:16'
labels:
  - planning
  - frontend
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lcc/cpp/ is a SEPARATE ~2800-line program. The frontend in src/ consumes preprocessed input only -- input.c's resynch() parses `# n "file"` linemarkers, and there is no #include, #if or macro expansion anywhere in src/.

So the headline claim "Nix alone compiles C with no external toolchain" is false unless cpp is ported too. That is ~2800 lines nobody has counted into the plan. This task is to decide, not to implement: port it, write a smaller one, or narrow the claim to preprocessed C and say so in the README.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The three options are costed: port lcc/cpp, write a minimal cpp, or accept preprocessed-C-only input
- [x] #2 A decision is recorded in backlog/decisions with its reasoning
- [x] #3 If preprocessed-only is chosen, the README claim is corrected in the same change -- no claim outlives the decision that invalidated it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-002: the lexer already takes a position on two things this task has to decide, and one of them is a known divergence from ISO C.

The lexer in poc/02-lexer lexes RAW C89, not preprocessed input, because gcc -E on lcc/src fails without lcc's own include paths and lexing needs no preprocessing. So it already accepts what lcc's own lexer rejects: '//' comments, and '#' as a one-character punctuator for a preprocessor to consume ('##' arrives as two of them).

The divergence: backslash-newline is treated as trivia BETWEEN tokens, not spliced in translation phase 2 before tokenising. So 'a\<newline>b' lexes as two identifiers where ISO C makes it one, and a backslash-newline does not continue a '//' comment onto the next line (gcc warns about exactly that construct). check.nix asserts that no continuation in the lcc corpus joins two token characters, so this is a measured precondition rather than a hope -- there are 65 continuations in lcc's 34 sources and none of them splice inside a token. Whoever implements phase 2 should do it as a pass BEFORE the lexer and delete the backslash-newline branch from triviaStep, not bolt splicing into the scanner.

Second: lcc's input.c resynch() parses '# n "file"' linemarkers, which is how lcc knows which file a token came from. Raw sources have none, so tokens currently carry a line number and no file (see task-012). Whatever this task decides about the preprocessor decides that too.

Also relevant to costing: the lexer measures 47000 tokens/s and about 4 kB of peak RSS per token. A preprocessor that re-lexes macro expansions pays that rate again per expansion, and memory is the tighter budget -- 501 MB for a 431 kB input.

FORWARD-CARRIED from task-013.01, commit a063490. task-008 is Done as a DECISION and this does not reopen it; what follows is the implementation half it deferred, now with its cases enumerated rather than described.

The note this task left said phase 2 should be done as a pass BEFORE the lexer, and that check.nix asserts no continuation in the lcc corpus joins two token characters. Slice 1 did not do the pass. What it did instead was find every place where splicing between tokens differs VISIBLY from phase 2 and refuse each of them, so that the gap is a diagnostic rather than a silent difference. There are three, and two of them were silent MISCOMPILES that review found, not the implementer:

  1. A continuation joining two token characters. `ab\\<nl>cd' is one identifier in phase 2 and two here. Flagged by the lexer as `glue' and refused by poc/08-cpp, which confirms the join by asking the lexer whether the two lexemes stay apart when written adjacently -- rather than by a character-class rule that would have to be kept in step with the punctuator table.
  2. A continuation at the end of a `//' comment. Phase 2 carries the comment onto the NEXT line, so the standard discards a line this lexer was compiling. Refused in triviaStep.
  3. A continuation inside a string or character literal. `"ab\\<nl>cd"' IS "abcd" after phase 2; this lexer kept the newline in the lexeme and poc/06-constants then decoded it as an unrecognised escape worth 10. Refused in strStep.

Measured before any of it changed: none of the three patterns occurs in lcc's 34 sources or in any corpus in this tree. Case 3 had a test asserting the OLD behaviour, in cases.nix's line table; it moved to must-fail.nix.

One consequence worth having if phase 2 is ever written: no token can span a line any more, so the lexer's per-token newline count is gone and `nextLine' is just `line'. A phase-2 pass would make it non-zero again -- or, more likely, make it unnecessary, since the splice would be gone before the lexer saw it. The cost that pass has to solve is the one this task already named: splicing before lexing removes newlines, so every line number after a continuation is wrong unless the pass also carries an offset-to-line map.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Decided by the user: write a minimal preprocessor in Nix, and file a follow-up for what it deliberately omits. Recorded as decision-005. The README claim stands because the minimal cpp keeps it true; implementation is task-013, omissions are tracked in task-014.
<!-- SECTION:FINAL_SUMMARY:END -->
