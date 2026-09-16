---
id: TASK-060
title: 'Slice 4c: block copy, as a libcall'
status: To Do
assignee: []
created_date: '2026-09-16 08:21'
updated_date: '2026-09-16 13:58'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ASGNB AND INDIRB ARE ALREADY EMITTED AND ALREADY DIFFED, byte for byte,
against rcc-rv32. task-058 put four of them in poc/07-parser/c/structs.c --
`nest' (a nested struct member assigned), `arrays' (two struct copies through
an array), `pass' (a by-value argument, which is decision-009's temporary plus
ASGNB plus ARGP4) and `volat'. So the frontend half of this task is done and
tested; what is missing is only the rule.

THE MEASUREMENT IN THIS TASK STILL HOLDS and is now visible in the corpus:
`1' ASGNB #2 #3 8 4' -- the size and alignment are syms[0] and syms[1], printed
after the kids, and dag.nix attaches them in that convention.

TWO THINGS TO KNOW BEFORE WRITING THE RULE.

A B-KIND OPCODE CARRIES NO WIDTH. dag.nix has one line for this now, with the
reason: lcc writes `tp->op == INDIR+B ? tp->op : op' at the two sites where a B
can arrive, and the rule behind both is that INDIRB and ASGNB are spelled
without a size -- the size is the separate operand. A rule table keyed on
`ASGNB8' would match nothing. There is a mutation that makes the frontend print
the width, so the spelling is held.

A STRUCT WITH A VOLATILE MEMBER IS NOT CSE'd. dag.c builds its INDIRB with
newnode, so two copies of the same struct are two nodes with count=1 rather
than one with count=2. c/structs.c's `volat' is the case, and a block-copy rule
must not assume the load is shared.

WHAT TO ADD TO run/. run/records.c deliberately touches NO struct-to-struct
copy, and says so in its header, because this rule does not exist yet. Once it
does, the honest move is a program that copies a struct whose size is not a
multiple of the word (criterion #3 here) and reads BOTH halves back -- a copy
that stops one word early leaves the tail holding whatever was there, and only
reading the tail catches it.

AND THE THING THAT WILL BE TEMPTING: the size is a compile-time constant in
syms[0], so an unrolled copy looks free. This task already argues for the
libcall and why; task-053's census will hold an unrolled row later, and
task-016 is the reason not to spend depth registers on one now.
<!-- SECTION:NOTES:END -->
