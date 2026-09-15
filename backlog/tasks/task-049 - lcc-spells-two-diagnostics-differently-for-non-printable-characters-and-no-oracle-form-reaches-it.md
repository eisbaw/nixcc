---
id: TASK-049
title: >-
  lcc spells two diagnostics differently for non-printable characters, and no
  oracle form reaches it
status: To Do
assignee: []
created_date: '2026-09-15 18:55'
labels:
  - frontend
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lcc/src/lex.c's backslash() prints 'unrecognized character escape sequence `\\%c'' when the offending character is printable and 'unrecognized character escape sequence' with no character when it is below space or 0177 or above. The ill-formed-\\x message has the same two spellings.

poc/06-constants/const.nix always interpolates the character. poc/06-constants/oracle.py compares diagnostic TEXT, so this would be caught -- except that no form in oracle.nix contains an escape of a control character, because writing one means putting a raw control byte inside a literal in the generated C. So the divergence is real, untested, and invisible to the differential as it stands.

Small, and it only affects a diagnostic's wording. It is filed because the differential's stated property is that diagnostic text agrees, and this is a known hole in that property rather than an unknown one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An oracle form contains an escape of a non-printable character, and the two sides agree on what they say about it
- [ ] #2 const.nix drops the character from the message in the same cases lcc does
<!-- AC:END -->
