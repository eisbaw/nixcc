---
id: TASK-014
title: Record what the minimal preprocessor omits
status: To Do
assignee: []
created_date: '2026-09-14 20:04'
updated_date: '2026-09-16 19:16'
labels:
  - frontend
  - preprocessor
  - docs
dependencies:
  - TASK-013
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up required by decision-005. The minimal cpp deliberately skips parts of the standard. Those omissions must be written down and diagnosed, not discovered by a user whose program silently fails to compile.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every deliberate omission is listed in the README's limits section
- [ ] #2 Encountering an unsupported directive produces a clear diagnostic naming it, never silent wrong output
- [ ] #3 A test asserts the diagnostic fires for each documented omission
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FORWARD-CARRIED from task-013.01, commit 81ec8bb.

Your AC #2 -- "encountering an unsupported directive produces a clear diagnostic naming it" -- is met for slice 1 and has a test: poc/08-cpp refuses any directive outside #define/#undef/#if/#ifdef/#ifndef/#elif/#else/#endif/#line by name, and the message ends "what the minimal preprocessor deliberately leaves out is tracked in task-014". poc/08-cpp/must-fail.nix pins three cases -- #pragma, #error and #ident -- and the third one's expected fragment is the TASK rather than the directive's name, precisely so that a refusal which stopped naming task-014 goes red. A mutation is aimed at it.

What AC #1 still wants from you is the README list, and slice 1 added its own half: what the preprocessor does, and that #if arithmetic is C89's in 32-bit long where gcc's is 64-bit. The omissions that are NOT yet written down anywhere but poc/08-cpp/cpp.nix's header: a skipped group is still lexed, so `#if 0' cannot fence off text that is not valid C tokens; an object-like macro body containing `#' is refused where gcc allows it; and a macro cannot reconstruct a compound assignment through the lexer's whitespace peek. Slices 2 and 3 will add more, so this task is better finished after them than before.
<!-- SECTION:NOTES:END -->
