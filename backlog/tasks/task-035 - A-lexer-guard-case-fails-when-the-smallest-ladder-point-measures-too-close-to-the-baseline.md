---
id: TASK-035
title: >-
  A lexer guard case fails when the smallest ladder point measures too close to
  the baseline
status: To Do
assignee: []
created_date: '2026-09-15 07:47'
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
