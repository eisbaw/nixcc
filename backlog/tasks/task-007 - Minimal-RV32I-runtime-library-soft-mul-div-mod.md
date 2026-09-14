---
id: TASK-007
title: Minimal RV32I runtime library (soft mul/div/mod)
status: To Do
assignee: []
created_date: '2026-09-14 18:47'
labels:
  - backend
  - runtime
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RV32I has no M extension -- nix-riscv states plainly there are no M/A/F/D/C/V extensions. So every C *, / and % becomes a libcall. Without these, no C program doing arithmetic can run, which makes this a deliverable rather than an optimisation.

See decision-003 and decision-004: the oracle cannot be put into libcall mode, so this path is verified against the emulator rather than against lcc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 __mulsi3, __divsi3, __udivsi3, __modsi3, __umodsi3 implemented in RV32I
- [ ] #2 Written as assembly our own assembler consumes, not hand-assembled bytes
- [ ] #3 Tested on the emulator against a table of signed and unsigned cases including INT_MIN/-1, division by zero behaviour, and both signs of operand
- [ ] #4 Frontend emits these calls where the IR has MULI4/DIVI4/MODI4, and that lowering is tested independently of the oracle
<!-- AC:END -->
