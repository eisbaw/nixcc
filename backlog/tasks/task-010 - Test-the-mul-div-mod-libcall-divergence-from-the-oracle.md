---
id: TASK-010
title: Test the mul/div/mod libcall divergence from the oracle
status: To Do
assignee: []
created_date: '2026-09-14 18:47'
labels:
  - frontend
  - verification
dependencies:
  - TASK-007
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-004 records that the oracle runs with mulops_calls=0 while our target needs mulops_calls=1. The divergence is small and precisely known: with the flag on, dag.c leaves the MULI4/DIVI4/MODI4 op alone and promotes it to a forest ROOT via list(p) -- it does NOT become a CALL node. Everything else is identical.

Because oracle diffing runs with promotion off, this one transformation has no oracle and needs its own test, or it will be the one silent hole in an otherwise verified frontend.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Our frontend implements root-promotion of MULI4/DIVI4/MODI4 matching dag.c's behaviour under mulops_calls=1
- [ ] #2 Tested without the oracle: a C program using * / and % compiles and produces correct results on the emulator
- [ ] #3 A test asserts that with promotion disabled our IR matches the oracle exactly, so the divergence is bounded to this transformation alone
<!-- AC:END -->
