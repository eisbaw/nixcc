---
id: TASK-047
title: Joining adjacent string literals of different width has no rule
status: To Do
assignee: []
created_date: '2026-09-15 18:55'
labels:
  - frontend
  - parser
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/06-constants/const.nix evaluates ONE literal and returns { units; width; warnings; } with no terminator; the parser joins adjacent literals and appends a single 0 (task-027, task-028). C89 leaves `"ab" L"cd"' undefined, and lcc's scon() has its own answer: the wide path calls getchr() looking for a following L and swallows it, so lcc will happily concatenate a narrow literal onto a wide one and vice versa.

Nothing in poc/06-constants covers it, because the evaluator never sees two literals at once -- it is a JOIN rule, and the join is the parser's. So whoever writes the join has to decide, and the decision has nowhere to live yet.

Three options, in order of what this project usually picks: refuse a mixed-width join with a diagnostic naming this task; match whatever lcc does, with an oracle form proving it; or widen the narrow literal, which is what C99 says and lcc does not.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The join rule for adjacent literals of different width is decided and written down where the parser can find it
- [ ] #2 Whichever is chosen, a case covers it -- an oracle form if the behaviour matches lcc, a must-fail case with its diagnostic text if it refuses
<!-- AC:END -->
