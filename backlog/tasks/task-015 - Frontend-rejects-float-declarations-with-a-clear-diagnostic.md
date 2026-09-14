---
id: TASK-015
title: Frontend rejects float declarations with a clear diagnostic
status: To Do
assignee: []
created_date: '2026-09-14 20:04'
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
- [ ] #1 float, double and long double declarations are rejected with a diagnostic naming the limitation and pointing at decision-006
- [ ] #2 Rejection covers declarations, casts, literals and implicit promotions -- not just the declaration keyword
- [ ] #3 A test asserts the diagnostic fires for each, so the guard is proven to bite rather than assumed
<!-- AC:END -->
