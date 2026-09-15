---
id: TASK-024
title: 'Byte and halfword loads and stores, so char exists'
status: In Progress
assignee: []
created_date: '2026-09-15 02:03'
updated_date: '2026-09-15 05:43'
labels:
  - poc
  - matcher
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/rules.nix implements INDIRI4/ASGNI4 and the 4-byte address modes and nothing narrower: there is no rule for INDIRC/ASGNC, no CVTCI/CVTIC, and so no `lb', `lbu', `sb', `lh', `lhu' or `sh'. poc/01-encoder and poc/04-assembler both have all six instructions; only the rule table is missing.

The practical consequence, found while building the headline demo: a C program cannot touch a string. poc/05-loop/hello.c builds its output message a WORD at a time -- four ASCII codes packed little-endian into one int and stored with `sw' -- because that is the narrowest thing compiled code can currently write. That is a fine demonstration of shifts and it is not C.

Needs the CVT opcodes as well as the loads and stores: lcc inserts CVTCI4/CVTIC4 around every char access, and a rule table without them will refuse rather than narrow silently, which is the right failure but still a failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A C function that walks a char array, reads a byte and stores a byte compiles and runs in the Nix emulator with the right result
- [ ] #2 Signed and unsigned char are distinguished: lb against lbu, checked by a case whose answer differs between them
- [ ] #3 Halfwords too, or the rule table says in one place why they are out of scope
- [ ] #4 poc/05-loop's demo can build its message a byte at a time
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan (implementer):
- poc/03-matcher/rules.nix gains, as data only: lb/lbu/lh/lhu loads (INDIRI1/INDIRU1/INDIRI2/INDIRU2), sb/sh stores (ASGNI1/ASGNU1/ASGNI2/ASGNU2), the word forms lcc emits for unsigned int (INDIRU4/ASGNU4), the conversions lcc wraps every narrow access in, and a 1-byte constant (CNSTI1).
- SIGN LIVES IN THE INSTRUCTION, not in a conversion afterwards: lb sign-extends the byte into the whole register and lbu zero-extends it, so signed and unsigned char are two different rows and a case whose answer differs between them is what proves it.
- The widening conversions need the SOURCE width, which lcc writes as the node's own symbol and NOT in the opcode (CVII4 with 1 is from a byte, with 2 from a halfword). burg.nix's predicate vocabulary gains `srcSize' for that -- frontend vocabulary, so it stays target-independent and burg.nix still knows nothing about RISC-V.
- Deliberately NOT done: the fused two-level patterns mips.md uses (reg: CVII4(INDIRI1(addr)) -> one lb). burg.nix matches one level, and the unfused form is correct, just three instructions where one would do. Filed rather than smuggled in.
- New corpus case ir/chars.c: signed and unsigned bytes and halfwords over the SAME data, so lb-against-lbu changes the answer; run in the emulator against the host compiler.
- Halfwords are in scope and implemented, not documented as out of scope.
<!-- SECTION:NOTES:END -->
