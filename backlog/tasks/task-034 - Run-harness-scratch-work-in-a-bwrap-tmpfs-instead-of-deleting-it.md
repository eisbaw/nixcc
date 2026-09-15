---
id: TASK-034
title: Run harness scratch work in a bwrap tmpfs instead of deleting it
status: In Progress
assignee: []
created_date: '2026-09-15 07:28'
updated_date: '2026-09-15 12:22'
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
- [ ] #1 No delete-shaped command remains in any harness: no rm, rmdir, truncate, git clean, git reset --hard. Grep proves it
- [ ] #2 Scratch state lives on a tmpfs inside bwrap and is reclaimed on exit with no cleanup command and no EXIT trap
- [ ] #3 Mutation testing gets a fresh tmpfs per mutation, so stale state between runs is impossible by construction rather than by remembering to clear it
- [ ] #4 poc/lib/contention.py still reads the host's /proc/stat and nproc from inside the sandbox; a test asserts the values match the host, since a silently namespaced /proc would invalidate every linearity verdict
- [ ] #5 poc/05-loop's no-toolchain stage binds only nix's runtime closure, so riscv32-none-elf-as and gcc are unreachable by absolute path and not merely absent from PATH. Its comment is updated from 'demonstration' to what it now actually proves
- [ ] #6 Wall-clock cost of just e2e measured before and after and recorded; a tmpfs HOME disables nix's eval cache, so if that slows things the cache is bound read-only instead of being left to regress silently
- [ ] #7 A machine without unprivileged user namespaces gets a clear diagnostic naming the requirement, not a confusing failure
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
<!-- SECTION:NOTES:END -->
