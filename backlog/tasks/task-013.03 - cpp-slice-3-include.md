---
id: TASK-013.03
title: 'cpp slice 3: #include'
status: To Do
assignee: []
created_date: '2026-09-16 17:28'
updated_date: '2026-09-16 17:28'
labels:
  - frontend
  - preprocessor
  - slice
dependencies:
  - TASK-070
  - TASK-013.02
parent_task_id: TASK-013
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The last preprocessor slice, blocked on task-070 because it cannot be built until header provenance and the purity question are settled.

Scope: both #include forms, the resolution strategy task-070 chooses, nesting, and include guards working as a consequence of slice 1 rather than as a special case.

WATCH THE MEMORY. A preprocessed translation unit pulling in real headers is far larger than anything measured so far: task-027 measured 142 kB of peak RSS per source line for many small functions and 359 kB for one large one, so 1 GB arrives around 2800 lines in a single function. Measure an include graph before assuming it fits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both #include forms resolve per task-070's decision
- [ ] #2 Nested includes and include guards work, the guards falling out of slice 1 rather than being special-cased
- [ ] #3 Runs inside nix flake check, where --impure is unavailable
- [ ] #4 Memory measured on a real multi-file include graph and recorded, not assumed
- [ ] #5 A C program using #include compiles from .c and RUNS end to end
<!-- AC:END -->
