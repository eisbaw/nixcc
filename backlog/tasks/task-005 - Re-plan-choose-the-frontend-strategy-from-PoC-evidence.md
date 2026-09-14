---
id: TASK-005
title: 'Re-plan: choose the frontend strategy from PoC evidence'
status: To Do
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-14 19:51'
labels:
  - planning
  - wave-boundary
dependencies:
  - TASK-002
  - TASK-003
  - TASK-004
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Wave boundary. The PoCs exist to answer questions that change the plan, so the plan is not written until they have answered.

The open decision is whether to port lcc's full C89 frontend before anything runs (the chosen milestone), or to grow the compiler feature by feature. The risk with full-frontend-first is that nothing runs until a great deal works; the mitigation already in place is that lcc's own rcc -target=symbolic dumps numbered DAG nodes, so our frontend is diffable against real lcc node by node with no backend written at all.

PoC-2 throughput is the main input. If Nix is fast enough, full-frontend-first is safe. If not, say so plainly and file the alternative instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Compile-time estimate for a 1000-line C file recorded, derived from PoC-2 measurements
- [ ] #2 Explicit go/no-go on the full-C89-frontend-first strategy, with the evidence that decided it
- [ ] #3 If go: the frontend port is filed as tasks decomposed along lcc's module boundaries (lex, decl, expr, stmt, types, dag, simp, gen)
- [ ] #4 If no-go: the alternative strategy is filed as tasks instead, and the reason full-frontend-first was rejected is written down
- [ ] #5 Differential harness against 'rcc -target=symbolic' is filed or built, since it gates every frontend task
- [ ] #6 Decision recorded in backlog as a decision entry, not only in a task note
- [ ] #7 Go/no-go weighs all four inputs, not throughput alone: oracle fidelity, accumulator linearity, the plan for lcc/cpp, and the plan for gen.c/dag.c/simp.c which are rewrites rather than ports
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-002: the lexer PoC answered its kill question with a yes, and the evidence is in task-002's notes -- 47000 tokens/s, linear from 31 kB to 431 kB, a 1143-line file in 0.25 s and 82 MB. Throughput is not the constraint on the frontend strategy.

Memory is. Peak RSS runs about 4 kB per token: 82 MB at 1143 lines, 501 MB at 16720, 976 MB for a 2.2 MB input. A strategy that keeps tokens, an AST and a DAG live at once multiplies that, and an attempt to localise the cost failed -- it is the evaluator's per-value overhead, not one fixable field. Cost the frontend in live values, not in seconds.

Two things the lexer deliberately does NOT do, both of which land on whatever this task chooses:
- No constant VALUES, only classified lexemes (task-011). lcc computes them inside gettok; in Nix, integer overflow throws rather than wrapping and strings cannot hold NUL, so neither lcc's overflow detection nor its string decoding transliterates.
- No column numbers, and no 'file' (task-012). lcc threads a full Coordinate through every error, every DAG node and the symbolic IR the oracle emits, so a line-only token will not survive contact with the oracle diff.

One shape decision is already made and is hard to reverse later: the token set is lcc's, which has NO compound-assignment tokens -- '<<=' is LSHIFT then '=', and lcc's parser disambiguates by peeking at the raw next character. Tokens record their preceding trivia so a parser can make the same peek via ws == "". A frontend strategy that wants '<<=' as one token has to change the lexer, not work around it.
<!-- SECTION:NOTES:END -->
