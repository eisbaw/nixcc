---
id: TASK-039
title: >-
  The contention self-test declares itself broken when the background load moves
  under it
status: To Do
assignee: []
created_date: '2026-09-15 10:48'
updated_date: '2026-09-15 11:13'
labels:
  - poc
  - testing
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Third symptom recorded on task-035, and NOT fixed by the round-robin work there. Seen in the wild:

    contention self-test: 2.91 cores busy with nothing of ours running (1.71 before, 4.11 after), 11.23 with 4 spin loops, so 8.32 of 4 were seen
    SELF-TEST FAILED: 4 busy cores read as 8.32, outside 1.6 to 6.8

The measurement is not broken; it was asked an unanswerable question. poc/lib/selftest.py check 1 takes a baseline, adds a known load, measures again, and differences the two. That is only valid if the background is stationary across the window. Here it went from 1.71 to 4.11 cores while the check ran, and the whole 2.4-core difference was attributed to the four spin loops.

The bracketing data needed to notice is ALREADY collected and already printed -- the before and after readings -- and simply not used. If the two bracket readings are 2.4 cores apart, the baseline is unknown to within 2.4 cores, which swamps a 4-core probe, and the honest outcome is NO VERDICT (exit 3) rather than SELF-TEST FAILED (exit 1).

Order matters: this must not become a way for a genuinely blinded measurement to escape. poc/02-lexer/run.sh and poc/03-matcher/run.sh stub busy_cpu_seconds() out to 0.0 and require SELF-TEST FAILED; with the stub in place both bracket readings are 0.0, so they agree perfectly and the new refusal must not fire. Check that, because that is exactly the hole this kind of change opens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A self-test whose two bracket readings of the baseline disagree by enough to swamp the probe renders NO VERDICT and exits 3, not SELF-TEST FAILED
- [ ] #2 The margin is measured on this machine and cited in the source, not chosen to make a red run go green
- [ ] #3 The blinded-measurement mutation in the lexer and matcher harnesses still reports SELF-TEST FAILED: a stubbed reading agrees with itself, and agreeing with itself must not buy an escape
- [ ] #4 A run that renders NO VERDICT here does not let the PoC that called it report a pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Second defect in the same file, found by qa-test-runner while reviewing task-035. poc/lib/selftest.py check 1 ends with two assertions:

    if not LOAD * LOW <= added <= LOAD * HIGH:  fail(...)
    if during < LOAD * LOW:                     fail(... 'not reporting this machine's load at all')

The second cannot fire in practice. Reaching it means `added >= 1.6', i.e. `during >= quiet + 1.6', and `quiet' is a contention reading which the guard floors at about -0.14 cores. So the second check only bites when `quiet' lands in roughly [-0.14, 0). The defect it names -- a blinded measurement -- reads `added = 0' and is already caught by the first.

A check that cannot fire is the shape this project keeps shipping by accident, so it wants either a reachable form or deleting with the reason recorded. Grouped here rather than fixed during task-035 because changing what check 1 asserts risks the blinded-mutation contract that poc/02-lexer/run.sh and poc/03-matcher/run.sh both depend on: they stub busy_cpu_seconds() to 0.0 and REQUIRE the string 'SELF-TEST FAILED'. Whatever replaces it has to keep that true.
<!-- SECTION:NOTES:END -->
