---
id: TASK-062
title: switch statements are refused with no task behind the refusal
status: To Do
assignee: []
created_date: '2026-09-16 08:22'
labels:
  - frontend
  - language-gap
dependencies:
  - TASK-058
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SWITCH is refused by name in parse.nix with no task. lcc lowers switch to a jump table or a comparison chain in stmt.c; which one it picks is size-dependent, so the IR shape varies with the case count and a corpus needs both.

Filed as part of closing the projection gap the COMPASS consult identified: four C features were refused by name in the code with nothing tracking them. See task-061 for the gate that stops this recurring.
<!-- SECTION:DESCRIPTION:END -->
