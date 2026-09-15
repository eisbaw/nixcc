---
id: TASK-027
title: 'Slice 1: parse declarations and integer expressions to DAG'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
updated_date: '2026-09-15 09:30'
labels:
  - frontend
  - parser
  - slice
dependencies:
  - TASK-002
  - TASK-011
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
First vertical slice per decision-007. Build the parser and DAG builder in Nix for the subset the backend already compiles: int locals and parameters, the integer binary and unary operators, assignment, calls, return.

This is the slice that turns hello.c rather than hello.sym into the entry point of the closed loop, for programs in this subset. That is the project's headline claim moving from "from the IR down" to "from the C down".

Binding constraints: decision-001 (loop shape, accumulator, substring, deepSeq, overflow throws); memory is ~4kB/token and ~8.5kB/DAG node, so do not hold tokens, AST, DAG and labels live at once without measuring. Read the forward-carried notes on this task and on task-005 before starting -- especially that token values are NOT computed by the lexer (task-011) and that lcc has no compound-assignment tokens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Parser consumes the task-002 lexer's tokens; no second lexer
- [ ] #2 DAG output diffs node-for-node against 'just ir' (rcc-rv32, never raw rcc -target=symbolic) for a corpus of at least 10 C functions in the subset
- [ ] #3 The diff compares node numbering and #n back-references, not just opcodes, since a renumbering bug is exactly what an opcode-only diff misses
- [ ] #4 At least 3 programs in this subset compile from .c and RUN end to end in one nix eval, replacing .sym as the entry point
- [ ] #5 Memory measured and recorded per source line, with tokens/AST/DAG live simultaneously
- [ ] #6 Harness mutation-tested: breaking the parser and breaking the harness each fail distinctly
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FORWARD-CARRIED from the task-023/024/025 batch (commits 5f954f6, 7de656d, 7875e71, bce67ae).

WHAT IS NOW SAFE TO EMIT that was not. The backend takes a global at a constant offset (`ADDRGP4 msg+8'), byte and halfword loads and stores with their conversions, the word forms lcc emits for unsigned int, and a CALLI4 whose result nothing consumes. So a parser in the int subset can emit what lcc emits without hitting a refusal, which was the risk decision-007 was written about.

WHAT STILL REFUSES, so do not emit it and expect it to work: CALLP4 and CALLD4 in any position (task-036) -- CALLP4 is reachable the moment anything returns a pointer; a symbol expression over a compiler-generated NUMERIC base, which is what every string-literal subscript produces (task-032, and it blocks task-028 more than it blocks this); CVUU4 and CVIU4 below width 4; hex, spaced or multi-term symbol expressions (task-030). Every one refuses loudly naming the opcode or the symbol, so you will know.

THE ORACLE DIFF IS HARDER THAN IT LOOKS, and criterion 3 is right to insist. Three things about lcc's listing cost time in this batch:
  * A conversion's DESTINATION width is in the opcode and its SOURCE width is the node's first symbol. CVII4 with a 1 and CVII4 with a 2 are the same opcode and different instructions. If your DAG builder does not write that symbol, the backend cannot pick a rule.
  * lcc types a character constant by its DESTINATION: `buf[0] = '\n'' is CNSTI1, not CNSTI4.
  * A discarded call is a LISTED root that nothing references. The distinction between that and a used one is not in the node, it is in whether anything has it as a kid -- poc/03-matcher/parse.nix computes `usedAsKid' per forest, and poc/05-loop/check.nix now uses exactly that to assert hello.c still discards one.

HARNESS LESSONS, all of them paid for.
  * builtins.tryEval does NOT catch `attribute missing'. Measured: `builtins.tryEval (builtins.getAttr "nope" {})' aborts rather than returning success=false. A must-fail suite cannot classify that error class -- it kills the run. Any guard whose failure mode is a missing attribute needs messages.sh or a check.nix pin instead.
  * A hand-written list of things-that-must-be-true catches a row DELETED from it and never a row added to the code and forgotten. Both reviewers proved that against the same check on the same day. Derive the population where you can.
  * A must-contain pin is worthless if the thing it names is emitted either way. `call wr' passed on the very program it claimed to forbid. Test a pin against the state it is supposed to reject, not only against the state you are in.
  * Never pin register names from poc/03-matcher: they come from the evaluation-depth pool and move when the C's expression shapes move, so they will fail on unchanged source and blame it.
  * `nix flake check' reads the GIT tree. A new file must be git-added before the gate sees it.

MACHINE. The contention guard refused or misfired four times in one day's work, in three distinct ways, on an untouched poc/02-lexer -- see task-035, which now carries all three symptoms. If your gate goes red on a timing ladder, read that task before believing the number.
<!-- SECTION:NOTES:END -->
