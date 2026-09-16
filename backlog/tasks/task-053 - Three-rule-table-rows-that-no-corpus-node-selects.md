---
id: TASK-053
title: Three rule-table rows that no corpus node selects
status: To Do
assignee: []
created_date: '2026-09-15 23:52'
updated_date: '2026-09-16 00:33'
labels:
  - backend
  - rules
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/rules.nix has three rules that label nothing in any ir/*.sym, so nothing but their own row asserts what they emit:

  reg_cnst_wide        a signed constant too wide for the 12-bit immediate field
  stmt_callv_indirect  a void call through a function pointer
  stmt_argp            a pointer argument

All three predate task-051 and all three are reachable C. Found while closing task-051, by walking every label table in the corpus and subtracting the rules that fired from the rules that exist -- which is a check the suite does not make and probably should:

  rules that label nothing in the corpus:
    reg_cnst_wide
    stmt_callv_indirect
    stmt_argp

What makes this worth a task rather than a note is what it costs to be wrong. cases.nix's 'lowerings' and 'libcalls' tables assert the TEMPLATE of a named rule and never that the matcher selects it, so a row nothing selects is pinned by a table describing itself. task-051 found five U-typed rows in exactly that state -- reg_rshu_reg among them, where 'srl' for 'sra' is the defect the whole slice was written to prevent -- and closed them by extending ir/unsig.c. These three are the remainder.

stmt_callv_indirect is the interesting one: poc/03-matcher/run.sh aims a mutation at it PRECISELY BECAUSE nothing else covers it ("a call rule's emitted text stops looking like a call"), and that mutation would stop proving what it proves if the rule were also selected somewhere. Read that one before changing it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every rule in poc/03-matcher/rules.nix is either selected by some node in the ir/ corpus, or named in a list of rows deliberately left unexercised with the reason written down
- [ ] #2 The suite computes that set rather than a reader computing it: a rule added to the table and selected by nothing is a named failure, not a silence
- [ ] #3 The mutation aimed at stmt_callv_indirect still demonstrates what it says it demonstrates, or is re-aimed and says why
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ORCHESTRATOR: raised to high. Task-051's implementer is right that this is not a tidy-up -- it is the check that would have caught its own five unselected U-typed rows, including reg_rshu_reg where sra-for-srl is the exact defect that task existed to prevent. Two reviewers found it; the implementer had not.

The window matters: slice 2 (task-028) is adding rules as I write this, and it has been briefed on the lesson but cannot lean on a check that does not exist. Every rule added before this lands is a rule asserted only by a table that names it rather than by a corpus that selects it.

Schedule it immediately after slice 2, before slice 3 adds more.
<!-- SECTION:NOTES:END -->
