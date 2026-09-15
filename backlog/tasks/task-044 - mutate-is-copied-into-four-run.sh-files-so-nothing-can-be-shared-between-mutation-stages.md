---
id: TASK-044
title: >-
  mutate() is copied into four run.sh files, so nothing can be shared between
  mutation stages
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
poc/02-lexer, poc/03-matcher, poc/04-assembler and poc/05-loop each carry their own copy of mutate(), the names/fragments/outputs arrays, the distinctness loop and now the declared-count assertion. poc/02-lexer's and poc/04-assembler's copies of mutate() are byte-identical; poc/03-matcher's adds the exit-9 CONTROL LOST arm task-041 introduced; poc/05-loop's trims the last error: line.

Two consequences, both found while reviewing task-040.

First, there is nowhere to put a statement about a mutation TABLE. task-040 put the reasoning for the declared count in poc/lib/mutant.sh, which runs ONE mutation and never sees a table. It is the only shared file, so it is where the paragraph went, and the comment says so rather than pretending otherwise.

Second, a claim in that comment cannot be enforced: 'the four harnesses that use this each declare a count today. Nothing checks that a fifth will.' task-027 and task-028 both instruct their implementer to copy mutate() from an existing harness, and neither mentions the declared count -- so the next harness written to those instructions will not have one, and a comment in poc/lib will keep reading clean.

The fix is poc/lib/mutate.sh: mutate(), the three arrays, the distinctness loop and a declared-count helper, sourced by all four, with the per-harness differences passed in rather than forked. Then the reasoning lives beside the thing it describes and the count is a parameter of a shared function, which nothing can forget to write.

Not done in the task-040 batch, which was three bounded harness fixes and was already over.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 mutate(), the mutation tables and the distinctness loop live in poc/lib and are sourced by all four harnesses; the per-harness differences are arguments, not forks
- [ ] #2 Every harness that runs mutations declares its count, and that is true by construction rather than by a comment saying so
- [ ] #3 Every mutation the four harnesses detect today is still detected, with the same distinct fragment, and the counts are unchanged
<!-- AC:END -->
