---
id: TASK-040
title: 'Assert the mutation COUNT in the lexer, matcher and assembler harnesses'
status: To Do
assignee: []
created_date: '2026-09-15 14:07'
labels:
  - poc
  - testing
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/05-loop/run.sh ends its mutation stage with a floor on how many mutations ran. poc/02-lexer, poc/03-matcher and poc/04-assembler print ${#names[@]} without asserting it, so a mutate call that was dropped, commented out, or lost to a bad merge would take the count down and nothing would notice -- the suite would report a smaller number just as confidently.

Found by qa-test-runner while reviewing task-034. Pre-existing rather than introduced there.

This is the same shape as two defects fixed during task-034: an absence check with no binaries to look for, and a grep over a file list that had gone stale. Both print their cleanest line when they have stopped testing. A count that is reported rather than asserted is that shape with the alarm removed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 poc/02-lexer, poc/03-matcher and poc/04-assembler each refuse to pass if fewer mutations ran than the floor, the way poc/05-loop already does
- [ ] #2 Each floor is the number that runs today, so lowering it is a deliberate edit rather than a silent drift
- [ ] #3 A deliberately removed mutate call makes the harness fail, and that is demonstrated rather than asserted
<!-- AC:END -->
