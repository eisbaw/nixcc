---
id: TASK-016
title: Register allocation for the instruction selector
status: To Do
assignee: []
created_date: '2026-09-14 20:56'
updated_date: '2026-09-15 01:41'
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

forward-carried from task-006: poc/04-assembler now stands between the selector
and the bytes, and two things in it bear on register allocation.

  * The assembler does NOT know about registers beyond validating their names
    (poc/01-encoder's `reg'). Allocation stays entirely above it, which is the
    right seam: an allocator rewrites the operands of insn ITEMS, and nothing
    about layout, labels or encoding has to change.
  * Items are the better target for an allocator than assembly text. An insn
    item is { kind = "insn"; mnemonic; args = [ ... ]; } where args are
    register-name strings, ints, { base; disp; } memory operands or symbol
    strings, and WHICH is which comes from asm.nix's operand-shape table rather
    than from how the token looks. So rewriting "s2" to "a3" at arg position
    k is a total function of the mnemonic, with no parsing and no chance of
    renaming a label that happens to be spelled like a register.

Also carried, because it is the same trap in a new place: task-003's cseHigh /
nextCse distinction. Any state threaded through a walk that RESETS at a
control-flow boundary cannot also serve as a whole-function total. An allocator
has at least two such quantities -- live ranges reset at a label, pressure
maxima do not -- so name them so they cannot be confused, as emit.nix now does.
<!-- SECTION:NOTES:END -->
