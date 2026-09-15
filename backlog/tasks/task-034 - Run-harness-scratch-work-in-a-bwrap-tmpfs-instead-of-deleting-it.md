---
id: TASK-034
title: Run harness scratch work in a bwrap tmpfs instead of deleting it
status: To Do
assignee: []
created_date: '2026-09-15 07:28'
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
