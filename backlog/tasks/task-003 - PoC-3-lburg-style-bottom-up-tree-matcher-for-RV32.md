---
id: TASK-003
title: 'PoC-3: lburg-style bottom-up tree matcher for RV32'
status: To Do
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-14 18:46'
labels:
  - poc
  - backend
  - codegen
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement instruction selection as lcc does it: rules as declarative data, matched bottom-up over the DAG with dynamic programming, then reduced to emit instructions.

Kill-risk: this is the single thing that made us pick lcc over tcc. An lburg rule is (nonterminal, tree pattern, cost, template), e.g. `base: ADDI4(reg,acon) "%1(%0)"`. If declarative tree matching does not work well in Nix, the choice of lcc was wrong and we should reconsider before porting 10k lines against it.

Does not need the full rule set. A handful of rules that prove labeling, cost-driven choice, and reduction is enough.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rules are data (nonterminal, pattern, cost, template), not hand-written emission code
- [ ] #2 Bottom-up labeling assigns each DAG node a cost and winning rule per nonterminal
- [ ] #3 Reduction walks the labels and emits RV32 assembly
- [ ] #4 Covers at least CNSTI4, ADDRLP4, ADDRGP4, INDIRI4, ASGNI4, ADDI4, SUBI4, LSHI4, CALLI4, RETI4 and one conditional branch
- [ ] #5 At least one test where two rules match the same subtree and the cheaper one demonstrably wins
- [ ] #6 Emitted assembly for a hand-built DAG assembles cleanly with riscv32-none-elf-as
- [ ] #7 The hand-built DAG is taken from real lcc output ('just ir') for a small C function, not invented
- [ ] #8 Runnable as 'just poc-matcher'
- [ ] #9 Covers MULI4 and DIVI4 as libcalls, not patterns: RV32I has no multiplier, so these lower to __mulsi3/__divsi3 calls (see decision-003)
<!-- AC:END -->
