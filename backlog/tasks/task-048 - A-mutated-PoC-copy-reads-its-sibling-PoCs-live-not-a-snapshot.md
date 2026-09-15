---
id: TASK-048
title: 'A mutated PoC copy reads its sibling PoCs live, not a snapshot'
status: To Do
assignee: []
created_date: '2026-09-15 18:55'
labels:
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/05-loop/run.sh and poc/06-constants/run.sh both symlink sibling PoC directories next to the mutated copy, because the code under test reaches them by relative path (05-loop needs 01/03/04, 06-constants needs 02-lexer for explode). The symlink points at the LIVE tree.

Two consequences, both only visible during the seven-odd minutes a gate takes. An edit to poc/02-lexer while the gate runs silently changes what every mutation in 06-constants evaluates. And poc/lib/mutant.sh's exit-122 check is `diff -rq "$poc" "$mut"' against the live source too, so an edit to the PoC under test can make the 'this mutation edited nothing' fault fire, or fail to fire, for no reason connected to the mutation.

Copying the siblings instead was rejected on purpose -- 05-loop's comment says a copy is a copy that could go stale -- so the fix is probably to snapshot once per run rather than per mutation, or to bind the siblings read-only inside the mutation's own bwrap. Low probability, but it is the class of thing that produces one unreproducible red gate and a day of looking in the wrong place.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A mutation run cannot see an edit made to the tree after the harness started
- [ ] #2 The fix costs no extra copy per mutation
<!-- AC:END -->
