---
id: TASK-076
title: 'A directive''s extent is its last token, not its last physical line'
status: To Do
assignee: []
created_date: '2026-09-16 19:35'
labels:
  - frontend
  - preprocessor
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by cross-model review of task-013.01. Given a `#line 10' followed by a block comment that opens on the directive's line and closes on the next, and then a semicolon, the semicolon is reported on line 11 and should be on line 12.

WHY. poc/08-cpp's `directive' computes `endLine' as the line of the directive's LAST TOKEN, and `relocate' then sets the presumed position of endLine + 1. Trivia that FOLLOWS the last token is not part of any token, so a comment spanning lines after the operands is invisible to that arithmetic -- the directive occupies more physical lines than its tokens do. The same would be true of a continuation after the last operand.

WHAT IS AVAILABLE. The next logical line's first token knows its own physical line, and that is the number the relocation is really about: `#line N' means the next line is N. Deriving the delta from the FOLLOWING token rather than from the directive's last one removes the question instead of answering it -- but the following token is not in scope where relocate runs, so it is a small restructuring of the step rather than a one-line fix.

Only #line and the `# n "file"' form are affected; every other directive uses endLine for nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A #line whose trailing trivia spans physical lines relocates the next line correctly
- [ ] #2 The same holds for a #line continued with a backslash-newline after its operands
- [ ] #3 poc/08-cpp/cases.nix carries both shapes in its relocation table, with the line numbers checked
<!-- AC:END -->
