---
id: TASK-008
title: Decide the C preprocessor strategy
status: To Do
assignee: []
created_date: '2026-09-14 18:47'
labels:
  - planning
  - frontend
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lcc/cpp/ is a SEPARATE ~2800-line program. The frontend in src/ consumes preprocessed input only -- input.c's resynch() parses `# n "file"` linemarkers, and there is no #include, #if or macro expansion anywhere in src/.

So the headline claim "Nix alone compiles C with no external toolchain" is false unless cpp is ported too. That is ~2800 lines nobody has counted into the plan. This task is to decide, not to implement: port it, write a smaller one, or narrow the claim to preprocessed C and say so in the README.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The three options are costed: port lcc/cpp, write a minimal cpp, or accept preprocessed-C-only input
- [ ] #2 A decision is recorded in backlog/decisions with its reasoning
- [ ] #3 If preprocessed-only is chosen, the README claim is corrected in the same change -- no claim outlives the decision that invalidated it
<!-- AC:END -->
