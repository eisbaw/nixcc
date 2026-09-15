---
id: TASK-050
title: 'Float support, when the integer compiler works end to end'
status: To Do
assignee: []
created_date: '2026-09-15 19:05'
labels:
  - frontend
  - deferred
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Placeholder for a real deliverable that nothing tracked. decision-006 deferred float to a later wave and said "revisit once the integer compiler works end to end"; task-009 was the DECIDE task and is closed, so that sentence was the only record.

NOT ACTIONABLE YET and deliberately unprioritised. Do not pick this up while any vertical slice (027-029) is open.

When it is picked up, two things from decision-006 and decision-004 apply: the lcc oracle cannot verify float, because symbolic.c prints floats with %g at six significant digits, so verification must be differential EXECUTION against the emulator rather than IR diffing. And RV32I has no F/D extension, so this needs a softfloat runtime layered on task-007.

Until then, task-015 requires the frontend to REJECT float with a clear diagnostic rather than silently miscompile it.
<!-- SECTION:DESCRIPTION:END -->
