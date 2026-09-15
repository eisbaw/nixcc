---
id: TASK-034
title: Run harness scratch work in a bwrap tmpfs instead of deleting it
status: In Progress
assignee: []
created_date: '2026-09-15 07:28'
updated_date: '2026-09-15 14:29'
labels:
  - infrastructure
  - harness
  - hermeticity
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace every delete-shaped command in the harnesses with a bubblewrap sandbox whose scratch filesystem is a tmpfs, so temporary state is reclaimed by the kernel on exit and no cleanup command is needed.

Motivation is twofold and the second is the bigger win:

1. Delete-shaped commands (rm -rf, and the cleanup traps in all five harnesses) trigger a security rules check engine on this machine. A tmpfs removes the need rather than working around it, and leaves no mutation behind by construction -- the current `rm -rf "$mut"; cp -r "$poc" "$mut"` pattern can leave stale files if the remove half ever partially fails.

2. HERMETICITY. poc/05-loop currently proves "no external toolchain" by building a PATH holding one symlink to nix, and its own author flagged that this is "closer to a demonstration than a proof". Binding only nix's runtime closure makes it a proof: the toolchain does not exist in the filesystem at all, not merely off PATH.

Measured feasibility (probed 2026-09-15, bubblewrap 0.11.0):
- tmpfs inside bwrap: works, 16 GB, host /tmp invisible, vanishes on exit.
- /proc/stat and nproc read the HOST inside bwrap -- values match, nproc 14. This was the make-or-break: poc/lib/contention.py reads /proc/stat to decide whether a linearity verdict means anything, and a namespaced /proc would have silently measured the wrong machine. It does not.
- `nix eval` works inside, including a real PoC eval (01-encoder/must-fail.nix returned its usual result) with a tmpfs HOME.
- nix's runtime closure is 63 store paths and contains NO compiler or assembler binaries -- the three that match gcc/binutils by name are libgcc and libstdc++ runtime libraries. So a closure-only bind genuinely leaves no toolchain reachable.

bwrap, not podman. Both are installed (podman 5.7.0), but bwrap is what nix itself sandboxes with: unprivileged user namespaces, no daemon, no images, no storage driver, and milliseconds of startup. That last point matters -- `just e2e` is already 5m40 and mutation testing spawns a sandbox per mutation, so podman's per-invocation cost would be paid dozens of times for no benefit here.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No delete-shaped command remains in any harness: no rm, rmdir, truncate, git clean, git reset --hard. Grep proves it
- [x] #2 Scratch state lives on a tmpfs inside bwrap and is reclaimed on exit with no cleanup command and no EXIT trap
- [ ] #3 Mutation testing gets a fresh tmpfs per mutation, so stale state between runs is impossible by construction rather than by remembering to clear it
- [x] #4 poc/lib/contention.py still reads the host's /proc/stat and nproc from inside the sandbox; a test asserts the values match the host, since a silently namespaced /proc would invalidate every linearity verdict
- [x] #5 poc/05-loop's no-toolchain stage binds only nix's runtime closure, so riscv32-none-elf-as and gcc are unreachable by absolute path and not merely absent from PATH. Its comment is updated from 'demonstration' to what it now actually proves
- [x] #6 Wall-clock cost of just e2e measured before and after and recorded; a tmpfs HOME disables nix's eval cache, so if that slows things the cache is bound read-only instead of being left to regress silently
- [x] #7 A machine without unprivileged user namespaces gets a clear diagnostic naming the requirement, not a confusing failure
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. poc/lib/sandbox.sh, sourced first by every run.sh: probe bwrap, then re-exec the caller inside a sandbox that binds the host but puts a tmpfs over /tmp, and set $work under it. No trap, no cleanup, no delete. NIXCC_SCRATCH lets a debugger bind a real directory instead, which is what replaces keep-on-failure.
2. Replace every rm -rf in the five harnesses: the EXIT traps, the per-guard-case and per-mutation wipes, and the two trap 'rm -rf' one-liners in 05-loop. Mutations get a nested bwrap tmpfs over the SAME path, so the path stays stable for demo.nix's relative sibling imports and the state is fresh by construction.
3. A lint check that greps the harnesses for delete-shaped commands, so criterion #1 stays true rather than being true once.
4. Host /proc/stat and nproc: record them outside the sandbox, pass them in, assert inside. A silently namespaced /proc would invalidate every linearity verdict, so this is an assertion and not a comment.
5. poc/05-loop/closed-loop.sh: bind only nix's 63-path runtime closure plus what the demo reads, and assert the cross toolchain is unreachable by ABSOLUTE path, not merely absent from PATH. Rewrite the comment that calls the current stage a demonstration.
6. Measure just e2e before and after. A tmpfs HOME disables nix's eval cache; if it costs anything, bind the cache read-only rather than let it slide.
7. Diagnose a machine without unprivileged user namespaces by name, and exercise that code path rather than asserting it.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
WHAT LANDED.

