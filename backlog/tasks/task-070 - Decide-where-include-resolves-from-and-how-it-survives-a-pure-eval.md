---
id: TASK-070
title: 'Decide where #include resolves from, and how it survives a pure eval'
status: Done
assignee: []
created_date: '2026-09-16 17:27'
updated_date: '2026-09-17 07:01'
labels:
  - frontend
  - preprocessor
  - decision
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Blocks the #include slice, and nothing has looked at it. Two problems, and the second is the one that bites.

WHERE DO HEADERS COME FROM. lcc ships exactly five: assert.h, float.h, limits.h, math.h, stdarg.h. There is no stdio.h, no string.h, no stdlib.h. So `#include <stdio.h>` has nowhere to resolve to unless we write the headers, vendor a set, or declare the hosted library out of scope and support freestanding only.

PURITY. Measured: builtins.readFile CAN read an arbitrary path at eval time, but only under --impure. The flake's checks output does not set it. So a preprocessor that reads headers off the filesystem CANNOT run inside `nix flake check`, which is where the differential tests live. Headers would have to be brought into the store, carried as a flake input, or passed as an attrset of name -> contents.

That last option is worth weighing seriously: an attrset of headers is pure, testable, trivially mockable in a harness, and sidesteps search-path semantics entirely. The cost is that `just run foo.c` can no longer pick up a header sitting next to foo.c without an impure escape hatch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The three options for header provenance are costed: write our own freestanding set, vendor one, or declare hosted headers out of scope
- [x] #2 The purity question is settled explicitly: how #include works inside nix flake check, where --impure is not available
- [x] #3 A decision record is written with the reasoning, as decision-005 was
- [ ] #4 If the answer restricts what C can be compiled, the README's limits section says so in the same change
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FORWARD-CARRIED from task-013.01, commits a063490 and 81ec8bb.

SLICE 1 LANDED AND DID NOT NEED YOU, which was the point of decomposing it. What it leaves you is one fact that narrows your third option considerably.

poc/08-cpp's entry point is `preprocess { src, file }' and `src' is a STRING. Nothing in the module reads the filesystem, calls readFile or touches a path; the corpus files are read by the HARNESS and handed in. So the attrset-of-headers answer you costed -- name -> contents, pure, mockable -- is not a design this stage would have to be rebuilt for. It is an extra argument threaded to one directive handler. Whatever you decide, that is the cheapest of the three to reach from here, and it is worth weighing that against the search-path semantics it gives up.

THE OTHER THING THAT IS NOW MEASURED rather than guessed: what a header COSTS once it is in. The macro table is one attrset updated with `//', which copies every binding it holds -- 3 MB of peak RSS above lexing at 500 macros, 37 MB at 2000 and 138 MB at 4000 (task-072). `#include <stdio.h>' on any real system is a four-figure macro count before the program has declared anything. If option one is chosen -- write our own freestanding set -- the size of that set is a memory decision as well as a scope one, and this is the number to decide it against.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Decided: freestanding headers only (float, limits, stdarg, stddef), carried in the repo. Recorded as decision-010.

The purity question turned out not to be a blocker. A bare nix eval --expr refuses absolute paths, but the flake's checks already read source purely via flake-relative paths, and nix eval .#checks...drvPath evaluates with no --impure. Headers in the repository are readable inside nix flake check.

The content question was settled by there being no libc: stdio.h would be a header with nothing behind it, which is the silent-failure shape this project refuses everywhere else. AC#4 (README limits) falls to task-013.03, which is where the limit becomes user-visible.
<!-- SECTION:FINAL_SUMMARY:END -->
