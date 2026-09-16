---
id: TASK-071
title: Object-like macro expansion is capped at 200 nested macros
status: To Do
assignee: []
created_date: '2026-09-16 18:11'
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
