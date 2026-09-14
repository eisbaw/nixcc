---
id: TASK-008
title: Decide the C preprocessor strategy
status: To Do
assignee: []
created_date: '2026-09-14 18:47'
updated_date: '2026-09-14 19:50'
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
- [ ] #1 The three options are costed: port lcc/cpp, write a minimal cpp, or accept preprocessed-C-only input
- [ ] #2 A decision is recorded in backlog/decisions with its reasoning
- [ ] #3 If preprocessed-only is chosen, the README claim is corrected in the same change -- no claim outlives the decision that invalidated it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-002: the lexer already takes a position on two things this task has to decide, and one of them is a known divergence from ISO C.

The lexer in poc/02-lexer lexes RAW C89, not preprocessed input, because gcc -E on lcc/src fails without lcc's own include paths and lexing needs no preprocessing. So it already accepts what lcc's own lexer rejects: '//' comments, and '#' as a one-character punctuator for a preprocessor to consume ('##' arrives as two of them).

The divergence: backslash-newline is treated as trivia BETWEEN tokens, not spliced in translation phase 2 before tokenising. So 'a\<newline>b' lexes as two identifiers where ISO C makes it one, and a backslash-newline does not continue a '//' comment onto the next line (gcc warns about exactly that construct). check.nix asserts that no continuation in the lcc corpus joins two token characters, so this is a measured precondition rather than a hope -- there are 65 continuations in lcc's 34 sources and none of them splice inside a token. Whoever implements phase 2 should do it as a pass BEFORE the lexer and delete the backslash-newline branch from triviaStep, not bolt splicing into the scanner.

Second: lcc's input.c resynch() parses '# n "file"' linemarkers, which is how lcc knows which file a token came from. Raw sources have none, so tokens currently carry a line number and no file (see task-012). Whatever this task decides about the preprocessor decides that too.

Also relevant to costing: the lexer measures 47000 tokens/s and about 4 kB of peak RSS per token. A preprocessor that re-lexes macro expansions pays that rate again per expansion, and memory is the tighter budget -- 501 MB for a 431 kB input.
<!-- SECTION:NOTES:END -->
