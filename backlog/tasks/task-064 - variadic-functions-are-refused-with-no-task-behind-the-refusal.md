---
id: TASK-064
title: variadic functions are refused with no task behind the refusal
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
Variadic functions are refused by name in parse.nix with no task, and a grep for 'varargs' across the whole backlog returned nothing before this. Needs the stack-argument work (task-018) and interacts with the RV32 ABI's variadic rules.

Filed as part of closing the projection gap the COMPASS consult identified: four C features were refused by name in the code with nothing tracking them. See task-061 for the gate that stops this recurring.
<!-- SECTION:DESCRIPTION:END -->
