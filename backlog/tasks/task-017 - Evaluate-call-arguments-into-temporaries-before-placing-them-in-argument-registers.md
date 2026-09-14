---
id: TASK-017
title: >-
  Evaluate call arguments into temporaries before placing them in argument
  registers
status: To Do
assignee: []
created_date: '2026-09-14 20:56'
labels:
  - backend
  - codegen
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher sets up a call's arguments one ARG root at a time, straight into a0, a1, ... An argument whose own evaluation calls something -- 'h(a * a, 1)' on RV32I, where the multiply is a libcall to __mulsi3 -- would destroy the argument registers already placed.

The PoC refuses this rather than emitting it (burg.nix's reduceRoot, 'contains a call, which would clobber the argument registers already placed'), and poc/03-matcher/ir/argcall.c is the real lcc DAG that triggers it. lcc's own back ends evaluate arguments into temporaries and move them into place immediately before the call; doarg() in the .md files is where that lives.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An argument expression containing a call compiles rather than being refused
- [ ] #2 ir/argcall.c moves from the must-fail suite to the execution suite and returns the value the host compiler gives
- [ ] #3 The refusal in burg.nix's reduceRoot is removed, not just widened
<!-- AC:END -->