poc/lib/sandbox.sh is sourced as the first thing every run.sh does. It probes bubblewrap, then re-execs the caller inside a sandbox that binds the host through (--dev-bind / /) and puts a tmpfs over /tmp, with $work=/tmp/nixcc. The kernel reclaims it when the process exits, so there is no trap, no cleanup and nothing to delete. poc/05-loop/provenance.sh sources it too, since it is also runnable on its own and re-entering an existing sandbox is a no-op.

poc/lib/mutant.sh runs one mutation -- the copy, the sed and the mutated suite -- inside a nested bwrap whose tmpfs is mounted over $mut. Every mutation therefore gets a filesystem created empty, and the suite's own exit status still reaches mutate(). Three statuses no evaluator or python harness produces (120, 121, 122) let the caller name a failed copy, a mutation that would not apply, and a mutation that edited nothing, instead of reporting them as a detection. That last check is new to poc/02-lexer, which did not have it: its one mutation that deliberately changes the INVOCATION rather than the tree writes its apply step as the literal 'true', and mutant.sh recognises that rather than being given a flag.

poc/05-loop/closed-loop.sh now binds nix's RUNTIME CLOSURE and nothing else -- 63 store paths, of which the only three whose names mention a compiler are libgcc and libstdc++ -- plus the PoC tree and the emulator source it imports. It then asks nix itself, from inside, whether the absolute path of each of six host binaries exists there: riscv32-none-elf-as, -ld, -objcopy, gcc, as, ld. All six are absent. builtins.pathExists is the only probe available because the sandbox is minimal enough to have no /bin/sh in it.

WHAT IT COSTS. e2e wall clock, same machine, measured either side:

    before task-034 (commit 678d352)   7m22, 7m28, 6m15, 7m09
    after                              5m44, and see below

It got FASTER, not slower. The acceptance criterion worried about a tmpfs HOME disabling nix's eval cache; that does not arise, because the scratch sandbox leaves HOME exactly as it was and replaces only /tmp. The eval cache matters to 'nix build .#rcc' and 'nix flake check', which run outside any sandbox, and the ladders use 'nix eval --expr', which does not consult it at all. The closure-only sandbox inside closed-loop.sh does use a tmpfs HOME, and runs seven evals in it in about 0.6 s.

TWO THINGS THE SANDBOX BROKE, both caught by the gate rather than by reasoning, and both worth recording because they are the shape of thing this change could have hidden:
  * poc/04-assembler's differential mutation calls gnu_diff, a shell function defined in run.sh, which a child bash in a new namespace does not inherit. It is now exported, with $mut, and its scratch moved from $work into $mut so that it lands on the per-mutation tmpfs rather than needing a unique name.
  * poc/05-loop's mutated copy reaches its siblings through symlinks back into the real tree, and a sandbox that bound only the copy could not follow them -- 'path .../04-assembler/asm.nix does not exist', about a path that plainly does exist. closed-loop.sh now binds what those links point at. It does not weaken the claim: the absence check runs against the finished bind list, so anything that arrived that way and should not have is caught rather than assumed away.

AND ONE THE SANDBOX INTRODUCED, which is the one I would most want a reviewer to look at. The first version of the absence check read

    if [ "$(in_sandbox eval ... )" = yes ]; then ...still reachable...; fi

and a bwrap that could not start produced empty output, which is not 'yes', which read as ABSENT. The check passed most loudly exactly when it had stopped working -- and it did stop working, for one run, when a tmpfs on a top-level path failed under nesting. It now requires the probe to succeed and to answer exactly 'yes' or 'no', and anything else is exit 2 with the sandbox's own error quoted. A new mutation ('the absence check is given no binaries to look for') covers the other half, the loop that checks nothing.

SECOND ROUND, after qa-test-runner and mped-architect. Both found real things; the most serious was a fail-open I had already introduced once and had not finished removing.

FAIL-OPEN SHAPES, which is what both reviewers were asked to hunt and what they found most of:
  * The absence check in closed-loop.sh had a THIRD failure mode neither of its two mutations covered: a probe that has stopped asking. Change builtins.pathExists to something always false and six tools come back missing, the floor passes, and the stage prints the greenest line in the suite. It now runs a POSITIVE CONTROL first -- it asks whether nix's own binary is in the sandbox, from inside the sandbox, by that very binary -- and requires a yes before believing any no. A new mutation ('the reachability probe stops looking and always says absent') covers it.
  * just no-deletes was the weakest guard in the change while being the one asserting the whole thing's durability. Its pattern anchored on a character class with no TAB in it, so a tab-indented rm -rf was invisible; /bin/rm and "git -C dir clean" escaped it; and a glob that matched nothing would have printed the same clean line as a glob that matched everything. It now has a positive control of ten fixture lines the pattern MUST match -- including the tab case, which has to be written as an escape because a literal tab cannot appear in a just recipe, and that is part of why it was missed -- plus a floor on the number of files scanned and a wider pattern. Proved by hand that a tab-indented rm is now caught and that the fixtures fail the check when the pattern is wrong.
  * contention.step_ratio() faulted (exit 2) when a round left nothing to take a ratio of. It runs BEFORE require_quiet(), so a busy machine inflating one round's baseline would have been reported as a broken harness -- the exact miscategorisation task-035 exists for, reintroduced inside the fix for it. It now branches on quiet(ladder) the way the cliff does: HARNESS FAULT on a quiet machine, NO VERDICT on a busy one.

