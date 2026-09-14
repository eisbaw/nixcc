---
id: TASK-016
title: Register allocation for the instruction selector
status: To Do
assignee: []
created_date: '2026-09-14 20:56'
updated_date: '2026-09-14 21:52'
labels:
  - backend
  - codegen
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher assigns registers by expression depth and never frees a common-subexpression register, which is enough to emit correct code for small functions and nothing more. Real code needs lcc's own second pass (gen.c's ralloc): live ranges, reuse, and a spill path when the register file runs out.

Today the PoC REFUSES rather than miscompiles -- 'expression nesting needs more than N evaluation registers' and 'needs more than N registers to hold common subexpressions' -- so this is a capability gap, not a correctness bug. The refusal sites are burg.nix's depthReg and the cseRegs bounds check; both name this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Registers are allocated from live ranges, not from evaluation depth
- [ ] #2 A common-subexpression register is released once its last use is reduced
- [ ] #3 Running out of registers spills to the frame rather than throwing
- [ ] #4 poc/03-matcher's must-fail cases for register exhaustion are replaced by cases that spill and still execute correctly
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-003: two refusals this task will remove are now precisely characterised, and both have a corpus case sitting next to them.

A value lcc pinned in the node list -- a call result -- cannot survive a label under the current emitter: the common-subexpression table is cleared at every branch target because there is no analysis saying the code that filled a register runs on every path to it. 'extern int g(void); int p(int a, int b) { return g() + (a ? b : a); }' is the smallest C that hits it, and the diagnostic names the label. Real register allocation with live ranges and dominance is what lifts it; until then, refusing is correct.

The saved-register set is derived from high-water marks (st.cseHigh, st.depthHigh), so it over-saves: every register up to the deepest one used, whether or not the ones below it were. Live ranges would fix that too.
<!-- SECTION:NOTES:END -->
