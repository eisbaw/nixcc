---
id: TASK-005
title: 'Re-plan: choose the frontend strategy from PoC evidence'
status: To Do
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-14 18:46'
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
