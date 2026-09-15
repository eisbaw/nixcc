---
id: TASK-045
title: >-
  Two more counts that are printed rather than asserted: just poc, and the guard
  stages
status: To Do
assignee: []
created_date: '2026-09-15 16:51'
labels:
  - poc
  - testing
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-040 asserted the mutation count in the four harnesses that have one. Two siblings of the same defect are left, both found by qa-test-runner while reviewing it.

ONE LEVEL UP. The Justfile's poc recipe counts PoCs with [ "$ran" -gt 0 ] and then prints '$ran PoC(s) passed'. Rename or move poc/03-matcher and the suite prints '4 PoC(s) passed' and exits 0 -- task-040's own description, word for word, one level above the thing it fixed. The recipe already refuses when a numbered directory has no run.sh, so the missing half is only the count itself.

ONE STAGE OVER. The guard stage in poc/02-lexer/run.sh runs six guard_case calls plus four standalone cases (blinded, blinded-deep, estimator, drift); poc/03-matcher/run.sh runs six plus one. None of them is counted at all -- the stage ends with a prose echo and no number, so the list can shrink to one and the line reads identically. Two of those cases print MUTATION NOT DETECTED when they fail, so they are mutations by any ordinary reading.

Related but not the same as task-043, which is about those guard-stage copies getting a tmpfs and going through mutant.sh. This is about whether anyone would notice one of them disappearing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 just poc asserts how many PoCs it ran, not merely that it ran more than none
- [ ] #2 The guard stage in poc/02-lexer and poc/03-matcher reports how many guard cases ran and refuses a different number, the way the mutation stage does
- [ ] #3 Each is demonstrated by removing one and watching the suite refuse, not asserted
<!-- AC:END -->
