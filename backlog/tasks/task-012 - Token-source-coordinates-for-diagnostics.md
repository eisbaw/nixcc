---
id: TASK-012
title: Token source coordinates for diagnostics
status: To Do
assignee: []
created_date: '2026-09-14 19:45'
labels:
  - frontend
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The lexer in poc/02-lexer records a line number per token and nothing else. lcc carries a full Coordinate (file, x, y) on every token and threads it through every error message, every DAG node and the symbolic IR the oracle emits -- so 'line only' will not survive contact with the parser.

The column is derivable today (a token starts at key + stringLength ws) but the byte offset is not a column: it needs the offset of the preceding newline, which nothing tracks. Adding it is cheap while scanFrom's return shape has one consumer and expensive once a parser depends on it, which is why this is filed now rather than discovered later.

Also unresolved: which 'file' a token belongs to. Raw C89 sources have none of lcc's '# n "file"' linemarkers, and lcc's input.c resynch() exists precisely to read them. Whatever task-008 decides about the preprocessor decides this too.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each token carries enough to produce lcc's (file, x, y) coordinate
- [ ] #2 Column numbers are verified against a hand-written table, not just line numbers
- [ ] #3 The cost of carrying them is measured against the task-002 throughput ladder, and the regression is reported
- [ ] #4 The file component is reconciled with whatever task-008 decides about linemarkers
<!-- AC:END -->
