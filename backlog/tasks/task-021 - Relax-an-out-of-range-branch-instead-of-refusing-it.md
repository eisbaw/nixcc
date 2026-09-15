---
id: TASK-021
title: Relax an out-of-range branch instead of refusing it
status: To Do
assignee: []
created_date: '2026-09-15 01:11'
labels:
  - backend
  - assembler
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/04-assembler refuses a branch further than a B-type offset reaches (+-4 KiB) rather than relaxing it, and says so: it names the label, the distance and the remedy. GNU as does the same, which is why the differential test stays exact. But a real function CAN exceed 4 KiB, and when one does the compiler stops rather than compiles.

The fix is the standard one: an inverted branch over a 'j', which costs four extra bytes. It was not done here because sizing it is a LAYOUT FIXPOINT -- growing one branch moves every address after it, which can push a second branch out of range -- and poc/03-matcher already paid once for an unasserted fixpoint (emit.nix sized the frame in one pass and emitted against it in another, with nothing checking they agreed). Sizes only ever grow, so the iteration terminates; what needs care is asserting that it converged rather than assuming it.

The refusal site is ctx.branchOff in poc/04-assembler/asm.nix and it names this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A branch beyond +-4 KiB is relaxed to an inverted branch over a jal, not refused
- [ ] #2 The relaxation is a fixpoint over layout, and convergence is ASSERTED rather than assumed -- a capped iteration count that throws if it is reached
- [ ] #3 A test has a branch that is in range before relaxation and out of range after another branch grew, so one round of relaxation is provably not enough
- [ ] #4 The differential against GNU as still passes on every program that needs no relaxation, and the programs that do need it are diffed against GNU as's own relaxed output or excluded with a stated reason
<!-- AC:END -->
