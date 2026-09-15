---
id: TASK-030
title: Symbol expressions accept only base+N in plain decimal
status: To Do
assignee: []
created_date: '2026-09-15 05:33'
labels:
  - poc
  - assembler
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/04-assembler/asm.nix resolves `sym+N' and `sym-N' with N a plain decimal run of digits (task-023). GNU as accepts more and this assembler refuses each of the extras by name rather than resolving it differently:

  sym+0x8    hexadecimal displacement
  sym + 8    whitespace around the sign
  sym+4+4    more than one term
  sym+08     a leading zero, which GNU as reads as OCTAL

The last one is the reason this is a task rather than a note: reading 08 as decimal agrees with GNU as (8 == 010 octal is false, but +08 decimal is 8 and +08 octal is 8) and reading 010 as decimal does NOT, so a silently permissive parser diverges from the reference assembler on some inputs and not others. Refusing is correct today; supporting the full expression grammar is the work.

Related: poc/04-assembler/parse.nix has its own `parseInt' handling sign and hex, and asm.nix now has `decimalOf'. Two answers to "parse an integer out of an operand" in one PoC. parse.nix imports asm.nix, so the shared one has to live in asm.nix or poc/lib.

Found by the task-023 review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A hexadecimal, spaced or multi-term displacement either assembles to what GNU as assembles it to, or is refused with a diagnostic naming which of the three it is
- [ ] #2 A leading-zero displacement is read as octal, as GNU as reads it, or refused; the differential in progs/ covers a case where octal and decimal differ
- [ ] #3 There is one integer parser in poc/04-assembler, used by both parse.nix and asm.nix
<!-- AC:END -->
