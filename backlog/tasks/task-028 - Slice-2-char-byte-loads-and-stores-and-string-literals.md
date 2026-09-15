---
id: TASK-028
title: 'Slice 2: char, byte loads and stores, and string literals'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
labels:
  - frontend
  - parser
  - slice
dependencies:
  - TASK-024
  - TASK-027
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Second vertical slice per decision-007. Depends on the backend gaining byte load/store rules (task-024), which is why that comes first.

This is the slice that makes string handling real. Note decision-001: Nix strings cannot hold NUL, so a decoded C string literal must be a byte list throughout -- this is also why the closed loop works at all.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 char declarations, byte loads and stores, and string literals parse and reach the DAG
- [ ] #2 String literals are byte lists end to end; a literal containing an embedded NUL survives compilation and execution
- [ ] #3 A C program using char arrays and string literals compiles from .c and runs, printing correct output
- [ ] #4 DAG diffs against rcc-rv32 for the extended corpus
<!-- AC:END -->
