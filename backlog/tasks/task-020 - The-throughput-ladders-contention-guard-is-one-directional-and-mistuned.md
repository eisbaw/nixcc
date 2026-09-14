---
id: TASK-020
title: The throughput ladders' contention guard is one-directional and mistuned
status: To Do
assignee: []
created_date: '2026-09-14 21:31'
labels:
  - poc
  - testing
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Both timing ladders -- poc/02-lexer/throughput.py and poc/03-matcher/scale.py -- judge linearity on the child's own CPU time and downgrade a SUPERLINEAR verdict to a measurement failure when the machine is busy: 'load > cores * BUSY_FRACTION', with BUSY_FRACTION = 0.5.

Two problems, both observed rather than theorised. During review, 'just e2e' failed once in two consecutive attempts on this machine -- the lexer ladder read '223124 -> 430998: 1.93x input, 2.99x CPU SUPERLINEAR' at a one-minute load average of 6.6 on 14 cores. The threshold is 7.0, so the guard missed by 0.4 and reported a hard FAIL for exactly the reason it was written to excuse. An unrelated Renode process and a rustdoc build were running. Re-run alone, the same ladder passed, but end-to-end at 1.43 against its 1.5 ceiling where the docstring records 0.88-1.02 for a quiet machine.

The second problem is the shape, not the number: the guard can only downgrade a FAIL. A PASS measured under contention is reported as a clean pass with no note, so the ladder is loud about false failures and silent about weak successes.

Fixing this by raising BUSY_FRACTION would be tuning a number to make a symptom go away. The measurement wants re-doing: either take the load reading around each ladder point rather than once at the start, or sample it and refuse to render any verdict when the machine was busy during the run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The contention diagnosis is made from load sampled across the measurement, not once before it
- [ ] #2 A verdict reached on a busy machine is reported as no verdict, whether it passed or failed
- [ ] #3 The threshold is justified by a measurement recorded in the file, as the tolerances already are
- [ ] #4 Ten consecutive 'just e2e' runs on an otherwise idle machine are green
<!-- AC:END -->
