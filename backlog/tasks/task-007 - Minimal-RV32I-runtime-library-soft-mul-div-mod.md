---
id: TASK-007
title: Minimal RV32I runtime library (soft mul/div/mod)
status: To Do
assignee: []
created_date: '2026-09-14 18:47'
updated_date: '2026-09-15 01:41'
labels:
  - backend
  - runtime
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RV32I has no M extension -- nix-riscv states plainly there are no M/A/F/D/C/V extensions. So every C *, / and % becomes a libcall. Without these, no C program doing arithmetic can run, which makes this a deliverable rather than an optimisation.

See decision-003 and decision-004: the oracle cannot be put into libcall mode, so this path is verified against the emulator rather than against lcc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 __mulsi3, __divsi3, __udivsi3, __modsi3, __umodsi3 implemented in RV32I
- [ ] #2 Written as assembly our own assembler consumes, not hand-assembled bytes
- [ ] #3 Tested on the emulator against a table of signed and unsigned cases including INT_MIN/-1, division by zero behaviour, and both signs of operand
- [ ] #4 Frontend emits these calls where the IR has MULI4/DIVI4/MODI4, and that lowering is tested independently of the oracle
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-003: the instruction selector now calls __mulsi3 and __divsi3 by name, from three rows of poc/03-matcher/rules.nix (reg_muli_libcall, reg_divi_libcall, reg_modi_libcall). __modsi3 has a rule but no caller yet, because lcc's simplifier folded the test case's % away.

poc/03-matcher/runtime.s already contains a naive RV32I __mulsi3 (shift-and-add) and __divsi3 (restoring division over the magnitudes, sign applied after), written only so that PoC's execution test could close the loop. They are NOT this task's deliverable -- they are the thing to replace -- but they are a working reference and, more usefully, the harness around them is: poc/03-matcher/run.sh assembles, links and runs the result in the Nix RV32I emulator and compares against the host compiler on the same C. Point that at a division test corpus and the runtime library gets a real oracle for free.

Gaps in those stubs, all deliberate: division by zero is not handled at all; __divsi3 always runs 32 iterations rather than skipping leading zeros; there is no __udivsi3, __umodsi3 or any 64-bit helper. The signs are the part worth testing hardest -- C requires truncation toward zero, and decision-001 records that Nix's own builtins.div already truncates that way, so a Nix-side reference implementation is one line.

The name to keep an eye on: decision-004 says the oracle runs with mulops_calls=0, so MULI4/DIVI4/MODI4 arrive as ordinary nodes and the LOWERING lives in the rule table, not in the DAG. Nothing else in the compiler knows these are calls.

forward-carried from task-006: the runtime library will be assembled by
poc/04-assembler, and poc/03-matcher/runtime.s already goes through it
unchanged -- block comments, numeric local labels (1:, 2f, 3b), .data, and all.
So a runtime written in the same style needs no new assembler work.

What is available: RV32I plus the usual pseudo-instructions -- mv, li, la, j,
jr, ret, call, tail, nop, neg, not, seqz, snez, sltz, sgtz, beqz/bnez/blez/
bgez/bltz/bgtz, and bgt/ble/bgtu/bleu (which are blt/bge/bltu/bgeu with the
operands SWAPPED -- the swap is the whole content of those four, and getting it
backwards still assembles). 65 mnemonics in all; `asm.mnemonics' is the list.

What it refuses, and why it matters here: a branch further than +-4 KiB throws
rather than relaxing (task-021). __divsi3-style loops are small, but a runtime
that grows a long function will hit it, and the throw names the label and the
distance. Write the branch-heavy parts as short blocks, or take task-021 first.

Also: there are no relocations. Every symbol resolves at layout time, so the
runtime and its callers must be assembled as ONE item list (task-022 if that
ever changes). And there is no .bss -- zero-initialised data is .zero bytes in
.data and costs image space.
<!-- SECTION:NOTES:END -->
