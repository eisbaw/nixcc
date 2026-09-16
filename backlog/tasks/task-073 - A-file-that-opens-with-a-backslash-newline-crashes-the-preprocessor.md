---
id: TASK-073
title: A file that opens with a backslash-newline crashes the preprocessor
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
Found by cross-model review of task-013.01. A source file whose very first characters are a backslash and a newline makes poc/08-cpp throw `builtins.elemAt called with index -1' instead of a diagnostic.

WHY. poc/02-lexer gives the file's first token `bol = true' unconditionally -- it is the start of a logical line by definition -- and `glue = true' if its whole trivia is a continuation. The first token is the only one that can legitimately have both. poc/08-cpp's `checkGlue' then asks whether the continuation joined this token to the one before it, and reaches for `elemAt ts (i - 1)' with i = 0.

The comment above checkGlue argues that a glue token always has a predecessor, on the grounds that splice-only trivia contains no line-ending newline. That is true and it is not the whole rule: the FIRST token's bol does not come from its trivia at all.

It is a crash rather than a miscompile, which is why it is filed rather than fixed inside 013.01 -- but `elemAt called with index -1' names neither the file nor the construct, and this project's contract is that a refusal says what is wrong.

WHAT THE RIGHT ANSWER PROBABLY IS. A continuation at the start of a file joins the first token to nothing, so ISO C's phase 2 simply removes it and the two readings agree. The token should not be flagged at all: `glue' wants to mean 'joined to the token before it', and at offset 0 there is none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A file beginning with a backslash-newline preprocesses, or is refused with a diagnostic naming the construct -- never an elemAt index error
- [ ] #2 poc/08-cpp/must-fail.nix carries the case, with a control that differs in one character
- [ ] #3 The comment above checkGlue states the rule it actually relies on, including the first token
<!-- AC:END -->
