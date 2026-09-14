---
id: TASK-019
title: Frame layout for types and frames the selector PoC does not handle
status: To Do
assignee: []
created_date: '2026-09-14 20:56'
labels:
  - backend
  - codegen
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher's frame layout covers what its three test functions need and refuses the rest, loudly:

  * 'lays out 4-byte scalars only' -- a char, short, double or struct parameter throws, because the PoC sizes the parameter area as 4 bytes per lcc offset.
  * 'exceeds the 2032-byte immediate a one-instruction prologue can reach' -- a larger frame needs a scratch register and a multi-instruction prologue.
  * Incoming parameters are always spilled to the frame in the prologue, even when nothing takes their address.

None of these is wrong code; all of them are a stop. They are collected here rather than in the register-allocation task because they are frame arithmetic, not allocation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Parameters and locals of every scalar size are laid out from lcc's own offsets and sizes
- [ ] #2 A frame larger than 2032 bytes gets a prologue that can reach it
- [ ] #3 A real lcc DAG for each case executes and returns what the host compiler gives
<!-- AC:END -->
