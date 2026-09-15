---
id: TASK-035
title: >-
  A lexer guard case fails when the smallest ladder point measures too close to
  the baseline
status: To Do
assignee: []
created_date: '2026-09-15 07:47'
updated_date: '2026-09-15 09:21'
labels:
  - poc
  - testing
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/02-lexer/run.sh's fourth contention-guard case -- "a reading that passes under contention is no verdict, not a PASS" -- intermittently fails the whole PoC with exit 1 rather than passing. Observed during task-024, on a tree where poc/02-lexer and poc/lib are untouched.

The guard case forces BUSY_FRACTION and BUSY_CEILING to -1.0 so that every reading counts as contended, and then requires the output to contain both "NO VERDICT" and "unjudged". "unjudged" is printed per ladder STEP, near the end of throughput.py, and is only reached if every ladder point was measured.

There is an earlier refusal that skips it. In throughput.py's measurement loop:

    if work < base_cpu * MIN_BASELINE_RATIO:
        contention.require_quiet([("baseline", base), (f"{nbytes} bytes", point)], "lexer")
        fault(...this ladder point is too small to measure...)

That cliff fires when the smallest point's CPU is not comfortably above the evaluator's start-up baseline -- a timing accident, not a property of the lexer. When it fires under the forced threshold, require_quiet refuses immediately and the run exits 3 having printed NO VERDICT and never the word "unjudged". The guard case sees the right exit status, the wrong text, and reports a harness failure.

Observed output:

    GUARD CASE 'a reading that passes under contention is no verdict, not a PASS' never said "unjudged":
    NO VERDICT: other work occupied up to 1.01 of this machine's 14 cores ... over the -14.00 ...
          baseline:  1.01 cores of other work over 2.0 s  <--
       31025 bytes:  0.69 cores of other work over 2.0 s  <--

Note 1.01 cores: the machine was essentially IDLE. It is the -14.00 threshold, which the guard case itself set, that made the baseline count as contended.

Two candidate fixes, and they are not the same claim:
  * The guard case should accept EITHER refusal path, because both are the refusal it is testing for. Cheapest, and arguably what it meant all along.
  * Or the too-small-to-measure cliff should not consult the contention guard at all when the guard has been told everything is contended, because then it reports the wrong cause.

poc/03-matcher/run.sh and poc/04-assembler/run.sh carry the same guard_case shape and may have the same hole; only the lexer has been seen to hit it, because its smallest ladder point is the one closest to the baseline.

Found while running the gate for task-024.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The guard case passes on an idle machine and on a busy one, whichever refusal path the ladder takes
- [ ] #2 If the too-small-to-measure cliff can still be reported as contention, the diagnostic says which of the two it is
- [ ] #3 The matcher and assembler ladders are checked for the same hole and either fixed or shown not to have it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SECOND SYMPTOM, same family, observed during the task-023/024/025 batch on a tree where poc/02-lexer and poc/lib are untouched.

The lexer ladder rendered a FAIL -- not a NO VERDICT -- on its largest point:

       223124 ->   430998: 1.93x input, 3.30x CPU  SUPERLINEAR
        31025 ->   430998: 13.89x input, 24.07x CPU  SUPERLINEAR
    FAIL: 223124 -> 430998 bytes grew 1.93x but cost 3.30x CPU

The three smaller steps read 1.95x, 1.96x and 1.90x in the same run, so the lexer is linear and the largest point alone was distorted. The contention guard measured 1.97 busy cores at that point -- comfortably under the 3.50 threshold -- so it rendered a verdict against a reading it should not have.

THE GUARD IS MEASURING THE WRONG RESOURCE FOR THAT POINT. busy_cpu_seconds counts other processes' CPU time. The largest ladder point holds a 500 MB working set (decision-001: memory is the binding constraint, not throughput), and what distorts it is memory bandwidth and page-cache pressure from other processes, which barely register as CPU. Three other Claude sessions and a browser were resident at the time. A machine can be quiet by the guard's measure and still be a bad place to measure a half-gigabyte working set.

So the two symptoms have one shape: the guard's threshold is a proxy, and the ladder trusts it at both ends -- refusing when the proxy is high even though nothing is wrong (the first note), and rendering a verdict when the proxy is low even though the reading is distorted (this one). The second is the dangerous direction: it is a red gate on a correct compiler, and the obvious response to a red gate on correct code is to widen the tolerance, which is how a check gets quietly disabled.

Worth considering as part of the fix: a memory-pressure term alongside the CPU one (available memory, or major faults during the window), or dropping the largest point from the ratio when its RSS is within some fraction of the ceiling.

THIRD SYMPTOM, same machinery, same batch, poc/lib still untouched. The contention SELF-TEST failed:

    contention self-test: 2.91 cores busy with nothing of ours running (1.71 before, 4.11 after), 11.23 with 4 spin loops, so 8.32 of 4 were seen
    SELF-TEST FAILED: 4 busy cores read as 8.32, outside 1.6 to 6.8

Look at the baseline it printed: 1.71 cores before the window and 4.11 after. Other work MORE THAN DOUBLED while the self-test was measuring, and the self-test attributes the whole difference to its own four spin loops, so four cores read as 8.32 and it declares its own measurement broken.

It is not broken; it was asked an unanswerable question. selftest.py takes a baseline, adds a known load, measures again, and differences the two. That is only valid if the background is stationary across the window, and on a machine where other sessions come and go it is not. The self-test already brackets its baseline (before and after) and PRINTS both -- it just does not use the spread between them. If 1.71 and 4.11 bracket the baseline, the honest conclusion is that the baseline is unknown to within 2.4 cores, which swamps a 4-core probe, and the right outcome is NO VERDICT rather than SELF-TEST FAILED.

That makes three distinct outcomes from this machinery seen in one batch of work, all on an untouched poc/02-lexer and poc/lib:
  1. a guard case fails because the ladder took the other refusal path (the original note)
  2. a ladder renders a FAIL on a reading distorted by memory pressure the guard does not measure (the second note)
  3. the self-test declares itself broken because the background moved under it (this one)

All three have the same root: a single scalar taken at one moment is being used as if it described a whole window. The bracketing data needed to notice is already collected in case 3 and could be collected cheaply in the others.
<!-- SECTION:NOTES:END -->
