---
id: TASK-006
title: Assembler and label layer for RV32
status: To Do
assignee: []
created_date: '2026-09-14 18:47'
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
