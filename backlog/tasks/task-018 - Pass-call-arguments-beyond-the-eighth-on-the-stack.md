---
id: TASK-018
title: Pass call arguments beyond the eighth on the stack
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
RV32 passes the first eight integer arguments in a0-a7 and the rest in the caller's outgoing argument area. poc/03-matcher only knows the register half and throws at the ninth ('emit: argument N does not fit the 8 argument registers'), which is a refusal rather than a miscompile but is also a hard stop for any real C.

This needs an outgoing-argument area in the frame (lcc's own back ends size it from argoffset/maxargoffset during doarg) and an ARG rule that stores to it rather than moving to a register.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A call with more than eight integer arguments compiles
- [ ] #2 The frame reserves an outgoing argument area sized from the widest call in the function
- [ ] #3 A real lcc DAG with a nine-argument call executes and returns what the host compiler gives
- [ ] #4 The refusal in emit.nix's argReg is removed
<!-- AC:END -->
