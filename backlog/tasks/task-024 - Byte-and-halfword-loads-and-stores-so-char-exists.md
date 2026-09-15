---
id: TASK-024
title: 'Byte and halfword loads and stores, so char exists'
status: To Do
assignee: []
created_date: '2026-09-15 02:03'
labels:
  - poc
  - matcher
dependencies: []
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
