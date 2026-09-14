---
id: TASK-009
title: 'Decide float support, given the oracle cannot verify it'
status: Done
assignee: []
created_date: '2026-09-14 18:47'
updated_date: '2026-09-14 20:04'
labels:
  - planning
  - frontend
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Float is the part of a C frontend most likely to be wrong, and it is the part our oracle cannot check: symbolic.c's defconst prints floats with %g -- six significant digits -- and pointer constants with %p (host addresses). See decision-004.

RV32I also has no F/D extension, so floats need softfloat on top of the soft mul/div work in task-007.

Decide before the frontend port, not during it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Decision recorded: full float support, integer-only subset, or deferred to a later wave
- [x] #2 If float is in scope, the verification strategy is named, since the lcc oracle cannot serve -- e.g. differential execution against the emulator rather than IR diffing
- [x] #3 If float is out of scope, the frontend rejects float declarations with a clear diagnostic rather than silently miscompiling them
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Decided by the user: defer float to a later wave. Integer-only for now, and the frontend must reject float declarations with a clear diagnostic rather than silently miscompiling them. Recorded as decision-006. The rejection requirement is carried into task-015 so it cannot be forgotten during the frontend port.
<!-- SECTION:FINAL_SUMMARY:END -->
