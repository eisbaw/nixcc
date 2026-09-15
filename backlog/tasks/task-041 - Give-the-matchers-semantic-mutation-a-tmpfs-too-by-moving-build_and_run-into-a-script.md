---
id: TASK-041
title: >-
  Give the matcher's semantic mutation a tmpfs too, by moving build_and_run into
  a script
status: To Do
assignee: []
created_date: '2026-09-15 14:28'
labels:
  - poc
  - testing
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The last mutation in this tree that does not get a filesystem of its own. poc/03-matcher/run.sh's 'the divide libcall divides x by itself' interleaves with build_and_run, a shell function defined in run.sh, so it cannot be handed to poc/lib/mutant.sh the way the other 106 mutations are. It gets a directory used exactly once instead, which is fresh because nothing else uses that name -- but a directory is not a tmpfs, and task-034's criterion #3 asks for a tmpfs.

The fix is known and has already been done once in this tree for exactly this reason. poc/04-assembler had the same problem with gnu_diff: the mutation stage runs in a mount namespace where a function defined in run.sh is out of scope. It was briefly solved with 'export -f gnu_diff', which worked and was wrong -- the child then ran the PARENT's copy, so that function became the one part of the differential path a mutation could not reach. It is poc/04-assembler/gnu-diff.sh now, called from inside the mutated tree, so the mutated copy is what runs.

build_and_run wants the same treatment: its own script taking the tree and the case name, called by both the main execution stage and the semantic mutation. Then the semantic mutation is an ordinary mutate() call and criterion #3 is met without an exception.

Two things to be careful of. build_and_run is the ONLY semantic oracle in the matcher suite -- it assembles, links and executes in the Nix emulator -- so breaking it while moving it would remove the check that catches what check.nix cannot, which is the whole reason that mutation exists. And moving it means the MUTATED copy runs during mutations, which is the point, but it also means a mutation that corrupts build_and_run itself must still be detected rather than silently passing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 poc/03-matcher's semantic mutation goes through poc/lib/mutant.sh like every other mutation in the tree, and so gets a tmpfs of its own
- [ ] #2 build_and_run lives in its own script, called from the mutated tree, so a mutation that edits it is the copy that runs
- [ ] #3 The semantic mutation still fails when check.nix passes it -- the property it exists to demonstrate is re-proved, not assumed to survive the move
- [ ] #4 task-034 criterion #3 can then be checked with no exception attached
<!-- AC:END -->
