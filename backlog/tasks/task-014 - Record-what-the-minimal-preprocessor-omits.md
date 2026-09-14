---
id: TASK-014
title: Record what the minimal preprocessor omits
status: To Do
assignee: []
created_date: '2026-09-14 20:04'
labels:
  - frontend
  - preprocessor
  - docs
dependencies:
  - TASK-013
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up required by decision-005. The minimal cpp deliberately skips parts of the standard. Those omissions must be written down and diagnosed, not discovered by a user whose program silently fails to compile.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every deliberate omission is listed in the README's limits section
- [ ] #2 Encountering an unsupported directive produces a clear diagnostic naming it, never silent wrong output
- [ ] #3 A test asserts the diagnostic fires for each documented omission
<!-- AC:END -->
