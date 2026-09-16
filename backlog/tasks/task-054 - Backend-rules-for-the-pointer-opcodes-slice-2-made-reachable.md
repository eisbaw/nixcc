---
id: TASK-054
title: Backend rules for the pointer opcodes slice 2 made reachable
status: To Do
assignee: []
created_date: '2026-09-16 01:02'
labels:
  - backend
  - rules
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/07-parser now emits CNSTP4, CVUP4, CVPU4, SUBP4 and RETP4 for ordinary C -- a null pointer constant, a cast between a pointer and an integer, a pointer difference, and a function returning a pointer. poc/03-matcher/rules.nix has a row for none of them, so such a program compiles to IR that diffs clean against lcc and is then refused at instruction selection, loudly and by name.

What makes this worth its own task rather than a footnote: 'p == 0' is not an exotic form. It is how every C program written before nullptr tests a pointer, and the frontend reaches it through int -> unsigned -> pointer with a fold at each step (see poc/07-parser/c/ptrs.c's 'nulls').

The rows are cheap -- a pointer is four bytes and so is an unsigned int on this target, so CVUP4 and CVPU4 are register moves at most and CNSTP4 is the CNSTU4 template. SUBP4 is 'sub'. What is NOT cheap is the lesson task-051 paid for: a rule the corpus never SELECTS is asserted by nothing. Each row needs a case in poc/03-matcher/ir/ that makes the matcher choose it, and an execution answer that moves if the wrong instruction is emitted.

poc/07-parser/cases.nix's opcode list names all five and says they are unreachable in the backend; that comment is where this task is referenced from.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every opcode poc/07-parser's corpus emits has a rule in poc/03-matcher/rules.nix, or a named reason why not
- [ ] #2 Each new row is SELECTED by a case in poc/03-matcher/ir/, not merely named in a table
- [ ] #3 A C program that compares a pointer against zero compiles from .c and runs
<!-- AC:END -->
