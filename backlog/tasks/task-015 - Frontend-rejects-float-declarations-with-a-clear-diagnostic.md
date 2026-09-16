---
id: TASK-015
title: Frontend rejects float declarations with a clear diagnostic
status: Done
assignee: []
created_date: '2026-09-14 20:04'
updated_date: '2026-09-16 08:22'
labels:
  - frontend
  - diagnostics
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Required by decision-006, which defers float to a later wave. A frontend that quietly accepts `double` and emits wrong code is worse than one that refuses it, and float is the one surface with no oracle behind it (symbolic.c prints floats with %g, six significant digits).

Filed separately so the rejection cannot be forgotten during the frontend port.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 float, double and long double declarations are rejected with a diagnostic naming the limitation and pointing at decision-006
- [x] #2 Rejection covers declarations, casts, literals and implicit promotions -- not just the declaration keyword
- [x] #3 A test asserts the diagnostic fires for each, so the guard is proven to bite rather than assumed
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Already satisfied by slice 1's parser; verified rather than assumed. Declarations, casts, literals and extern returns all refuse with a diagnostic naming decision-006: 'double declarations are deferred (decision-006, task-015)' and 'floating-point constant 1.5: float support is deferred'. Closed on evidence, per the COMPASS consult's flag that it read stale.
<!-- SECTION:FINAL_SUMMARY:END -->
