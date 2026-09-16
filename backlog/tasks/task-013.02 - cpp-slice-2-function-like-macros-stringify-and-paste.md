---
id: TASK-013.02
title: 'cpp slice 2: function-like macros, stringify and paste'
status: To Do
assignee: []
created_date: '2026-09-16 17:27'
labels:
  - frontend
  - preprocessor
  - slice
dependencies:
  - TASK-070
parent_task_id: TASK-013
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The hard part of macro expansion, split out deliberately. Across the entire backlog before this, `#` stringify and `##` paste had two passing mentions and appeared in no acceptance criterion -- while task-013 named only "nested and recursive invocations".

Scope: parameters, argument substitution, the # stringify operator, the ## paste operator, and the blue-paint rule (a macro must not re-expand inside its own expansion).

The corner cases are where the defects live: paste producing a token that is then NOT re-examined for further macro names, stringify preserving internal whitespace as a single space, an empty argument, an argument containing a comma inside parentheses, and paste at the edges of a replacement list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Function-like macros expand with correct argument substitution, including empty arguments and commas inside parentheses
- [ ] #2 The # operator stringifies, collapsing internal whitespace to one space and escaping quotes and backslashes
- [ ] #3 The ## operator pastes, and the result is NOT re-examined for further macro names
- [ ] #4 A macro does not re-expand inside its own expansion, direct or indirect
- [ ] #5 Differential against gcc -E on a corpus built to hit the corner cases above, comparing token streams
- [ ] #6 Harness mutation-tested
<!-- AC:END -->
