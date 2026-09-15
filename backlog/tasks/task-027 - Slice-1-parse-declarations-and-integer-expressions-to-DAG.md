---
id: TASK-027
title: 'Slice 1: parse declarations and integer expressions to DAG'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
labels:
  - frontend
  - parser
  - slice
dependencies:
  - TASK-002
  - TASK-011
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
First vertical slice per decision-007. Build the parser and DAG builder in Nix for the subset the backend already compiles: int locals and parameters, the integer binary and unary operators, assignment, calls, return.

This is the slice that turns hello.c rather than hello.sym into the entry point of the closed loop, for programs in this subset. That is the project's headline claim moving from "from the IR down" to "from the C down".

Binding constraints: decision-001 (loop shape, accumulator, substring, deepSeq, overflow throws); memory is ~4kB/token and ~8.5kB/DAG node, so do not hold tokens, AST, DAG and labels live at once without measuring. Read the forward-carried notes on this task and on task-005 before starting -- especially that token values are NOT computed by the lexer (task-011) and that lcc has no compound-assignment tokens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Parser consumes the task-002 lexer's tokens; no second lexer
- [ ] #2 DAG output diffs node-for-node against 'just ir' (rcc-rv32, never raw rcc -target=symbolic) for a corpus of at least 10 C functions in the subset
- [ ] #3 The diff compares node numbering and #n back-references, not just opcodes, since a renumbering bug is exactly what an opcode-only diff misses
- [ ] #4 At least 3 programs in this subset compile from .c and RUN end to end in one nix eval, replacing .sym as the entry point
- [ ] #5 Memory measured and recorded per source line, with tokens/AST/DAG live simultaneously
- [ ] #6 Harness mutation-tested: breaking the parser and breaking the harness each fail distinctly
<!-- AC:END -->