THE ESTIMATOR HAD NO TEST AT ALL, which mped-architect called the single most consequential unguarded line in the tree and was right: change the median to a minimum, a maximum or the old quotient-of-minima and every guard case still passes, because they move the contention threshold and the tolerances and cannot see the statistic. selftest.py check 0b now drives step_ratio() with synthetic Points whose per-round ratios are 1, 5 and 12 -- median 5, mean 6, minimum 1, maximum 12, quotient-of-minima 1, five different answers -- and poc/02-lexer/run.sh mutates the median to a minimum and requires the self-test to catch it. Verified by hand that it does.

HERMETICITY WAS NOT WHAT THE COMMENT SAID. mped-architect ran a store ping inside the sandbox and got "Store URL: daemon": binding /nix/var/nix left the nix daemon reachable, so an evaluation could have realised a derivation ON THE HOST with the real toolchain -- and the file's own comment named import-from-derivation as the one escape a pure eval has. The sandbox no longer binds /nix/var/nix and now passes --unshare-net. Measured after: nix falls back to a chroot store under the tmpfs, builtins.fetchurl fails, and the demo still prints 1..10 = 55 in 714 instructions. The header now also BOUNDS the claim -- six names probed is a sampled absence, not a proof of absence, and a chroot store is still a store.

OTHER THINGS ACTED ON:
  * selftest.py check -1 compared nproc (affinity-aware) with os.cpu_count() (not), so under taskset or a cgroup cpuset it would have fired with "the sandbox is virtualising the core count" when nothing was -- a false diagnostic pointing at bubblewrap, in a file whose own module docstring describes taskset experiments. sandbox.sh now reads both figures through contention.py itself, which also removes a second copy of the busy-counter formula.
  * NIXCC_SCRATCH was documented as "yours to keep" and was single-use: the second run died on the first plain mkdir with a message naming neither the cause nor the variable. Each run now gets its own subdirectory. And just poc prints the variable's name when a PoC fails, because a debugging aid nobody is told about on the day they need it is not one.
  * NIXCC_SANDBOX doubled as an undocumented opt-out: setting it by hand skipped the sandbox entirely and put scratch back on the real filesystem, reusable across runs. sandbox.sh now refuses when the sentinel is set without the host figures that only it supplies.
  * A checkout under /tmp could not work -- the tmpfs takes the harness with it and bwrap execs a vanished path -- and said only "No such file or directory". Named now. $BASH is checked for being an executable rather than assumed.
  * The closure floor read ">= 20" against an array with three elements per store path, so it was really a floor of seven. It counts paths now, and the prose no longer carries the count.
  * mutant.sh inspected the caller's snippet TEXT (is apply literally the word true) to decide whether to expect an edit. The caller declares it instead, and an unrecognised declaration is its own exit status. And eval of the apply snippet carried only the last clause's status, so a compound mutation whose first sed failed read as clean; it runs under a subshell with -e now.
  * export -f gnu_diff was worse than it looked: the child ran the PARENT's copy, so that function was the one part of the differential path a mutation could not reach, while the comment beside it claimed "breaking the comparison is itself testable". It is poc/04-assembler/gnu-diff.sh now, run from inside the mutated tree, which is what that comment always meant.
  * Comments corrected where the estimator change made them false: rounds() argued "minimum, not mean" forty lines above step_ratio() arguing that a minimum is biased, with neither referencing the other; the module docstring still said each point's cheapest run was what a verdict rests on. The README claimed the sandbox holds "nothing but nix's own runtime closure" and dropped the qualifier closed-loop.sh's own header keeps.

NOT ACTED ON, named rather than buried:
  * The 03-matcher semantic mutation ("the divide libcall divides x by itself") still gets a fresh DIRECTORY rather than a fresh tmpfs, and qa-test-runner is right that my stated reason was too strong: I wrote that it "cannot" be handed to mutant.sh because it interleaves with build_and_run, when the sibling harness solved the same problem for gnu_diff by moving the function into a script. It could be done the same way. It is used exactly once per run, so freshness holds either way; the impossibility claim did not, and the comment has been left for the orchestrator to judge rather than quietly softened.
  * poc/05-loop/provenance.sh puts its scratch under the OUTER tmpfs with a per-pid name rather than the per-mutation one. Same shape, same reasoning.
  * Only poc/05-loop/run.sh has a floor on its mutation COUNT; 02, 03 and 04 print the number without asserting it, so a silently dropped mutate call in those three would not be noticed. Pre-existing, not from this change, and worth a task of its own.

