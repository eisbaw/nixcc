---
id: TASK-023
title: 'A global at a constant offset is refused, not compiled'
status: In Progress
assignee: []
created_date: '2026-09-15 02:02'
updated_date: '2026-09-15 04:47'
labels:
  - poc
  - matcher
  - assembler
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lcc folds `msg[2]' on an `extern int msg[]' into a single node `ADDRGP4 msg+8'. poc/03-matcher's ADDRGP4 rules take the node's symbol verbatim, so this emits `la a0,msg+8', and poc/04-assembler then refuses it: nothing in the unit defines a symbol spelled `msg+8'. A refusal rather than a miscompile, but indexing a global by a constant is ordinary C and the demo in poc/05-loop had to pass its buffer as a parameter to avoid it (see the comment in poc/05-loop/hello.c).

Two places could own the fix. The matcher could split the symbol at the `+' and emit `la' followed by `addi'. The assembler could accept `sym+N' as a symbol expression, which is what GNU as does and which also gets `.word sym+4' in .data. The assembler is the better home: it already resolves every symbol at layout time, and a symbol expression is an assembler concept.

Found by TASK-004.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A C program that reads and writes a global array at a constant index compiles, assembles and runs in the Nix emulator with the right value
- [ ] #2 The offset is resolved from the symbol table at layout time, not hand-computed
- [ ] #3 A must-fail case covers a symbol expression whose base is undefined, with a diagnostic that names the base rather than the whole expression
- [ ] #4 poc/05-loop/hello.c can take its buffer as a global again, and the comment pointing at this task goes away
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan (implementer):
- Own the fix in poc/04-assembler/asm.nix, as the task's own analysis argues: `lookup' first tries an exact symbol-table hit and only then splits a trailing `+N'/`-N' off the operand. Exact-first keeps a label literally named `f-1' working and matches what GNU as does.
- One place, so `la sym+N', `call sym+N', a branch to `L+N' and `.word sym+N' all resolve through the same code path at layout time; nothing is hand-computed.
- poc/04-assembler/parse.nix: widen the `.word'/.half/.byte operand pattern so a symbol expression reaches the assembler instead of being rejected as "neither a number nor a symbol".
- Diagnostic: an undefined BASE is named as the base, not as the whole expression. must-fail case + control, message pinned by messages.sh.
- Differential: put a symbol expression in progs/ so GNU as assembles the same bytes; pin its addresses in cases.nix; add a mutation that breaks the offset and must be caught.
<!-- SECTION:NOTES:END -->
