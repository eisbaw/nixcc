---
id: TASK-020
title: The throughput ladders' contention guard is one-directional and mistuned
status: In Progress
assignee: []
created_date: '2026-09-14 21:31'
updated_date: '2026-09-14 22:57'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure contention around every ladder point instead of reading a one-minute load average once before the run: sample /proc/stat's system-wide busy counter around each point, subtract the point's own children's CPU, and report the cores' worth of OTHER work that ran during that window. A one-minute mean cannot see a burst that arrives mid-run; a delta over the window can.
2. Attribute the reading to the WHOLE window of a point -- every repeat and the gaps between them -- rather than to the repeat whose CPU number won the min(). That is the conservative direction: if load arrived for part of the window and the cheapest repeat missed it, the point still counts as contended.
3. Pad a short window with a sleep rather than with extra runs. The reading needs a window of its own (/proc/stat counts whole ticks per core, which over the 0.14 s start-up baseline is an error of a whole core), but adding runs would deepen the min() for the short points only, biasing the small end of a ladder down and its ratios up.
4. Put the measurement AND the decision in one shared module (poc/lib/contention.py) imported by both ladders, so the guard cannot be fixed in one and left broken in the other.
5. Refuse in BOTH directions: when any point, baseline included, was measured against more contention than the threshold, print the rows and ratios as data, mark every step 'unjudged', and exit 3 -- neither PASS, nor FAIL (1), nor HARNESS FAULT (2). run.sh turns exit 3 into a NO VERDICT banner rather than a failure.
6. Keep the contention-independent checks out from behind the guard: peak RSS is a fact about one run rather than a comparison between two, and it is the budget decision-001 closes on, so a memory ceiling still FAILs on a busy machine.
7. Justify the threshold by measurement recorded in the module: foreign occupancy against the worst step's ratio-of-ratios across seventeen ladder runs under controlled load.
8. Prove the guard MEASURES, not just that it decides: poc/lib/selftest.py puts a known number of busy cores on the machine and checks they are seen, and that a core burnt by our own child is not. run.sh then stubs the measurement out and requires the self-test to catch it -- without that, all four decision cases pass against a guard that reports a perfectly idle machine.
9. Prove the guard REFUSES in both directions with four cases and their controls: a reading forced to fail and one forced to pass, each with contention discounted and declared.
10. Ten consecutive 'just e2e' runs.
<!-- SECTION:PLAN:END -->
