---
id: TASK-041
title: >-
  Give the matcher's semantic mutation a tmpfs too, by moving build_and_run into
  a script
status: In Progress
assignee: []
created_date: '2026-09-15 14:28'
updated_date: '2026-09-15 16:14'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Move build_and_run out of poc/03-matcher/run.sh into poc/03-matcher/build-and-run.sh TREE NAME OUT, following poc/04-assembler/gnu-diff.sh exactly: a script under the tree, so the MUTATED copy is the one that runs. OUT is an argument because the main execution stage passes the real poc directory as TREE and must not write into the repository.
2. Point the main execution loop at the script. Its output and its checks are unchanged, so the host-compiler oracle and cases.nix comparison stay where they are.
3. Turn the semantic mutation into an ordinary mutate() call, so it goes through poc/lib/mutant.sh and gets a tmpfs. Its run snippet keeps the control in front of the claim: if check.nix has started catching the divide-by-itself mutation the snippet says CONTROL LOST and cannot produce the fragment, so a lost control shows up as a red suite and never as a detection.
4. Drop the magic 72: read the expectation out of cases.nix the way the main loop does.
5. Prove the property survived the move -- check.nix still passes the mutated tree and the emulator still returns the wrong answer -- by running it, not by assuming.
6. Then task-034 criterion 3 holds with no exception, and task-034 goes Done.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IMPLEMENTED.

poc/03-matcher/build-and-run.sh TREE NAME OUT is the old build_and_run function, modelled on poc/04-assembler/gnu-diff.sh, which solved the identical problem for the same reason. OUT is an argument rather than a path under TREE, which is where gnu-diff.sh puts its scratch: during a mutation TREE is a tmpfs and either would do, but the main execution stage passes the real PoC directory and that must not be written into. Verified with a find snapshot either side of a real run -- the tracked tree is byte-identical afterwards.

The semantic mutation is an ordinary mutate() call now, so it goes through poc/lib/mutant.sh and gets a tmpfs. Three things improved on the way, none of them the point of the task:

  * The old "did the sed apply" guard was a grep for 'mv a1,%0' in rules.nix, which would have passed had any OTHER rule contained that string. mutant.sh's diff -rq (exit 122) is strictly stronger -- it proves the tree changed, not that a string is present.
  * The control now runs check.nix on the MUTATED tree inside the namespace. It used to run on a copy outside one.
  * The expectation comes out of cases.nix instead of the literal 72 that was written in run.sh.

REVIEW FOUND FOUR THINGS, all fixed before the commit.

  * exit 9 from the control was a status mutate() did not know about, so a lost control was recorded as a DETECTION and only went red later, when the fragment check noticed the CONTROL LOST text did not contain "but cases.nix expects 72". Red for a coincidence rather than a mechanism -- and the obvious improvement to that message, quoting the expected number in it, would have made a lost control read as a clean detection. mutate() has a 9) arm now that names it. Demonstrated end to end by forcing the control to fail in a copy of the tree: the harness prints CONTROL LOST for mutation '...' with check.nix's own diagnostic under it, and exits 1.
  * The control discarded nix's stderr and then asserted a cause. A failing nix eval means check.nix caught the mutation OR check.nix is broken, and the redirect threw away the only thing that tells those apart. It is captured and printed now.
  * The non-empty guard on expr_want could not fire: under set -e a failing nix eval aborts the harness before it, and a --raw eval that succeeds cannot print nothing. Removed, with the reason recorded where it stood.
  * "|| true" on the objdump pipeline masked objdump's own failure as well as grep's zero match, so an objdump that could not read the object reported "only 0 instructions in the assembled object" -- a claim about an object it never saw. Split.

AND A MUTATION ADDED, which is the half of poc/04-assembler's precedent that moving the function does not give you for free. gnu-diff.sh is reachable by a mutation AND has one aimed at it; build-and-run.sh was reachable and had none, so "the mutated copy is the one that runs" was argued rather than shown. "harness: the semantic oracle stops running the program to completion" cuts the emulator's step budget from 200000 to 20 in build-and-run.sh, and the program then stops with reason "budget" instead of reaching its exit syscall -- which can only happen if the mutated copy ran. The matcher suite is 36 mutations now.

Two comment overclaims corrected, both the same species task-034's notes already caught in this spot. "The one check in the suite a mutation could not reach" is false -- no mutation anywhere in poc/ edits a run.sh, so stage 1's DAG diff, the host-compiler cross-check and mutate()'s own distinctness loop are all still out of reach. And build-and-run.sh is not a check: it reports, and both callers judge. Its header says so now, including that a program which faulted or ran out of budget comes back as a clean exit 0 with a reason that is not "exit".

The instruction floor of 5 moved verbatim and is now described honestly: it catches "essentially nothing came out" and nothing finer -- the smallest function in the corpus is 29 instructions and expr is 66.
<!-- SECTION:NOTES:END -->
