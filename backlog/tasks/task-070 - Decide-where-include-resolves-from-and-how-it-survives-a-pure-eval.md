---
id: TASK-070
title: 'Decide where #include resolves from, and how it survives a pure eval'
status: To Do
assignee: []
created_date: '2026-09-16 17:27'
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
- [ ] #1 The three options for header provenance are costed: write our own freestanding set, vendor one, or declare hosted headers out of scope
- [ ] #2 The purity question is settled explicitly: how #include works inside nix flake check, where --impure is not available
- [ ] #3 A decision record is written with the reasoning, as decision-005 was
- [ ] #4 If the answer restricts what C can be compiled, the README's limits section says so in the same change
<!-- AC:END -->
