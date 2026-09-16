---
id: TASK-063
title: goto and labels are refused with no task behind the refusal
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
GOTO is refused by name in parse.nix with no task. lcc's stmt.c resolves forward gotos with a patch list, which is mutation in the shape Nix handles worst -- expect a rewrite rather than a port, as with dag.c and gen.c (decision-002).

Filed as part of closing the projection gap the COMPASS consult identified: four C features were refused by name in the code with nothing tracking them. See task-061 for the gate that stops this recurring.
<!-- SECTION:DESCRIPTION:END -->
