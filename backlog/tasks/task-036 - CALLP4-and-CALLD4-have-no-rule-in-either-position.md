---
id: TASK-036
title: CALLP4 and CALLD4 have no rule in either position
status: To Do
assignee: []
created_date: '2026-09-15 07:57'
updated_date: '2026-09-15 08:39'
labels:
  - poc
  - matcher
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/rules.nix has CALLI4 in both a value position and a statement position (task-025) and CALLV as a statement. It has no row at all for CALLP4 -- a function returning a pointer -- or CALLD4, and neither has a `reg' rule to pair with, so both refuse loudly wherever they appear.

CALLP4 is ordinary C and is reachable the moment a frontend slice declares anything returning a pointer:

    char *p = strchr(s, 'x');      /* CALLP4 as a value     */
    strcpy(dst, src);              /* CALLP4 as a statement */

It is two rows in each position, identical to the CALLI4 rows with the opcode changed, and they should be added with a corpus case that produces them rather than guessed at from the pattern -- the same discipline task-025 followed. CALLD4 is out of scope until floats are (decision-005 territory), and should be left refusing.

Also worth doing at the same time: poc/03-matcher/cases.nix's `callRules' table would gain the new rows, and the floor in check.nix moves with it.

Found while implementing task-025.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A C function that calls a pointer-returning function, once for its value and once for its effect, compiles and runs with the right answer
- [ ] #2 The corpus case comes from real lcc output, not hand-written IR
- [ ] #3 poc/03-matcher/check.nix's derived call-rule guard covers the new rows automatically; nothing has to be added to a second list
<!-- AC:END -->
