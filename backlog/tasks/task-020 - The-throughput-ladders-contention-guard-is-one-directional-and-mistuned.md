---
id: TASK-020
title: The throughput ladders' contention guard is one-directional and mistuned
status: Done
assignee: []
created_date: '2026-09-14 21:31'
updated_date: '2026-09-15 05:16'
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
- [x] #1 The contention diagnosis is made from load sampled across the measurement, not once before it
- [x] #2 A verdict reached on a busy machine is reported as no verdict, whether it passed or failed
- [x] #3 The threshold is justified by a measurement recorded in the file, as the tolerances already are
- [x] #4 Ten consecutive 'just e2e' runs on an otherwise idle machine are green
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed in 2a6707e.

SHAPE. poc/lib/contention.py owns both the measurement and the decision; the two ladders ask it and carry no copy of the threshold. poc/lib/selftest.py proves the measurement works. Each run.sh runs the self-test, a mutation that blinds the measurement, and four cases over the real ladder (a reading forced to fail and one forced to pass, each with contention discounted and declared).

WHAT THE MEASUREMENT IS. /proc/stat's system-wide busy counter sampled around every ladder point, minus that point's own children's CPU, over the window's wall time: cores' worth of OTHER work. The baseline counts as a point because it is subtracted from all of them.

GOTCHAS, in the order they cost time.

1. A contention reading is only as good as its window. /proc/stat counts whole ticks per core, so on 14 cores at 100 Hz a delta can be out by 0.14 core-seconds -- a whole core of error over the 0.14 s the start-up baseline takes. best() pads a short window with a sleep. The FIRST attempt filled it with extra child runs instead, which deepens min() for the short points only, depresses the small end of a ladder and inflates its ratios: an instrument that manufactures the superlinearity it is looking for, and a silent recalibration of tolerances measured at a fixed repeat count.

2. Clamping a negative reading to 0.0 is fail-open. It turns 'the kernel's counters and this child's rusage contradict each other' into 'the machine was perfectly idle'. Now a fault beyond two ticks per core of skew -- and that fault is what catches a sign error in the subtraction.

3. Four cases that force the DECISION cannot see a broken MEASUREMENT. With busy_cpu_seconds() stubbed to return 0.0, all four still pass. That is why selftest.py exists (4 spin loops must be seen; 4 cores burnt by our own child must not) and why run.sh applies exactly that stub and requires it to be caught.

4. Order in run.sh matters more than it looks. The ladder runs LAST: exit 3 under set -e used to take the lexer's ten mutation tests and the entire matcher PoC down with it, and none of those need a quiet machine. 'just poc' now carries on past exit 3 and reports a count at the end, so a refusal costs one ladder rather than the rest of the suite.

5. The copied harnesses need the guard beside them: $work/lib for the mutation copies, and a per-case $guard/lib for the guard cases, which is what lets a case patch the REAL constant in contention.py rather than a per-ladder alias that could go stale while the checks kept passing.

6. Measured, not assumed: our own work does not inflate the reading. Foreign occupancy sampled with nothing of ours running read 3.7-4.5 cores; sampled around our own evaluator runs in the same minute, 3.7-4.3. Three consecutive 500 MB evals leave no tail -- readings after them (1.68-1.95) match cold ones (1.71-1.92). The elevated readings seen in some gate runs are this machine's other jobs, not ours.

7. THRESHOLD, and why not the number the table points at. Seventeen ladder runs under controlled load: every reading at or below 3.9 cores left the worst adjacent step within 1.05 of linear, the first excursions past 1.15 are at 4.1, and at 6.4 the distortion alone reads 1.36 against a 1.35 tolerance -- a FAIL from contention, matching the one this task was filed for. The boundary is between 3.9 and 4.1; BUSY_CEILING is 3.5, BELOW it, because only three of the seventeen runs landed under 4.0 (the clean side is the thinly sampled one) and because refusing a verdict costs a re-run while rendering a wrong one costs a wrong decision about the architecture. It was not chosen to make a gate green: at the time it was set, this machine idled at 3.6-4.7 cores and refused either way.

8. Exit statuses now mean something: 1 FAIL, 2 HARNESS FAULT, 3 NO VERDICT. A bare 'import contention' failure and any uncaught exception used to exit 1, which in these harnesses reads as 'the lexer is superlinear'; both are now faults.

9. COST. 'just e2e' went from about 2 minutes to 4m17 on a quiet machine, nearly all of it the four guard cases running a ladder four extra times. Separable in principle: extracting a pure judge(rows, quiet, tolerances) would let the same four cases run against synthetic rows in milliseconds, and would let the measurement self-test cover what is left. Not done here -- it is a refactor of both ladders, not a fix to the guard.

NOT FIXED, deliberately. iowait counts as idle, so a machine saturating the memory bus through writeback reads quiet; counting it would be conservative but iowait is a per-CPU heuristic that is not monotonic, so it is recorded as the known hole rather than fed into a threshold. And there is still no Python linter in the dev shell: statix, deadnix and shellcheck cover Nix and shell, nothing covers the four .py files. ruff would have caught the unused imports this change churned.

ACCEPTANCE EVIDENCE. Ten consecutive 'just e2e' runs green, 01:54 to 02:36, each rendering both ladders' verdicts (lexer PASS over a 13.9x span, matcher PASS over 8.1x, 10 and 22 mutations detected, lint clean, 3 PoCs passed), measured against 2.10 to 3.45 cores of other work. An earlier batch of six, while another project's jobs were on the machine, went four green and two NO VERDICT at 3.82 and 4.09 cores -- the guard being conservative rather than wrong, since the distortion measured at that load is 1.05 to 1.19 against a 1.35 tolerance.

ORCHESTRATOR: the runaway is dead. PID 2585897, traceviz_dump.sh from the retimer-sim project, had been at 98.5% CPU for 4 days 7 hours, orphaned to PPID 1 with its originating session long gone. Killed with the user's explicit authorisation on 2026-09-15; load average fell from the 9-20 range to 3.62/4.34/4.04 immediately.

This matters for the threshold recorded above. BUSY_FRACTION was set to 0.25 (3.5 of 14 cores) against a machine that permanently carried a full core of unrelated work, and the 17-run measurement table behind that choice was taken under the same condition. The threshold is not wrong -- it was deliberately set below the observed distortion boundary of 4.1 cores, and that reasoning holds regardless -- but the 'roughly one gate run in three refuses' figure was measured in a world that no longer exists and should be expected to improve. Do not retune on this basis without re-measuring; the guard failing safe costs a re-run, while a wrong verdict costs a wrong decision.

The iowait hole is unaffected: a writeback-saturated machine still reads quiet.
<!-- SECTION:NOTES:END -->
