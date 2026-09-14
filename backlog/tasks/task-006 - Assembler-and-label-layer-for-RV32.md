---
id: TASK-006
title: Assembler and label layer for RV32
status: To Do
assignee: []
created_date: '2026-09-14 18:47'
updated_date: '2026-09-14 19:50'
labels:
  - backend
  - assembler
dependencies:
  - TASK-001
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The encoder takes resolved byte offsets: e.jal "ra" 4. A code generator does not have those -- it has `beq a0, a1, .L3`. The missing layer is an assembler: items (insn / label / data / align), a fold assigning addresses, and a resolve pass.

This is where the real bugs live -- PC-relative base off-by-one, forward references, wrong section -- and it sits between the encoder (task-001) and any code generator. Filed as a blocker on task-004 so that PoC-4 cannot paper over it by hand-computing a twelve-instruction program.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Items are data: insn, label, data bytes, align
- [ ] #2 Address assignment is a linear fold, no ++ accumulation (decision-001)
- [ ] #3 Forward and backward references both resolve from one symbol table
- [ ] #4 PC-relative base is tested explicitly: branch and jal offsets are relative to the branch instruction's own address, and an off-by-one-instruction bug is caught by a test
- [ ] #5 Branch out of range (beyond +-4 KiB) either relaxes to jal or throws with a clear message; whichever is chosen is tested
- [ ] #6 lui/addi constant materialisation is one tested helper, not re-derived per call site, with cases at 0x7ff, 0x800, 0xfffff800, -1 and 0x80000000
- [ ] #7 Differential test: assembled output matches riscv32-none-elf-as for a program using labels
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-002: an assembler is the same shape as a lexer, so reuse the shape.

Label resolution is a sequential pass that emits one value per instruction -- exactly what builtins.foldl' cannot do. Use builtins.genericClosure: it is an iterative worklist in the evaluator, measured linear at constant stack depth (0.07/0.11/0.18/0.35/0.49 s at 25000..400000 steps). Two traps in it: keys must be unique because duplicates are SILENTLY DROPPED, and it forces only 'key', so the operator must deepSeq the item it returns or the field chain grows as deep as the loop and dies with 'stack overflow (possible infinite recursion)' -- measured at 100000 steps, and not as a slowdown first.

Two-pass assembly (measure, then place) is the natural fit: pass one is a genericClosure over instructions carrying a running address, pass two is a plain map now that every label's address is known. No list is ever appended to.

builtins.substring COPIES ITS HAYSTACK -- cost proportional to the string being sliced, not to the slice. Never parse assembly text by repeatedly slicing the source: 20000 four-byte slices cost 0.11 s at 278 kB and 0.84 s at 2.2 MB. Explode to a character list with builtins.split "(.)" (one evaluator call, 10x faster than genList+substring) and cut with concatStringsSep. Better still, do not have assembly text at all: emit instruction records and let the encoder consume them.

The output is a byte list, not a string -- Nix strings cannot hold NUL (decision-001), so an ELF can never be one.

Harness lessons from poc/02-lexer, which are the reason its suite catches things: order the guards so a HARNESS FAULT can never pre-empt a real diagnosis; assert the fields nothing else looks at (addresses and label offsets are this task's equivalent of line numbers, which went unverified in the lexer until a reviewer noticed a lexer answering 'line 1' to everything would pass every test); check what errors SAY and not only that they threw, which needs a shell loop because builtins.tryEval never returns the message; mutation-test the measurement code, not only the code under test; and measure performance in CPU time rather than wall clock, because a wall-clock linearity assertion fails on a busy machine from a change that never happened.
<!-- SECTION:NOTES:END -->
