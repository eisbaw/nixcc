---
id: TASK-043
title: 'The guard stage still copies poc/lib into single-use directories, not tmpfs'
status: To Do
assignee: []
created_date: '2026-09-15 16:25'
labels:
  - poc
  - testing
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-041 put the last mutate() mutation on a tmpfs, so every one of the 110 mutations in the mutate() stage now gets a filesystem of its own by construction. The GUARD stage does not, and it is the same shape at a smaller scale.

poc/02-lexer/run.sh makes four copies of poc/lib into plain directories -- $blinded, $blinded_deep, $estimator, $drift -- seds each one, and runs selftest.py out of it. poc/03-matcher/run.sh makes one ($blinded). Both harnesses also copy the whole PoC per guard_case. Two of those copies print 'MUTATION NOT DETECTED' when they fail, so calling them something other than mutations is a stretch.

Each name is used exactly once per run and the scratch root is itself a tmpfs the kernel reclaims, so nothing can actually leak between runs today. What is missing is the by-construction part: these use a plain mkdir, a hand-rolled grep standing in for mutant.sh's exit 122, and a hand-rolled 'did it pass' test standing in for mutate(). They are the pattern task-034 replaced, surviving in the stage that was not looked at.

Found by qa-test-runner while reviewing task-041, which is exactly where it should have been found -- it was checking whether task-034's criterion 3 could be ticked without an exception. It was ticked on the reading that criterion 3 means the mutate() stage, which is what its author was counting when they wrote '106 of 107'. If it is read more widely, this is the remaining work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The guard-stage copies in poc/02-lexer and poc/03-matcher go through poc/lib/mutant.sh, or through something that gives them the same three properties: a tmpfs, an exit-122 proof that the edit applied, and a caller that cannot mistake a harness fault for a detection
- [ ] #2 The four things those guard cases currently prove are each still proved, and each still fails when it should: a blinded measurement, a blinded measurement taken through check 1, a non-median estimator, and a baseline that moves under the probe
- [ ] #3 No hand-rolled 'did the sed apply' grep is left where mutant.sh's diff would do the job
<!-- AC:END -->
