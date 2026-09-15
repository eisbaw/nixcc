---
id: TASK-038
title: Count cycles rather than seconds in the linearity ladders
status: To Do
assignee: []
created_date: '2026-09-15 10:48'
labels:
  - poc
  - testing
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-008 records that CPU seconds are not a stable unit on a hybrid, boosting CPU: the same 431 kB lexer point costs 1.79 s on a P-core, 2.40 on an E-core and 3.93 on an LP-E core, and 1.60 to 2.16 s on the P-cores alone depending on how warm the package is. Round-robin measurement removes the BIAS that caused, but not the noise: two readings of one point can still be 1.3x apart, and that residue is what the ladders' tolerances have to absorb.

Retired instructions, or cycles, are invariant to both effects. perf_event_open(PERF_COUNT_HW_INSTRUCTIONS) on a child we spawned is permitted at this machine's perf_event_paranoid of 2.

Not built because it is a counter the harness cannot assume it may open: a stricter paranoid level, a container, a VM without PMU passthrough, and the bubblewrap sandbox of task-034 can each take it away. So it would have to be an OPTIONAL sharpening -- used when available, with the current seconds-based reading as the fallback -- and the two must not silently produce different verdicts from the same tree. Design that before building it.

Would let the tolerances be tightened from 1.35 towards the 1.05 the measurement actually supports, which is worth real signal against a quadratic regression.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 poc/lib/contention.py reads retired instructions per child where the counter can be opened, and says in the log which unit a verdict was rendered in
- [ ] #2 A machine that cannot open the counter still gets a verdict, from seconds, and says so
- [ ] #3 The tolerance used is the one measured for the unit in play; a cycles-based run does not silently keep a seconds-based constant
- [ ] #4 Works inside the bwrap sandbox task-034 introduces, or the sandbox says clearly that it has given the counter up
<!-- AC:END -->
