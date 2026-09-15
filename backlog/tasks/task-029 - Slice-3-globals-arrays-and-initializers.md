---
id: TASK-029
title: 'Slice 3: globals, arrays and initializers'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
labels:
  - frontend
  - parser
  - slice
dependencies:
  - TASK-023
  - TASK-028
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Third vertical slice per decision-007. Depends on the backend understanding a symbol with a constant offset (task-023), since lcc folds msg[2] into ADDRGP4 msg+8.

Note decision-004: little_endian affects initializer splitting in lcc/src/init.c, so the rcc-rv32 wrapper matters here more than anywhere else -- diffing against the raw oracle would silently compare against a big-endian layout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 File-scope globals, arrays and their initializers parse, reach the DAG and are placed in .data by the assembler
- [ ] #2 Initializer splitting matches rcc-rv32 for multi-byte and mixed-type initializers
- [ ] #3 A C program using a global array and an initializer compiles from .c and runs
<!-- AC:END -->
