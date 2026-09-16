---
id: TASK-060
title: 'Slice 4c: block copy, as a libcall'
status: To Do
assignee: []
created_date: '2026-09-16 08:21'
labels:
  - backend
  - slice
  - compound-types
dependencies:
  - TASK-058
  - TASK-007
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The ONLY genuinely new backend rule class compound types need. Covers struct assignment (a = b), struct return, and by-value arguments under decision-009.

Measured: `struct P mk(int,int)` emits INDIRB #5 and ASGNB #2 #4 8 4, with size and alignment in syms[0]/syms[1] -- and poc/07-parser/dag.nix's ASGN and ARG arms ALREADY attach size and align in exactly that convention.

MODEL IT AS A LIBCALL, NOT A TEMPLATE. rules.nix already has the proven shape in reg_muli_libcall and reg_divi_libcall, and runtime.s is already assembled by poc/04-assembler unchanged. A libcall reuses a rule shape the census understands, avoids inventing a loop-emitting template the tmpl string format may not express, and sidesteps task-016 entirely -- an unrolled copy would consume depth registers proportional to struct size, a libcall consumes none.

Stated trade: the size is a compile-time constant in syms[0], so a libcall throws away an obvious specialisation. That is the right trade at this rung -- correctness first, and the rule census will happily hold an unrolled row later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ASGNB and INDIRB select, via a runtime block-copy routine in runtime.s rather than a multi-instruction template
- [ ] #2 Struct assignment, struct return and a by-value struct argument each compile from .c and run
- [ ] #3 The copy is tested at a size that is not a multiple of the word size, and at a size of zero
- [ ] #4 The new rule rows are reduced by the corpus, per task-053's census, and corrupting each changes an executed answer -- SELECTED is not TESTED (see task-053's notes)
<!-- AC:END -->