CRITERION STATUS, one of seven not met as written.

#1 no delete-shaped command remains, proved by grep -- MET. just no-deletes, run by just lint, and it is now proved to be able to fail: ten fixture lines it must match run before it is trusted, including the tab-indented case an earlier pattern was blind to, plus a floor on the number of files scanned. Verified by hand that a tab-indented rm -rf added to a harness is caught and that removing it makes the check clean again.

#2 scratch on a tmpfs, reclaimed on exit, no cleanup command and no EXIT trap -- MET. All five run.sh and poc/05-loop/provenance.sh source poc/lib/sandbox.sh as their first statement; grep for "trap " across poc/ returns only prose.

#3 a fresh tmpfs per mutation -- NOT MET AS WRITTEN, and I am leaving the criterion alone rather than rewording it. 106 of 107 mutations go through poc/lib/mutant.sh, which runs the copy, the sed and the mutated suite inside a nested bwrap whose tmpfs is mounted over $mut: those are fresh by construction. The one that is not is poc/03-matcher's "the divide libcall divides x by itself", which interleaves with build_and_run -- a function defined in run.sh -- and so gets a directory used exactly once instead. Freshness holds for it (there is no previous run of that directory to inherit from) but a directory is not a tmpfs, and qa-test-runner was right that my first comment overstated the case by calling it impossible: the sibling harness solved the identical problem for gnu_diff by moving the function into a script, and the same could be done here. It is a real remaining gap with a known fix, not an unavoidable one. poc/05-loop/provenance.sh is the same shape on a smaller scale. Whether that is close enough is the orchestrator's call, not mine.

#4 contention.py still reads the host's /proc/stat and nproc, with a test -- MET. poc/lib/selftest.py check -1: the sandbox records both figures on the way in and the check asserts they came back. Falsified by hand in all three directions -- a wrong core count, a wrong busy counter, and the variables absent -- and each fires. One caveat stated in the source rather than glossed: the upper bound on the busy-counter delta tolerates ten minutes of the whole machine, so it is monotonicity that does the work and the ceiling catches only a wildly different counter.

#5 closed-loop binds only nix's runtime closure, unreachable by absolute path, comment updated -- MET, and stronger than the criterion asked. Six host binaries are probed by absolute path from inside and none is present; a positive control asks about nix's own binary first so a probe that has stopped looking cannot report absence; and after review the sandbox also drops /nix/var/nix and unshares the network, which closes import-from-derivation and fetching -- the escape the file's own comment had named while leaving it open. The comment is rewritten from "demonstration" to what it now establishes AND what it still does not: six names is a sampled absence, and a chroot store is still a store.

#6 e2e wall clock measured before and after, eval cache not left to regress -- MET. 7m22, 7m28, 6m15 and 7m09 before; 5m44, 6m30 and 6m17 after, all on this machine. It got faster. The eval-cache worry does not arise: the scratch sandbox replaces /tmp and leaves HOME alone, so nix's cache is untouched, and the ladders use nix eval --expr which does not consult it. The closure-only sandbox inside closed-loop.sh does use a tmpfs HOME and runs seven evals in about 0.6 s.

#7 a machine without unprivileged user namespaces gets a clear diagnostic -- MET. just sandbox-refuses puts a bwrap that fails the way such a kernel does in front of the real one and requires exit 2 plus three fragments, one of which can only reach the output by being quoted through from the stub -- so the reader gets bubblewrap's own reason, not a guess. It cannot pass vacuously: if the stub were not installed the encoder PoC would really run and exit 0.

GATE, on 860a468: exit 0, 5 PoCs passed, lint clean, 6m17, with all 14 guard cases, both new cliff cases, the estimator mutation and 108 mutations across the five PoCs caught. Three attempts in the same window were lost first, all three to the contention self-test's own non-stationarity (task-039), which this batch neither introduced nor fixed. That is worth knowing before anyone reads a single green run as a stable gate: on this machine, right now, roughly one gate run in three is lost to that one check.

The remaining gap on criterion #3 is filed as task-041, with the fix spelled out: move build_and_run into its own script the way poc/04-assembler/gnu-diff.sh was moved in this batch, for exactly the same reason, and the semantic mutation becomes an ordinary mutate() call. Task left In Progress rather than Done, with #3 unchecked, for the orchestrator to judge.
<!-- SECTION:NOTES:END -->
