---
id: TASK-042
title: >-
  A machine with too few free cores to host the probe is a HARNESS FAULT, which
  is red
status: To Do
assignee: []
created_date: '2026-09-15 14:51'
updated_date: '2026-09-15 15:28'
labels:
  - poc
  - testing
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/lib/selftest.py refuses to run check 1 when fewer than LOAD + 2 cores are free, and calls contention.fault() to do it -- exit 2, HARNESS FAULT, which `just poc' treats as a defect and stops the whole suite on.

Its own message says otherwise: 'Not a verdict on anything -- re-run on a less busy machine.' That is the definition of the third outcome this tree already has. A machine carrying 10 cores of somebody else's work is not a broken harness, and on a 14-core machine that is all it takes: 14 - 10 = 4, which is under LOAD + 2 = 6.

Found while fixing task-039, which fixed the neighbouring shape -- a background that MOVES under the probe now renders NO VERDICT rather than SELF-TEST FAILED. A background that is merely too big for the probe to fit beside is the same family and still reports as a defect. Filed rather than fixed because task-039's criteria name the moving case specifically and that batch was bounded.

The change looks like one line -- contention.fault(...) becomes the no_verdict(...) helper task-039 added -- but it is not only that: exit 3 from the self-test now has to mean the same thing at every caller, and poc/02-lexer, poc/03-matcher and poc/04-assembler each carry it to their last line rather than propagating it. So the fix is cheap and the CHECK that it did not become a way for a real failure to escape is not.

Do not fix it by lowering LOAD. Four spin loops is what the accept band was measured against (see the figures in poc/lib/selftest.py), and a smaller probe is a smaller signal against the same noise.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The self-test renders NO VERDICT and exits 3 on a machine with too few free cores to host the probe, rather than HARNESS FAULT
- [ ] #2 A genuinely broken harness -- no /bin/sleep, a missing scratch directory, a child that did not burn the CPU it was asked to -- still exits 2
- [ ] #3 The blinded-measurement mutation in the lexer and matcher harnesses still reports SELF-TEST FAILED: a busy machine must not become a way for a stubbed reading to escape
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
A second instance of the same family, found by mped-architect while reviewing task-039. poc/lib/selftest.py check 2 calls contention.fault() -- exit 2, HARNESS FAULT -- when the child it asked to burn OWN cores used less than three quarters of that CPU. On a loaded machine an under-burning child is exactly as transient as the 1.74-core spike that the retakes three lines below it exist to absorb, and it is denied that mechanism. It should either be retaken like the reading it guards, or be the third outcome; it should not be a hard red.
<!-- SECTION:NOTES:END -->
