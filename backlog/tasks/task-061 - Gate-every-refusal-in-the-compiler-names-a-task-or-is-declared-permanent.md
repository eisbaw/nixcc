---
id: TASK-061
title: 'Gate: every refusal in the compiler names a task or is declared permanent'
status: To Do
assignee: []
created_date: '2026-09-16 08:22'
labels:
  - harness
  - verification
  - structural
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The highest-leverage structural change available, per the COMPASS consult, and it is the backlog analogue of a check this project already trusts.

THE PROBLEM. Four whole C features were refused BY NAME IN THE CODE with no task anywhere: struct/union/enum, switch, goto/labels, varargs. A grep for "varargs" across backlog/tasks returned nothing at all. switch and goto appeared only inside a narrative paragraph in another task's implementation notes -- prose, not a trackable item.

The mechanism, and the implementers are not at fault: THE BACKLOG GROWS BY REACTION, NOT BY PROJECTION. Every task filed since task-027 was discovered by someone who touched the code. That practice is excellent and captured 33 real gaps. It structurally cannot capture what nobody reached. decision-007 projected slices 1-3 and stopped; task-005, the re-plan, is Done and nothing replaced it.

THE FIX, and the project already uses it elsewhere. poc/03-matcher/check.nix refuses a rule row the corpus never reduces unless it is declared in unexercisedRules with a written reason, and asserts the arithmetic adds up. Apply the same derived-population idiom to refusals: every refuse string in poc/07-parser must either name an open task id or be declared a permanent refusal with a reason.

The convention half-exists already, which is why the gap hid so well: parse.nix says "belong to slice 3 (task-029)" for globals but only "outside slice 1" for struct. A gate over that difference would have surfaced all four gaps the day slice 1 closed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every refusal site in poc/07-parser names an open task id, or is declared permanent with a written reason in one place
- [ ] #2 The gate derives the refusal population from the source rather than from a hand-maintained list, as check.nix does for rules
- [ ] #3 The declared set and the derived set must reconcile exactly, and the arithmetic is asserted
- [ ] #4 Mutation-tested both ways: adding an undeclared refusal fails, and declaring a refusal that does not exist fails
- [ ] #5 Extended to poc/03-matcher and poc/04-assembler refusals, or a written reason why only the frontend is covered
<!-- AC:END -->
