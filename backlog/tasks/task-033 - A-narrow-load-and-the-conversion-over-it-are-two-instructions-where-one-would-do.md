---
id: TASK-033
title: >-
  A narrow load and the conversion over it are two instructions where one would
  do
status: To Do
assignee: []
created_date: '2026-09-15 05:52'
updated_date: '2026-09-15 09:43'
labels:
  - poc
  - matcher
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/rules.nix lowers a char access as lcc hands it over: `lb' to load the byte, then `slli'/`srai' to sign-extend what `lb' already sign-extended. Three instructions where mips.md emits one, because lcc's own machine descriptions carry a TWO-LEVEL pattern:

    reg:  CVII4(INDIRI1(addr))   "lb $%c,%0\n"  1
    reg:  CVUU4(INDIRU1(addr))   "lbu $%c,%0\n" 1

poc/03-matcher/burg.nix matches ONE level: a rule is an opcode plus a list of nonterminals for its kids, so there is no way to say "a CVII4 whose kid is an INDIRI1". Two ways out, and they are not equivalent:

  * Nested tree patterns in the rule table, which is what lburg really has and what makes the table a grammar rather than a list of rows. The bigger change, and the one that also buys ADDI4(reg,MULI4(...)) style folds later.
  * A nonterminal per extension state -- `sext1', `zext1', `sext2', `zext2' -- so that INDIRI1 produces `sext1', a chain rule takes `sext1' to `reg', and `reg: CVII4(sext1)' is a zero-cost fragment. No matcher change at all, four more nonterminals and about ten more rows. Careful: a zero-cost fragment producing `reg' hands its users the register its KID was reduced into, and the depth registers are reused between statements, so the chain has to be costed or the fragment has to emit a move.

Measured cost of not doing it: ir/chars.c compiles to 81 body instructions, of which 14 are extension shifts and masks that a fused rule would delete. poc/05-loop/hello.c pays two per byte stored.

Not urgent. The unfused form is CORRECT, which is why task-024 shipped it.

Found while implementing task-024.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A char read through a pointer compiles to one load instruction, not a load and a shift pair
- [ ] #2 The corpus's instruction counts fall and the executed answers do not change
- [ ] #3 The choice between nested patterns and extension nonterminals is written down with the reason, in the file that carries it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MEASUREMENT CORRECTED after review, and the thing this task is really blocking recorded.

The numbers in the description were taken before ir/chars.c grew its CVII1 case and counted only part of the waste. Measured on the committed ir/chars.sym: 91 body instructions for scan(), of which 23 are extension shifts and masks (slli/srai/srli/andi) and 4 are `mv sN,sN' self-moves -- 27 of 91, just under 30%.

THE SELF-MOVES ARE A SECOND, SEPARATE PIECE OF WASTE, not part of the fusion. rules.nix's width-4 conversions (reg_cvui4_4, reg_cviu4_4) emit `mv %c,%0' for a conversion that changes no bits. The move exists because a zero-cost FRAGMENT producing the register nonterminal would hand its users whatever register its KID was reduced into, and the evaluation registers are reused between statements. burg.nix now REFUSES such a rule outright, so the hazard is a throw rather than a comment. Making these free needs the register allocator (task-016), not this task: once a node's value has a home of its own, the conversion can be a fragment safely.

All four of those moves are currently self-moves, because a one-kid node's kid is reduced at the same depth into the same depth register. So the register the comment worries about is never actually different today -- which means the justification is correct and unexercised at the same time. burg.nix's new table check is what keeps it honest.

WHAT THIS TASK BLOCKS, which was not written down: until the load and the conversion are fused, the SIGN a load carries is unobservable in any executed answer. lcc promotes every narrow load, so an INDIRI1 always arrives under a CVII4 whose slli/srai pair re-normalises the register -- `lb' and `lbu' leave the same 32 bits. Measured: the whole rule table with lb and lbu exchanged still returns 1649 from ir/chars.c. poc/03-matcher/cases.nix's `narrowLoads' table is the ONLY thing checking lb against lbu, and it checks the rule table rather than a result. When this lands, the load becomes the extension and the execution stage starts to see it -- at which point narrowLoads stops being the only witness, and should not be deleted before then.

forward-carried from task-024 via the orchestrator: when you fuse the narrow load with its conversion, the lb/lbu and lh/lhu distinction becomes OBSERVABLE for the first time. Today it is not -- lcc emits CVII4 above INDIRI1 and CVUI4 above INDIRU1, so the conversion re-normalises the register whatever the load did, and swapping the two in the rule table changes no answer anywhere (measured three times: twice by task-024's implementer, once by the orchestrator against the IR itself). Task-024's acceptance criterion originally demanded a case where the answer differs and had to be withdrawn for this reason. Once fused, write that case here -- a signed char holding 0xFF must read as -1 and an unsigned char holding 0xFF must read as 255, and the fused load is the only thing making it so.
<!-- SECTION:NOTES:END -->
