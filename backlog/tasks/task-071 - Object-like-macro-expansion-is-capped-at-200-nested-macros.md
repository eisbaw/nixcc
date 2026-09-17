---
id: TASK-071
title: Object-like macro expansion is capped at 200 nested macros
status: To Do
assignee: []
created_date: '2026-09-16 18:11'
updated_date: '2026-09-17 09:15'
labels:
  - frontend
  - preprocessor
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while implementing task-013.01. poc/08-cpp expands object-like macros recursively, carrying a hide set that grows by one name per level, so the recursion DEPTH is bounded by the number of distinct macros in a chain rather than by the size of the file -- which is what decision-001 requires. It is not bounded by anything else, so a chain of a few thousand macros would reach Nix's max-call-depth and die with 'stack overflow (possible infinite recursion)' rather than with a diagnostic.

cpp.nix therefore caps it at MAX_NEST = 200 and throws naming this task. Nothing real comes near it: the deepest chain in the corpus is three. The cap exists so the failure has a message, not because 200 is a considered number.

What would remove it: an expansion loop driven by genericClosure over a worklist rather than by recursion, which is how the standard's rescanning is usually written anyway (push the replacement list back onto the front of the input and carry the hide set on each token). That is a bigger change than slice 1 needed, and task-013.02 has to touch the same code for function-like macros, so it is the natural place to do it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A macro chain deeper than the current cap either expands correctly or is refused with a diagnostic -- never a Nix stack overflow
- [ ] #2 If the cap is removed, a chain of 5000 macros is shown to expand at constant stack depth
- [ ] #3 The must-fail case in poc/08-cpp that pins the cap is updated or removed with it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MEASURED AGAIN IN task-013.02, after the expander became a genericClosure worklist.

WHAT CHANGED: the failure mode. With MAX_NEST lifted, a chain of 6000 object-like macros now EXPANDS in 0.89 s. Slice 1's recursion died on the same input with "stack overflow; max-call-depth exceeded", which is what this task was opened about. Criterion #2 is therefore demonstrated -- a chain well past 5000 expands, at frame depth one, because the cursor pops a frame before it pushes the next.

WHAT DID NOT CHANGE: the cap. `nest' counts how many macros a token has been expanded THROUGH, not how deep the frame stack is, so a chain still trips MAX_NEST at 200 exactly as before. The reason to keep a cap is now MEMORY rather than stack: each level's hide set is the level before it plus one name and is copied per level, so a chain of n costs O(n^2) bindings. Measured with the cap lifted, on the same machine as the rest of poc/08-cpp/memory.py:

    chain of 1000   0.12 s    88 MB peak RSS
    chain of 3000   0.35 s   286 MB
    chain of 6000   0.89 s   782 MB

The diagnostic in cpp.nix now says that rather than blaming max-call-depth, and the header paragraph says plainly that a linear chain runs at frame depth one AND is still capped at 200.

SO WHAT IS LEFT HERE is a real choice rather than a rewrite: raise the cap to whatever peak RSS the project will spend, remove it and let memory decide, or make the hide set something that is not copied per level. The last is the only one that changes the curve.
<!-- SECTION:NOTES:END -->
