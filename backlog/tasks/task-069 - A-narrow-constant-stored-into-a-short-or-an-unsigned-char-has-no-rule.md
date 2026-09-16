---
id: TASK-069
title: A narrow constant stored into a short or an unsigned char has no rule
status: To Do
assignee: []
created_date: '2026-09-16 13:20'
labels:
  - backend
  - rules
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/rules.nix has a row for CNSTI1 -- task-024 added it, because lcc pushes a constant's type down to the DESTINATION and `buf[0] = '\\n'' therefore arrives as CNSTI1 rather than CNSTI4 -- and no row for CNSTI2, CNSTU1 or CNSTU2. The same lowering applies to all four.

So `short h; h = 9;' emits CNSTI2 and is refused at instruction selection. That is ordinary slice-1 C and has been reachable since task-027; nothing in c/ happened to write it until task-058's c/unions.c did, which is the usual shape of this gap -- task-051 and task-054 both found rules missing this way, by writing the C rather than by reading the table.

cases.nix's opcode list now carries CNSTI2 and says what it is: a claim about the FRONTEND, not a claim that the backend can lower it. ASGNB and INDIRB are in the same position and belong to task-060.

The rule itself should be reg_cnst_small's, with the same range() guard task-024 argued for: a CNSTI2 outside the range has to be REFUSED rather than truncated, because a truncated constant is a wrong program that runs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CNSTI2, CNSTU1 and CNSTU2 each have a row, each reached by a C program under poc/07-parser/run/ rather than only by the rule census
- [ ] #2 A constant outside the destination's range is refused by name, not truncated, and a must-fail case says so
- [ ] #3 The rule census in task-053's sense still passes: every row added here is SELECTED and REDUCED by some corpus node, and corrupting it changes an executed answer
<!-- AC:END -->
