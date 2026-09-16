---
id: TASK-057
title: 'CALLP4: calling a function that returns a pointer'
status: To Do
assignee: []
created_date: '2026-09-16 03:02'
updated_date: '2026-09-16 03:02'
labels:
  - backend
  - rules
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-054 gave poc/03-matcher/rules.nix rows for CNSTP4, CVUP4, CVPU4, SUBP4 and RETP4, and deliberately not for CALLP4. This is the row it left.

WHY IT WAS LEFT. Two reasons, and the second is the one that makes this a task rather than a footnote:

  * poc/07-parser's corpus does not emit CALLP4, so task-054's criterion #1 -- every opcode the frontend's corpus emits has a rule -- did not reach it.
  * poc/03-matcher/run.sh's mutation "a call rule is added to the table and forgotten everywhere else" ADDS a CALLP4 row with a template the table's callMarkers do not recognise, precisely because there is none. It is the one thing proving that the call-rule population is DERIVED from the opcode rather than hand-listed. A real CALLP4 row must not be named stmt_callp_direct, which is the id that mutation uses, and adding one has to leave that mutation proving what it says.

WHAT IT COSTS TODAY. run/pointers.c cannot call a function that returns a pointer, so the only executed witness for RETP4 is poc/03-matcher/ir/ptr.c, whose caller is hand-written assembly in drivers/ptr.s. A C program compiled from .c cannot yet write

    char *find(char *s, int c) { ... }
    p = find(buf, 'c');

which is an ordinary shape, and the refusal it gets is loud and by name -- the right failure, still a failure.

THE ROW OR ROWS. reg_callp_direct is "call %0" followed by "mv %c,a0", the CALLI4 row with the letter changed. Whether stmt_callp_direct is needed as well depends on whether any corpus C discards a pointer result; task-025's history is the guide there -- without the stmt rows for CALLI4, the "stmt: reg" chain took the node and handed a null destination to a template saying "mv %c,a0".

task-053's census refuses a row the corpus does not REDUCE, so each row added here needs a case in poc/03-matcher/ir/ that selects it and an executed answer that moves.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A C program under poc/07-parser/run/ calls a function that returns a pointer, compiles from .c and runs
- [ ] #2 Every CALLP4 row added is reduced by a case in poc/03-matcher/ir/, so task-053's census accounts for it without a declaration
- [ ] #3 run.sh's mutation 'a call rule is added to the table and forgotten everywhere else' still demonstrates that the call-rule population is derived, or is re-aimed and says why
<!-- AC:END -->
