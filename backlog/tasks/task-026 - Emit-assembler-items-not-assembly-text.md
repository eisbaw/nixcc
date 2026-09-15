---
id: TASK-026
title: 'Emit assembler items, not assembly text'
status: To Do
assignee: []
created_date: '2026-09-15 02:03'
labels:
  - poc
  - matcher
  - assembler
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The remaining seam inside the single evaluation. poc/03-matcher's rule templates produce TEXT -- `sw %1,%0\n' -- which poc/04-assembler/parse.nix immediately turns back into items. A compiler that never leaves the evaluator has no reason to serialise to assembly and parse it again: it costs a whole front end on the hot path, it is where operand kinds have to be re-derived from how a token looks, and it is the only place in the chain where a value is stringified and re-read.

poc/05-loop shows both halves of the choice today. Its driver and its fault programs are built as items in Nix and handed straight to asm.nix; the compiled function goes through text. Everything else about the two paths is the same, which is what makes the comparison honest.

What has to be decided rather than assumed: a template is a STRING with %-escapes, and that is most of what makes rules.nix readable as a machine description. An item-producing table needs a shape that keeps that -- probably a template that expands to { mnemonic; args } with the escapes as argument positions rather than as characters. Getting this wrong turns a declarative table into code, which is the property TASK-003 was run to establish.

Blocked on nothing; TASK-005 should decide whether it comes before or after the frontend work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 poc/03-matcher's rule table produces assembler items, and poc/04-assembler/parse.nix is not on the path from IR to bytes
- [ ] #2 The rule table is still data: adding an instruction is still adding a row, and no rule contains Nix code that emits
- [ ] #3 The existing corpus produces byte-identical images through the new path, checked against the old one rather than against a new set of expectations
- [ ] #4 parse.nix stays, with its own tests: it is still how a .s file is read, and the differential against GNU as needs it
<!-- AC:END -->
