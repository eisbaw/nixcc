---
id: TASK-065
title: 'Rung-1 hygiene wave: batch the harness follow-ups'
status: To Do
assignee: []
created_date: '2026-09-16 08:22'
labels:
  - harness
  - hygiene
  - wave
dependencies:
  - TASK-058
  - TASK-059
  - TASK-060
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Batches six harness-hygiene tasks into one, to be run at a wave boundary rather than trickled between features: task-037 (tryEval cannot catch attribute-missing), 042 (too-few-cores is a HARNESS FAULT, which is red), 043 (guard stage not on tmpfs), 044 (mutate() copied into four run.sh files), 045 (two counts printed rather than asserted), 048 (a mutated PoC copy reads its siblings live).

COMPASS flagged these as cornerstone-avoidance risk: seven rung-1 hygiene tasks sat open while FOUR rung-2 language features had no task at all. None of the six is wrong -- but the soil already grows things, and trickling them between features is rung-1 gold-plating.

Run this after the compound-type wave, not before.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All six constituent tasks are either done or explicitly re-deferred with a reason
- [ ] #2 Run as one cycle at a wave boundary, not split across feature work
<!-- AC:END -->
